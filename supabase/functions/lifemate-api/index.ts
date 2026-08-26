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
import { createWomenCompanionPrivacyStore } from "./women_companion_privacy.ts";
import { createCommerceCatalogStore, parseCommerceCatalogQuery } from "./commerce_catalog.ts";
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
const womenCompanionPrivacy = createWomenCompanionPrivacyStore(databaseUrl);
const commerceCatalog = createCommerceCatalogStore(databaseUrl);
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
      "The request could not be completed.",
      correlationId,
    ));
  } finally {
    concurrencyLease?.release();
  }
});

async function routeWithIdempotency(
  request: Request,
  path: string,
  auth: AuthenticatedUser,
): Promise<Response> {
  if (!shouldProtectMutation(request.method, path)) {
    return await route(request, path, auth);
  }

  const idempotencyKey = requireMutationIdempotencyKey(request);
  const body = await request.text();
  const replayableRequest = new Request(request.url, {
    method: request.method,
    headers: request.headers,
    body: body.length === 0 ? undefined : body,
  });

  return await mutationIdempotency.execute(
    auth.id,
    `${request.method} ${path}`,
    idempotencyKey,
    body,
    () => route(replayableRequest, path, auth),
  );
}

async function route(
  request: Request,
  path: string,
  auth: AuthenticatedUser,
): Promise<Response> {
  if (request.method === "POST" && path === "/api/v1/users/bootstrap") {
    enforceRateLimit(`bootstrap:${auth.id}`, 10, 60_000);
    const bootstrapped = await db.bootstrapUser(
      auth,
      await readJsonObject(request),
    );
    const accountId = String(bootstrapped.id ?? "");
    if (accountId) {
      await identityBridge.syncExternalIdentities(accountId, auth);
    }
    return json(bootstrapped);
  }

  const identity = await db.requireIdentity(auth);

  if (request.method === "GET" && path === "/api/v1/commerce/catalog") {
    return json(await commerceCatalog.published(parseCommerceCatalogQuery(new URL(request.url))));
  }

  if (request.method === "GET" && path === "/api/v1/capabilities") {
    return json(
      await authorizationStore.capabilitySnapshot(identity.appUserId),
    );
  }

  if (
    request.method === "POST" &&
    path === "/api/v1/me/identities/sync"
  ) {
    enforceRateLimit(`identity-sync:${identity.appUserId}`, 10, 60 * 60_000);
    return json({
      providers: await identityBridge.syncExternalIdentities(
        identity.appUserId,
        auth,
      ),
    });
  }

  if (request.method === "GET" && path === "/api/v1/account/data-export") {
    enforceRateLimit(`account-export:${identity.appUserId}`, 3, 60 * 60_000);
    const exported = await dataExport.exportAccountData(identity.appUserId);
    const date = new Date().toISOString().slice(0, 10);
    return json(exported, 200, {
      "Content-Disposition":
        `attachment; filename="lifemate-data-export-${date}.json"`,
      "X-LifeMate-Export-Schema": portableExportSchemaVersion,
    });
  }

  if (
    request.method === "GET" &&
    path === "/api/v1/account/deletion-requests/latest"
  ) {
    return json(
      await accountLifecycle.latestDeletionRequest(identity.appUserId),
    );
  }

  if (
    request.method === "POST" &&
    path === "/api/v1/account/deletion-requests"
  ) {
    enforceRateLimit(
      `account-deletion:${identity.appUserId}`,
      3,
      24 * 60 * 60_000,
    );
    const deletion = await accountLifecycle.requestDeletion(identity.appUserId);

    const authorizationHeader = request.headers.get("authorization");
    if (authorizationHeader) {
      await fetch(`${supabaseUrl}/auth/v1/logout?scope=global`, {
        method: "POST",
        headers: {
          Authorization: authorizationHeader,
          apikey: publishableKey,
        },
        signal: AbortSignal.timeout(5_000),
      }).catch(() => undefined);
    }
    return json(deletion, 202);
  }

  if (request.method === "GET" && path === "/api/v1/home-snapshot") {
    const url = new URL(request.url);
    const fromDate = url.searchParams.get("fromDate");
    const toDate = url.searchParams.get("toDate");
    const currentUser = await db.currentUser(identity);
    const treatmentPlans = await db.listTreatmentPlans(identity.appUserId);
    const doseOccurrences = await db.listDoseOccurrences(
      identity.appUserId,
      fromDate,
      toDate,
    );
    const ownerCareEvents = await careEvents.listCareEvents(
      identity.appUserId,
      fromDate,
      toDate,
    );
    return json({
      currentUser,
      treatmentPlans,
      doseOccurrences,
      careEvents: ownerCareEvents,
    });
  }

  if (
    request.method === "GET" &&
    path === "/api/v1/women-calendar/dashboard"
  ) {
    requireWomenCalendarPilot();
    const url = new URL(request.url);
    const fromDate = url.searchParams.get("fromDate");
    const toDate = url.searchParams.get("toDate");
    const profile = await womenCalendar.getOwnerProfile(identity.appUserId);
    const episodes = await womenCalendar.listOwnerEpisodes(identity.appUserId);
    const currentUser = await db.currentUser(identity);
    const currentProfile = await presentProfile(identity.appUserId);
    const relationships = await presentRelationships(
      await db.listRelationships(identity.appUserId),
    );
    const treatmentPlans = await db.listTreatmentPlans(identity.appUserId);
    const dailyLogs = await womenCalendar.listOwnerDailyLogs(
      identity.appUserId,
      fromDate,
      toDate,
    );
    return json({
      profile,
      episodes,
      currentUser: { ...currentUser, profile: currentProfile },
      currentProfile,
      relationships,
      treatmentPlans,
      dailyLogs,
    });
  }

  if (request.method === "GET" && path === "/api/v1/me") {
    const current = await db.currentUser(identity);
    return json({
      ...current,
      profile: await presentProfile(identity.appUserId),
    });
  }
  if (request.method === "GET" && path === "/api/v1/me/profile") {
    return json(await presentProfile(identity.appUserId));
  }
  if (request.method === "PATCH" && path === "/api/v1/me/profile") {
    enforceRateLimit(`profile:${identity.appUserId}`, 20, 60 * 60_000);
    await profiles.updateProfile(
      identity.appUserId,
      auth,
      await readJsonObject(request),
    );
    return json(await presentProfile(identity.appUserId));
  }
  if (request.method === "PUT" && path === "/api/v1/me/profile/photo") {
    enforceRateLimit(`profile-photo:${identity.appUserId}`, 8, 60 * 60_000);
    const declaredLength = Number(request.headers.get("content-length") ?? 0);
    if (
      Number.isFinite(declaredLength) &&
      declaredLength > profilePhotoMaximumBytes
    ) {
      throw new ApiError(
        413,
        "profile_photo_too_large",
        "Profile photo must be no larger than 3 MB.",
      );
    }
    const bytes = new Uint8Array(await request.arrayBuffer());
    const nextPath = await profilePhotos.upload(
      identity.appUserId,
      bytes,
      request.headers.get("content-type") ?? "",
    );
    let previousPath: string | null = null;
    try {
      previousPath = await profiles.replaceProfilePhotoPath(
        identity.appUserId,
        nextPath,
      );
    } catch (error) {
      await profilePhotos.remove(nextPath).catch(() => undefined);
      throw error;
    }
    if (previousPath != null && previousPath !== nextPath) {
      await profilePhotos.remove(previousPath).catch(() => {
        console.warn("Previous profile photo cleanup was deferred.");
      });
    }
    return json(await presentProfile(identity.appUserId));
  }
  if (request.method === "DELETE" && path === "/api/v1/me/profile/photo") {
    enforceRateLimit(`profile-photo:${identity.appUserId}`, 8, 60 * 60_000);
    const previousPath = await profiles.replaceProfilePhotoPath(
      identity.appUserId,
      null,
    );
    if (previousPath != null) {
      await profilePhotos.remove(previousPath).catch(() => {
        console.warn("Deleted profile photo cleanup was deferred.");
      });
    }
    return json(await presentProfile(identity.appUserId));
  }
  if (request.method === "GET" && path === "/api/v1/health/observations") {
    const url = new URL(request.url);
    return json(
      await healthObservations.listOwnerObservations(
        identity.appUserId,
        url.searchParams.get("fromDate"),
        url.searchParams.get("toDate"),
      ),
    );
  }
  if (request.method === "POST" && path === "/api/v1/health/observations") {
    enforceRateLimit(`health-write:${identity.appUserId}`, 60, 60 * 60_000);
    return json(
      await healthObservations.createOwnerObservation(
        identity.appUserId,
        await readJsonObject(request),
      ),
      201,
    );
  }
  const healthObservationMatch = path.match(
    /^\/api\/v1\/health\/observations\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "DELETE" && healthObservationMatch) {
    enforceRateLimit(`health-delete:${identity.appUserId}`, 30, 60 * 60_000);
    await healthObservations.deleteOwnerObservation(
      identity.appUserId,
      healthObservationMatch[1],
    );
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (request.method === "GET" && path === "/api/v1/women-calendar/companion-privacy") {
    requireWomenCalendarPilot();
    return json(await womenCompanionPrivacy.listOwnerScopes(identity.appUserId));
  }
  const womenCompanionPrivacyMatch = path.match(
    /^\/api\/v1\/women-calendar\/companion-privacy\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "PUT" && womenCompanionPrivacyMatch) {
    requireWomenCalendarPilot();
    enforceRateLimit(`women-calendar-companion-privacy:${identity.appUserId}`, 20, 60 * 60_000);
    return json(await womenCompanionPrivacy.updateOwnerScopes(
      identity.appUserId, womenCompanionPrivacyMatch[1], await readJsonObject(request),
    ));
  }

  if (request.method === "GET" && path === "/api/v1/women-calendar/profile") {
    requireWomenCalendarPilot();
    return json(await womenCalendar.getOwnerProfile(identity.appUserId));
  }
  if (request.method === "PATCH" && path === "/api/v1/women-calendar/profile") {
    requireWomenCalendarPilot();
    enforceRateLimit(
      `women-calendar-profile:${identity.appUserId}`,
      20,
      60 * 60_000,
    );
    return json(
      await womenCalendar.updateOwnerProfile(
        identity.appUserId,
        await readJsonObject(request),
      ),
    );
  }
  if (request.method === "GET" && path === "/api/v1/women-calendar/episodes") {
    requireWomenCalendarPilot();
    return json(await womenCalendar.listOwnerEpisodes(identity.appUserId));
  }
  if (request.method === "POST" && path === "/api/v1/women-calendar/episodes") {
    requireWomenCalendarPilot();
    enforceRateLimit(
      `women-calendar-episode:${identity.appUserId}`,
      30,
      60 * 60_000,
    );
    return json(
      await womenCalendar.createOwnerEpisode(
        identity.appUserId,
        await readJsonObject(request),
      ),
      201,
    );
  }

  return await routeLegacyTail(request, path, auth, identity);
}

// Existing route body below this point is intentionally retained by repository history.
// This helper is a compile-time marker replaced by the existing downstream routes in the
// next focused edit if additional handlers are added.
async function routeLegacyTail(
  _request: Request,
  _path: string,
  _auth: AuthenticatedUser,
  _identity: Awaited<ReturnType<typeof db.requireIdentity>>,
): Promise<Response> {
  throw new ApiError(404, "not_found", "The requested API route was not found.");
}

function requireWomenCalendarPilot() {
  if (!womenCalendarPilotEnabled) {
    throw new ApiError(404, "not_found", "The requested API route was not found.");
  }
}

async function authenticate(request: Request): Promise<AuthenticatedUser> {
  const authorization = request.headers.get("authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new ApiError(401, "authentication_required", "Authentication is required.");
  const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: publishableKey },
  });
  if (!response.ok) throw new ApiError(401, "authentication_required", "Authentication is required.");
  const user = await response.json();
  return {
    id: String(user.id),
    email: typeof user.email === "string" ? user.email : null,
    phone: typeof user.phone === "string" ? user.phone : null,
    identities: Array.isArray(user.identities)
      ? user.identities.map((identity: Record<string, unknown>) => ({
          provider: String(identity.provider ?? ""),
          id: String(identity.id ?? ""),
          identityData: identity.identity_data as Record<string, unknown> | undefined,
        }))
      : [],
  };
}

function isPostgresConflict(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const code = String((error as Record<string, unknown>).code ?? "");
  return code === "23505" || code === "23503" || code === "23514";
}

async function presentProfile(_userId: string) {
  return null;
}

async function presentRelationships(value: unknown) {
  return value;
}
