import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createCareEventStore } from "./care_events.ts";
import { createCareEventSyncStore } from "./care_event_sync.ts";
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
import { createGrowthRouteHandler } from "./growth_routes.ts";
import { createSubscriptionRouteHandler } from "./subscription_routes.ts";
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
const careEventSync = createCareEventSyncStore(databaseUrl);
const careRequests = createCareRequestStore(databaseUrl, contactHashingSecret);
const authorizationStore = createAuthorizationStore(databaseUrl);
const identityBridge = createIdentityBridge(databaseUrl);
const accountLifecycle = createAccountLifecycleStore(databaseUrl);
const dataExport = createDataExportStore(databaseUrl);
const edits = createEditStore(databaseUrl);
const healthObservations = createHealthObservationStore(databaseUrl);
const womenCalendar = createWomenCalendarStore(databaseUrl);
const womenCompanionPrivacy = createWomenCompanionPrivacyStore(databaseUrl);
const growthRoutes = createGrowthRouteHandler(
  databaseUrl,
  contactHashingSecret,
);
const subscriptionRoutes = createSubscriptionRouteHandler(databaseUrl);
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
  const growthResponse = await growthRoutes({
    request,
    path,
    appUserId: identity.appUserId,
  });
  if (growthResponse) return growthResponse;
  const subscriptionResponse = await subscriptionRoutes({
    request,
    path,
    appUserId: identity.appUserId,
  });
  if (subscriptionResponse) return subscriptionResponse;

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

  if (
    request.method === "GET" &&
    path === "/api/v1/women-calendar/companion-privacy"
  ) {
    requireWomenCalendarPilot();
    return json(
      await womenCompanionPrivacy.listOwnerScopes(identity.appUserId),
    );
  }
  const womenCompanionPrivacyMatch = path.match(
    /^\/api\/v1\/women-calendar\/companion-privacy\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "PUT" && womenCompanionPrivacyMatch) {
    requireWomenCalendarPilot();
    enforceRateLimit(
      `women-calendar-companion-privacy:${identity.appUserId}`,
      20,
      60 * 60_000,
    );
    return json(
      await womenCompanionPrivacy.updateOwnerScopes(
        identity.appUserId,
        womenCompanionPrivacyMatch[1],
        await readJsonObject(request),
      ),
    );
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
  const womenEpisodeMatch = path.match(
    /^\/api\/v1\/women-calendar\/episodes\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "PATCH" && womenEpisodeMatch) {
    requireWomenCalendarPilot();
    return json(
      await womenCalendar.updateOwnerEpisode(
        identity.appUserId,
        womenEpisodeMatch[1],
        await readJsonObject(request),
      ),
    );
  }
  if (request.method === "DELETE" && womenEpisodeMatch) {
    requireWomenCalendarPilot();
    await womenCalendar.deleteOwnerEpisode(
      identity.appUserId,
      womenEpisodeMatch[1],
    );
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (
    request.method === "GET" && path === "/api/v1/women-calendar/daily-logs"
  ) {
    requireWomenCalendarPilot();
    const url = new URL(request.url);
    return json(
      await womenCalendar.listOwnerDailyLogs(
        identity.appUserId,
        url.searchParams.get("fromDate"),
        url.searchParams.get("toDate"),
      ),
    );
  }
  if (
    request.method === "PUT" && path === "/api/v1/women-calendar/daily-logs"
  ) {
    requireWomenCalendarPilot();
    enforceRateLimit(
      `women-calendar-daily-log:${identity.appUserId}`,
      40,
      60 * 60_000,
    );
    return json(
      await womenCalendar.upsertOwnerDailyLog(
        identity.appUserId,
        await readJsonObject(request),
      ),
    );
  }

  if (request.method === "GET" && path === "/api/v1/medications") {
    return json(await db.listMedications(identity.appUserId));
  }
  if (request.method === "POST" && path === "/api/v1/medications") {
    enforceRateLimit(`write:${identity.appUserId}`, 30, 60_000);
    return json(
      await db.createMedication(
        identity.appUserId,
        await readJsonObject(request),
      ),
      201,
    );
  }
  if (request.method === "GET" && path === "/api/v1/treatment-plans") {
    return json(await db.listTreatmentPlans(identity.appUserId));
  }
  if (request.method === "POST" && path === "/api/v1/treatment-plans") {
    enforceRateLimit(`write:${identity.appUserId}`, 30, 60_000);
    return json(
      await db.createTreatmentPlan(
        identity.appUserId,
        await readJsonObject(request),
      ),
      201,
    );
  }
  const treatmentPlanMatch = path.match(
    /^\/api\/v1\/treatment-plans\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "PATCH" && treatmentPlanMatch) {
    enforceRateLimit(`edit-treatment:${identity.appUserId}`, 30, 60_000);
    return json(
      await edits.updateTreatmentPlan(
        identity.appUserId,
        treatmentPlanMatch[1],
        await readJsonObject(request),
      ),
    );
  }
  if (request.method === "GET" && path === "/api/v1/dose-occurrences") {
    const url = new URL(request.url);
    return json(
      await db.listDoseOccurrences(
        identity.appUserId,
        url.searchParams.get("fromDate"),
        url.searchParams.get("toDate"),
      ),
    );
  }

  const reportMatch = path.match(
    /^\/api\/v1\/dose-occurrences\/([0-9a-f-]{36})\/report$/i,
  );
  if (request.method === "POST" && reportMatch) {
    enforceRateLimit(`adherence:${identity.appUserId}`, 60, 60_000);
    return json(
      await db.reportDose(
        identity.appUserId,
        reportMatch[1],
        await readJsonObject(request),
      ),
    );
  }

  if (request.method === "GET" && path === "/api/v1/sync/care-events") {
    const url = new URL(request.url);
    return json(
      await careEventSync.pullOwnerCareEvents(
        identity.appUserId,
        url.searchParams.get("cursor"),
        url.searchParams.get("limit"),
      ),
    );
  }

  if (request.method === "GET" && path === "/api/v1/care-events") {
    const url = new URL(request.url);
    return json(
      await careEvents.listCareEvents(
        identity.appUserId,
        url.searchParams.get("fromDate"),
        url.searchParams.get("toDate"),
      ),
    );
  }
  if (request.method === "POST" && path === "/api/v1/care-events") {
    enforceRateLimit(`care-event:${identity.appUserId}`, 30, 60_000);
    return json(
      await careEvents.createCareEvent(
        identity.appUserId,
        await readJsonObject(request),
      ),
      201,
    );
  }
  const ownedCareEventMatch = path.match(
    /^\/api\/v1\/care-events\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "GET" && ownedCareEventMatch) {
    return json(
      await edits.getCareEvent(identity.appUserId, ownedCareEventMatch[1]),
    );
  }
  if (request.method === "PATCH" && ownedCareEventMatch) {
    enforceRateLimit(`edit-care-event:${identity.appUserId}`, 30, 60_000);
    return json(
      await edits.updateCareEvent(
        identity.appUserId,
        ownedCareEventMatch[1],
        await readJsonObject(request),
      ),
    );
  }

  if (request.method === "POST" && path === "/api/v1/care/requests") {
    enforceRateLimit(`care-request:${identity.appUserId}`, 8, 60 * 60_000);
    return json(
      await careRequests.create(identity, await readJsonObject(request)),
      201,
    );
  }
  if (
    request.method === "GET" &&
    path === "/api/v1/care/requests/outgoing"
  ) {
    return json(await careRequests.listOutgoing(identity.appUserId));
  }
  if (
    request.method === "GET" &&
    path === "/api/v1/care/requests/incoming"
  ) {
    const incoming = await careRequests.listIncoming(identity);
    const presented = [];
    for (const item of incoming) {
      const requesterUserId = String(item.requesterUserId ?? "");
      let requesterProfile: Record<string, unknown> = {};
      if (requesterUserId) {
        try {
          requesterProfile = await presentProfile(requesterUserId);
        } catch {
          requesterProfile = {};
        }
      }
      presented.push({
        ...item,
        requesterDisplayName: requesterProfile.displayName ??
          item.requesterDisplayName,
        requesterAvatarKey: requesterProfile.avatarKey ??
          item.requesterAvatarKey ?? null,
        requesterProfilePhotoUrl: requesterProfile.profilePhotoUrl ?? null,
      });
    }
    return json(presented);
  }
  const careRequestMatch = path.match(
    /^\/api\/v1\/care\/requests\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "DELETE" && careRequestMatch) {
    enforceRateLimit(
      `care-request-cancel:${identity.appUserId}`,
      20,
      60 * 60_000,
    );
    await careRequests.cancel(identity.appUserId, careRequestMatch[1]);
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  const careRequestResponseMatch = path.match(
    /^\/api\/v1\/care\/requests\/([0-9a-f-]{36})\/respond$/i,
  );
  if (request.method === "POST" && careRequestResponseMatch) {
    enforceRateLimit(
      `care-request-respond:${identity.appUserId}`,
      20,
      60 * 60_000,
    );
    return json(
      await careRequests.respond(
        identity,
        careRequestResponseMatch[1],
        await readJsonObject(request),
      ),
    );
  }

  if (
    request.method === "POST" &&
    path === "/api/v1/care/invitations/qr"
  ) {
    enforceRateLimit(`qr-invite:${identity.appUserId}`, 10, 60 * 60_000);
    return json(
      await db.createQrInvitation(identity, await readJsonObject(request)),
      201,
    );
  }
  if (request.method === "GET" && path === "/api/v1/care/invitations") {
    return json(await db.listInvitations(identity.appUserId));
  }
  if (request.method === "POST" && path === "/api/v1/care/invitations") {
    enforceRateLimit(`invite:${identity.appUserId}`, 5, 60 * 60_000);
    return json(
      await db.createInvitation(identity, await readJsonObject(request)),
      201,
    );
  }
  const careInvitationMatch = path.match(
    /^\/api\/v1\/care\/invitations\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "DELETE" && careInvitationMatch) {
    enforceRateLimit(
      `care-invitation-revoke:${identity.appUserId}`,
      20,
      60 * 60_000,
    );
    await db.revokeInvitation(identity.appUserId, careInvitationMatch[1]);
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (
    request.method === "POST" &&
    path === "/api/v1/care/invitations/accept"
  ) {
    enforceRateLimit(`accept:${identity.appUserId}`, 10, 60 * 60_000);
    return json(
      await db.acceptInvitation(identity, await readJsonObject(request)),
    );
  }
  if (request.method === "GET" && path === "/api/v1/care/relationships") {
    return json(
      await presentRelationships(
        await db.listRelationships(identity.appUserId),
      ),
    );
  }

  const relationshipPresentationMatch = path.match(
    /^\/api\/v1\/care\/relationships\/([0-9a-f-]{36})\/presentation$/i,
  );
  if (request.method === "PATCH" && relationshipPresentationMatch) {
    enforceRateLimit(
      `care-presentation:${identity.appUserId}`,
      30,
      60 * 60_000,
    );
    return json(
      await db.updateRelationshipPresentation(
        identity.appUserId,
        relationshipPresentationMatch[1],
        await readJsonObject(request),
      ),
    );
  }

  const relationshipPermissionMatch = path.match(
    /^\/api\/v1\/care\/relationships\/([0-9a-f-]{36})\/permissions$/i,
  );
  if (request.method === "PATCH" && relationshipPermissionMatch) {
    requireWomenCalendarPilot();
    enforceRateLimit(`care-permissions:${identity.appUserId}`, 30, 60 * 60_000);
    return json(
      await db.updateRelationshipPermissions(
        identity.appUserId,
        relationshipPermissionMatch[1],
        await readJsonObject(request),
      ),
    );
  }

  const relationshipMatch = path.match(
    /^\/api\/v1\/care\/relationships\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "DELETE" && relationshipMatch) {
    enforceRateLimit(`revoke:${identity.appUserId}`, 20, 60 * 60_000);
    await db.revokeRelationship(identity.appUserId, relationshipMatch[1]);
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const careDoseMatch = path.match(
    /^\/api\/v1\/care\/patients\/([0-9a-f-]{36})\/dose-occurrences$/i,
  );
  if (request.method === "GET" && careDoseMatch) {
    await authorizationStore.requirePersonFeature(
      identity.appUserId,
      careDoseMatch[1],
      "treatment.adherence.read",
      "care.basic",
    );
    const url = new URL(request.url);
    return json(
      await db.listCareDoseOccurrences(
        identity.appUserId,
        careDoseMatch[1],
        url.searchParams.get("fromDate"),
        url.searchParams.get("toDate"),
      ),
    );
  }

  const careEventMatch = path.match(
    /^\/api\/v1\/care\/patients\/([0-9a-f-]{36})\/care-events$/i,
  );
  if (request.method === "GET" && careEventMatch) {
    await authorizationStore.requirePersonFeature(
      identity.appUserId,
      careEventMatch[1],
      "care.events.read",
      "care.basic",
    );
    const url = new URL(request.url);
    return json(
      await careEvents.listCareRecipientEvents(
        identity.appUserId,
        careEventMatch[1],
        url.searchParams.get("fromDate"),
        url.searchParams.get("toDate"),
      ),
    );
  }

  const careWomenCalendarMatch = path.match(
    /^\/api\/v1\/care\/patients\/([0-9a-f-]{36})\/women-calendar$/i,
  );
  if (request.method === "GET" && careWomenCalendarMatch) {
    requireWomenCalendarPilot();
    await authorizationStore.requirePersonFeature(
      identity.appUserId,
      careWomenCalendarMatch[1],
      "women_health.summary.read",
      "care.basic",
    );
    return json(
      await womenCalendar.getCareSummary(
        identity.appUserId,
        careWomenCalendarMatch[1],
      ),
    );
  }

  const careWomenGuidanceImpressionMatch = path.match(
    /^\/api\/v1\/care\/patients\/([0-9a-f-]{36})\/women-calendar\/guidance-impressions$/i,
  );
  if (request.method === "POST" && careWomenGuidanceImpressionMatch) {
    requireWomenCalendarPilot();
    await authorizationStore.requirePersonFeature(
      identity.appUserId,
      careWomenGuidanceImpressionMatch[1],
      "women_health.summary.read",
      "care.basic",
    );
    enforceRateLimit(
      `women-calendar-guidance:${identity.appUserId}`,
      30,
      60 * 60_000,
    );
    return json(
      await womenCalendar.recordGuidanceImpression(
        identity.appUserId,
        careWomenGuidanceImpressionMatch[1],
        await readJsonObject(request),
      ),
      201,
    );
  }

  const careWomenSupportMatch = path.match(
    /^\/api\/v1\/care\/patients\/([0-9a-f-]{36})\/women-calendar\/support-actions$/i,
  );
  if (request.method === "POST" && careWomenSupportMatch) {
    requireWomenCalendarPilot();
    await authorizationStore.requirePersonFeature(
      identity.appUserId,
      careWomenSupportMatch[1],
      "women_health.support.write",
      "care.basic",
    );
    enforceRateLimit(
      `women-calendar-support:${identity.appUserId}`,
      30,
      60 * 60_000,
    );
    return json(
      await womenCalendar.recordCareSupportAction(
        identity.appUserId,
        careWomenSupportMatch[1],
        await readJsonObject(request),
      ),
      201,
    );
  }

  throw new ApiError(404, "route_not_found", "API route was not found.");
}

async function authenticate(request: Request): Promise<AuthenticatedUser> {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ") || authorization.length > 4_096) {
    throw new ApiError(
      401,
      "authorization_missing",
      "Authentication is required.",
    );
  }

  let response: Response;
  try {
    response = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        Authorization: authorization,
        apikey: publishableKey,
      },
      signal: AbortSignal.timeout(10_000),
    });
  } catch {
    throw new ApiError(
      503,
      "identity_provider_unavailable",
      "Authentication service is temporarily unavailable.",
    );
  }
  if (!response.ok) {
    throw new ApiError(
      401,
      "invalid_session",
      "Authentication session is invalid.",
    );
  }

  const value = await response.json();
  if (!value?.id) {
    throw new ApiError(
      401,
      "invalid_session",
      "Authentication session is invalid.",
    );
  }
  return {
    id: value.id,
    email: normalizeOptional(value.email)?.toLowerCase() ?? null,
    phone: normalizeOptional(value.phone),
    userMetadata: value.user_metadata && typeof value.user_metadata === "object"
      ? value.user_metadata
      : {},
    identities: Array.isArray(value.identities)
      ? value.identities as ProviderIdentity[]
      : [],
  };
}

async function presentProfile(
  userId: string,
): Promise<Record<string, unknown>> {
  const profile = await profiles.getProfile(userId);
  const objectPath = await profiles.getProfilePhotoPath(userId);
  let profilePhotoUrl: string | null = null;
  if (objectPath != null) {
    try {
      profilePhotoUrl = await profilePhotos.createSignedUrl(objectPath);
    } catch {
      profilePhotoUrl = null;
    }
  }
  return { ...profile, profilePhotoUrl };
}

async function presentRelationships(
  relationships: Record<string, unknown>[],
): Promise<Record<string, unknown>[]> {
  const cache = new Map<string, Promise<Record<string, unknown>>>();

  const loadProfile = (userId: string) => {
    let pending = cache.get(userId);
    if (pending == null) {
      pending = presentProfile(userId);
      cache.set(userId, pending);
    }
    return pending;
  };

  const safeProfile = async (
    userId: string,
  ): Promise<Record<string, unknown>> => {
    if (!userId) return {};
    try {
      return await loadProfile(userId);
    } catch {
      return {};
    }
  };

  const presented: Record<string, unknown>[] = [];
  for (const relationship of relationships) {
    const patientUserId = String(relationship.patientUserId ?? "");
    const caregiverUserId = String(relationship.caregiverUserId ?? "");
    const patientProfile = await safeProfile(patientUserId);
    const caregiverProfile = await safeProfile(caregiverUserId);
    presented.push({
      ...relationship,
      patientAvatarKey: patientProfile.avatarKey ?? null,
      patientProfilePhotoUrl: patientProfile.profilePhotoUrl ?? null,
      caregiverAvatarKey: caregiverProfile.avatarKey ?? null,
      caregiverProfilePhotoUrl: caregiverProfile.profilePhotoUrl ?? null,
    });
  }
  return presented;
}

function requireWomenCalendarPilot(): void {
  if (!womenCalendarPilotEnabled) {
    throw new ApiError(
      404,
      "women_calendar_feature_disabled",
      "Women calendar pilot is disabled.",
    );
  }
}

function isPostgresConflict(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const code = String((error as Record<string, unknown>).code ?? "");
  return code === "23505" || code === "23503" || code === "23514";
}
