import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createCareEventStore } from "./care_events.ts";
import { createCareRequestStore } from "./care_requests.ts";
import { createAccountLifecycleStore } from "./account_lifecycle.ts";
import {
  createDataExportStore,
  portableExportSchemaVersion,
} from "./data_export.ts";
import { createAuthorizationStore } from "./authorization.ts";
import {
  createIdentityBridge,
  type ProviderIdentity,
} from "./identity_bridge.ts";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { isPostgresUnavailable } from "./database_client.ts";
import { createEditStore } from "./edit_store.ts";
import { createHealthObservationStore } from "./health_observations.ts";
import { corsHeaders, json, problem, safeError } from "./http.ts";
import {
  ApiObservability,
  inferTelemetrySubsystem,
  type TelemetrySubsystem,
  withCorrelationId,
} from "./observability.ts";
import { createProfileStore } from "./profile.ts";
import {
  createProfilePhotoStorage,
  profilePhotoMaximumBytes,
} from "./profile_photo.ts";
import { createWomenCalendarStore } from "./women_calendar.ts";
import { loadRuntimeConfig } from "./runtime_config.ts";
import { createRequestRateLimiterFromEnvironment } from "./rate_limit.ts";
import { createRequestConcurrencyGateFromEnvironment } from "./concurrency.ts";
import {
  createMutationIdempotencyStore,
  requireMutationIdempotencyKey,
  shouldProtectMutation,
} from "./idempotency.ts";
import { enforceRateLimit } from "./security.ts";
import {
  ApiError,
  normalizeOptional,
  normalizePath,
  readJsonObject,
} from "./validation.ts";

type AuthenticatedUser = AuthUser & {
  identities: ProviderIdentity[];
};

const {
  databaseUrl,
  databaseTransport,
  transactionPoolerRequired,
  supabaseUrl,
  publishableKey,
  storageServiceKey,
  contactHashingSecret,
  releaseVersion,
} = await loadRuntimeConfig();

const db = createLifeMateDatabase(databaseUrl, contactHashingSecret);
const profiles = createProfileStore(databaseUrl);
const profilePhotos = createProfilePhotoStorage(
  supabaseUrl,
  storageServiceKey,
);
const careEvents = createCareEventStore(databaseUrl);
const careRequests = createCareRequestStore(databaseUrl, contactHashingSecret);
const authorizationStore = createAuthorizationStore(databaseUrl);
const identityBridge = createIdentityBridge(databaseUrl);
const accountLifecycle = createAccountLifecycleStore(databaseUrl);
const dataExport = createDataExportStore(databaseUrl);
const edits = createEditStore(databaseUrl);
const healthObservations = createHealthObservationStore(databaseUrl);
const womenCalendar = createWomenCalendarStore(databaseUrl);
const womenCalendarPilotEnabled =
  (Deno.env.get("ENABLE_WOMEN_CALENDAR_PILOT") ?? "true").toLowerCase() !==
    "false";
const requestRateLimiter = createRequestRateLimiterFromEnvironment();
const requestConcurrency = createRequestConcurrencyGateFromEnvironment();
const mutationIdempotency = createMutationIdempotencyStore(
  databaseUrl,
  contactHashingSecret,
);
const apiObservability = new ApiObservability("lifemate-api", releaseVersion);

Deno.serve(async (request: Request) => {
  const correlationId = crypto.randomUUID();
  const path = normalizePath(new URL(request.url).pathname);
  const startedAt = performance.now();
  const finish = (
    response: Response,
    subsystem: TelemetrySubsystem = "application",
  ): Response => {
    const telemetryWindow = apiObservability.record({
      method: request.method,
      path,
      status: response.status,
      controlledOverload: response.status === 429 ||
        (response.status === 503 && response.headers.has("Retry-After")),
      durationMs: performance.now() - startedAt,
      subsystem,
      concurrency: requestConcurrency.snapshot(),
      rateLimiter: requestRateLimiter.snapshot(),
    });
    if (telemetryWindow) {
      console.info("LifeMate telemetry window", telemetryWindow);
    }
    return withCorrelationId(response, correlationId);
  };

  if (request.method === "OPTIONS") {
    return finish(new Response("ok", { headers: corsHeaders }));
  }

  if (request.method === "GET" && path === "/health") {
    try {
      await db.health();
      return finish(json({
        status: "ok",
        database: "ready",
        databaseTransport,
        transactionPoolerRequired,
        service: "lifemate-api",
        version: releaseVersion,
      }));
    } catch (error) {
      console.error("LifeMate health check failed", {
        correlationId,
        ...safeError(error),
      });
      return finish(
        problem(
          503,
          "database_unavailable",
          "Database is not ready.",
          correlationId,
        ),
        "database",
      );
    }
  }

  let concurrencyLease;
  try {
    concurrencyLease = requestConcurrency.acquire(request.method, path);
    const auth = await authenticate(request);
    await requestRateLimiter.enforce(request.method, path, auth.id);
    return finish(await routeWithIdempotency(request, path, auth));
  } catch (error) {
    if (error instanceof ApiError) {
      return finish(
        problem(error.status, error.code, error.message, correlationId),
        inferTelemetrySubsystem(error.status, error.code),
      );
    }
    if (isPostgresUnavailable(error)) {
      console.warn("LifeMate database temporarily unavailable", {
        correlationId,
        method: request.method,
        path,
        ...safeError(error),
      });
      return finish(
        problem(
          503,
          "database_busy",
          "Database is temporarily busy. Please retry.",
          correlationId,
        ),
        "database",
      );
    }
    if (isPostgresConflict(error)) {
      return finish(
        problem(
          409,
          "database_conflict",
          "The request conflicts with the current state.",
          correlationId,
        ),
        "database",
      );
    }
    console.error("Unhandled LifeMate API error", {
      correlationId,
      method: request.method,
      path,
      ...safeError(error),
    });
    return finish(problem(
      500,
      "internal_error",
      "Unexpected server error.",
      correlationId,
    ));
  } finally {
    concurrencyLease?.release();
  }
});

async function authenticate(request: Request): Promise<AuthenticatedUser> {
  const authorization = request.headers.get("authorization")?.trim() ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    throw new ApiError(401, "authorization_missing", "Authentication required.");
  }

  const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      Authorization: authorization,
      apikey: publishableKey,
    },
    signal: AbortSignal.timeout(5_000),
  });
  if (!response.ok) {
    throw new ApiError(401, "invalid_session", "Authentication failed.");
  }
  const payload = await response.json();
  if (!payload || typeof payload !== "object") {
    throw new ApiError(401, "invalid_session", "Authentication failed.");
  }
  const id = normalizeOptional((payload as Record<string, unknown>).id);
  if (!id) throw new ApiError(401, "invalid_session", "Authentication failed.");
  const email = normalizeOptional((payload as Record<string, unknown>).email);
  const phone = normalizeOptional((payload as Record<string, unknown>).phone);
  const identities = Array.isArray((payload as Record<string, unknown>).identities)
    ? ((payload as Record<string, unknown>).identities as unknown[])
      .filter((value): value is Record<string, unknown> =>
        Boolean(value && typeof value === "object")
      )
      .map((identity) => ({
        provider: normalizeOptional(identity.provider) ?? "unknown",
        providerUserId: normalizeOptional(identity.id) ?? id,
      }))
    : [];

  return { id, email, phone, identities };
}

async function routeWithIdempotency(
  request: Request,
  path: string,
  auth: AuthenticatedUser,
): Promise<Response> {
  const method = request.method.toUpperCase();
  if (!shouldProtectMutation(method, path)) {
    return route(request, path, auth);
  }

  const key = requireMutationIdempotencyKey(request);
  const claimed = await mutationIdempotency.claim(auth.id, method, path, key);
  if (claimed.state === "replayed") {
    return json(claimed.responseBody, claimed.statusCode, {
      "X-Idempotency-Replayed": "true",
    });
  }
  if (claimed.state === "in_progress") {
    throw new ApiError(
      409,
      "idempotency_in_progress",
      "An identical request is already being processed.",
    );
  }

  try {
    const response = await route(request, path, auth);
    const responseBody = await response.clone().json().catch(() => null);
    await mutationIdempotency.complete(
      auth.id,
      method,
      path,
      key,
      response.status,
      responseBody,
    );
    return response;
  } catch (error) {
    await mutationIdempotency.release(auth.id, method, path, key).catch(() => {});
    throw error;
  }
}

async function route(
  request: Request,
  path: string,
  auth: AuthenticatedUser,
): Promise<Response> {
  if (request.method === "POST" && path === "/api/v1/users/bootstrap") {
    const payload = await readJsonObject(request);
    return json(await db.bootstrapUser(auth, payload), 200);
  }

  if (request.method === "GET" && path === "/api/v1/me") {
    return json(await db.me(auth.id), 200);
  }

  if (request.method === "PATCH" && path === "/api/v1/me") {
    return json(await db.updateMe(auth.id, await readJsonObject(request)), 200);
  }

  if (request.method === "GET" && path === "/api/v1/me/profile") {
    return json(await profiles.get(auth.id), 200);
  }

  if (request.method === "PUT" && path === "/api/v1/me/profile") {
    return json(await profiles.update(auth.id, await readJsonObject(request)), 200);
  }

  if (request.method === "GET" && path === "/api/v1/me/profile/photo") {
    const profile = await profiles.get(auth.id);
    return json({
      profilePhotoPath: profile.profilePhotoPath,
      signedUrl: profile.profilePhotoPath
        ? await profilePhotos.createSignedReadUrl(profile.profilePhotoPath)
        : null,
    });
  }

  if (request.method === "PUT" && path === "/api/v1/me/profile/photo") {
    const contentLength = Number(request.headers.get("content-length") ?? "0");
    if (
      !Number.isFinite(contentLength) ||
      contentLength < 1 ||
      contentLength > profilePhotoMaximumBytes
    ) {
      throw new ApiError(
        413,
        "profile_photo_too_large",
        "Profile photo payload is invalid or too large.",
      );
    }
    const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
    if (!contentType.startsWith("image/")) {
      throw new ApiError(
        415,
        "profile_photo_type_invalid",
        "Profile photo must be an image.",
      );
    }
    const bytes = new Uint8Array(await request.arrayBuffer());
    const previous = await profiles.get(auth.id);
    const stored = await profilePhotos.replaceProfilePhoto({
      accountId: auth.id,
      bytes,
      contentType,
      previousPath: previous.profilePhotoPath,
    });
    await profiles.setPhotoPath(auth.id, stored.path);
    return json({ profilePhotoPath: stored.path, signedUrl: stored.signedUrl }, 200);
  }

  if (request.method === "DELETE" && path === "/api/v1/me/profile/photo") {
    const previous = await profiles.get(auth.id);
    if (previous.profilePhotoPath) {
      await profilePhotos.remove(previous.profilePhotoPath);
    }
    await profiles.setPhotoPath(auth.id, null);
    return json({ profilePhotoPath: null }, 200);
  }

  if (request.method === "GET" && path === "/api/v1/account/data-export") {
    return json(await dataExport.exportForAccount(auth.id), 200, {
      "X-LifeMate-Export-Schema": portableExportSchemaVersion,
    });
  }

  if (request.method === "POST" && path === "/api/v1/account/deletion-requests") {
    return json(await accountLifecycle.requestDeletion(auth.id), 202);
  }

  if (request.method === "POST" && path === "/api/v1/me/identities/sync") {
    return json(await identityBridge.sync(auth), 200);
  }

  if (request.method === "GET" && path === "/api/v1/home-snapshot") {
    return json(await db.homeSnapshot(auth.id), 200);
  }

  if (request.method === "GET" && path === "/api/v1/health-observations") {
    const url = new URL(request.url);
    return json(
      await healthObservations.listOwnerObservations(
        auth.id,
        url.searchParams.get("fromDate"),
        url.searchParams.get("toDate"),
      ),
      200,
    );
  }

  if (request.method === "POST" && path === "/api/v1/health-observations") {
    return json(
      await healthObservations.createOwnerObservation(
        auth.id,
        await readJsonObject(request),
      ),
      201,
    );
  }

  const observationDelete = path.match(
    /^\/api\/v1\/health-observations\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "DELETE" && observationDelete) {
    await healthObservations.deleteOwnerObservation(auth.id, observationDelete[1]);
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (path.startsWith("/api/v1/women-calendar")) {
    if (!womenCalendarPilotEnabled) {
      throw new ApiError(404, "feature_not_found", "Feature is not enabled.");
    }
    return routeWomenCalendar(request, path, auth);
  }

  if (path.startsWith("/api/v1/care/requests")) {
    return routeCareRequests(request, path, auth);
  }

  if (path.startsWith("/api/v1/care/events")) {
    return routeCareEvents(request, path, auth);
  }

  if (path.startsWith("/api/v1/care/authorization")) {
    return routeAuthorization(request, path, auth);
  }

  if (path.startsWith("/api/v1/edit")) {
    return routeEdits(request, path, auth);
  }

  if (path.startsWith("/api/v1")) {
    return routeLegacyApi(request, path, auth);
  }

  throw new ApiError(404, "not_found", "Route not found.");
}

async function routeWomenCalendar(
  request: Request,
  path: string,
  auth: AuthenticatedUser,
): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === "GET" && path === "/api/v1/women-calendar/dashboard") {
    return json(
      await womenCalendar.dashboard(
        auth.id,
        url.searchParams.get("fromDate"),
        url.searchParams.get("toDate"),
      ),
    );
  }
  if (request.method === "POST" && path === "/api/v1/women-calendar/cycle-start") {
    return json(
      await womenCalendar.startCycle(auth.id, await readJsonObject(request)),
      201,
    );
  }
  if (request.method === "POST" && path === "/api/v1/women-calendar/logs") {
    return json(
      await womenCalendar.createLog(auth.id, await readJsonObject(request)),
      201,
    );
  }
  const logDelete = path.match(
    /^\/api\/v1\/women-calendar\/logs\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "DELETE" && logDelete) {
    await womenCalendar.deleteLog(auth.id, logDelete[1]);
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method === "PUT" && path === "/api/v1/women-calendar/settings") {
    return json(
      await womenCalendar.updateSettings(auth.id, await readJsonObject(request)),
    );
  }
  throw new ApiError(404, "not_found", "Route not found.");
}

async function routeCareRequests(
  request: Request,
  path: string,
  auth: AuthenticatedUser,
): Promise<Response> {
  if (request.method === "GET" && path === "/api/v1/care/requests") {
    return json(await careRequests.list(auth.id), 200);
  }
  if (request.method === "POST" && path === "/api/v1/care/requests") {
    return json(await careRequests.create(auth.id, await readJsonObject(request)), 201);
  }
  const decision = path.match(/^\/api\/v1\/care\/requests\/([0-9a-f-]{36})\/(accept|reject)$/i);
  if (request.method === "POST" && decision) {
    return json(
      await careRequests.decide(auth.id, decision[1], decision[2] as "accept" | "reject"),
      200,
    );
  }
  throw new ApiError(404, "not_found", "Route not found.");
}

async function routeCareEvents(
  request: Request,
  path: string,
  auth: AuthenticatedUser,
): Promise<Response> {
  if (request.method === "GET" && path === "/api/v1/care/events") {
    const url = new URL(request.url);
    return json(
      await careEvents.list(
        auth.id,
        url.searchParams.get("patientId"),
        url.searchParams.get("from"),
        url.searchParams.get("to"),
      ),
    );
  }
  if (request.method === "POST" && path === "/api/v1/care/events") {
    return json(await careEvents.create(auth.id, await readJsonObject(request)), 201);
  }
  throw new ApiError(404, "not_found", "Route not found.");
}

async function routeAuthorization(
  request: Request,
  path: string,
  auth: AuthenticatedUser,
): Promise<Response> {
  if (request.method === "GET" && path === "/api/v1/care/authorization") {
    const url = new URL(request.url);
    return json(
      await authorizationStore.get(auth.id, url.searchParams.get("patientId")),
    );
  }
  throw new ApiError(404, "not_found", "Route not found.");
}

async function routeEdits(
  request: Request,
  path: string,
  auth: AuthenticatedUser,
): Promise<Response> {
  if (request.method === "POST" && path === "/api/v1/edit/medication") {
    return json(await edits.updateMedication(auth.id, await readJsonObject(request)), 200);
  }
  if (request.method === "POST" && path === "/api/v1/edit/treatment-plan") {
    return json(await edits.updateTreatmentPlan(auth.id, await readJsonObject(request)), 200);
  }
  throw new ApiError(404, "not_found", "Route not found.");
}

async function routeLegacyApi(
  request: Request,
  path: string,
  auth: AuthenticatedUser,
): Promise<Response> {
  return db.routeLegacy(request, path, auth);
}

function isPostgresConflict(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const code = String((error as Record<string, unknown>).code ?? "");
  return code === "23503" || code === "23505";
}
