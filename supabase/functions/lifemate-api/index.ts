import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createCareEventStore } from "./care_events.ts";
import { createCareRequestStore } from "./care_requests.ts";
import { createAccountLifecycleStore } from "./account_lifecycle.ts";
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

Deno.serve(async (request: Request) => {
  const correlationId = crypto.randomUUID();
  const path = normalizePath(new URL(request.url).pathname);

  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method === "GET" && path === "/health") {
    try {
      await db.health();
      return json({
        status: "ok",
        database: "ready",
        service: "lifemate-api",
        version: releaseVersion,
      });
    } catch (error) {
      console.error("LifeMate health check failed", {
        correlationId,
        ...safeError(error),
      });
      return problem(
        503,
        "database_unavailable",
        "Database is not ready.",
        correlationId,
      );
    }
  }

  let concurrencyLease;
  try {
    concurrencyLease = requestConcurrency.acquire(request.method, path);
    const auth = await authenticate(request);
    await requestRateLimiter.enforce(request.method, path, auth.id);
    return await routeWithIdempotency(request, path, auth);
  } catch (error) {
    if (error instanceof ApiError) {
      return problem(error.status, error.code, error.message, correlationId);
    }
    if (isPostgresUnavailable(error)) {
      console.warn("LifeMate database temporarily unavailable", {
        correlationId,
        method: request.method,
        path,
        ...safeError(error),
      });
      return problem(
        503,
        "database_unavailable",
        "Database is temporarily unavailable. Retry shortly.",
        correlationId,
      );
    }
    console.error("LifeMate request failed", {
      correlationId,
      method: request.method,
      path,
      ...safeError(error),
    });
    return problem(
      500,
      "internal_error",
      "Unexpected server error.",
      correlationId,
    );
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
  if (request.method === "GET" && path === "/api/v1/capabilities") {
    const identity = await db.requireIdentity(auth);
    return json(await db.capabilities(identity));
  }

  if (request.method === "POST" && path === "/api/v1/users/bootstrap") {
    const body = await readJsonObject(request);
    return json(await db.bootstrapUser(auth, body));
  }

  if (request.method === "GET" && path === "/api/v1/me") {
    const identity = await db.requireIdentity(auth);
    return json(await db.currentUser(identity));
  }

  if (request.method === "GET" && path === "/api/v1/me/profile") {
    const identity = await db.requireIdentity(auth);
    return json(await profiles.get(identity.appUserId));
  }

  if (request.method === "PATCH" && path === "/api/v1/me/profile") {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(await profiles.update(identity.appUserId, body));
  }

  if (request.method === "PUT" && path === "/api/v1/me/profile/photo") {
    const identity = await db.requireIdentity(auth);
    const contentType = normalizeOptional(request.headers.get("content-type"));
    if (!contentType || !/^image\/(?:jpeg|png|webp)$/i.test(contentType)) {
      throw new ApiError(
        415,
        "unsupported_profile_photo_type",
        "Profile photo must be JPEG, PNG or WebP.",
      );
    }
    const contentLength = Number(request.headers.get("content-length") ?? "0");
    if (contentLength > profilePhotoMaximumBytes) {
      throw new ApiError(
        413,
        "profile_photo_too_large",
        "Profile photo exceeds the maximum upload size.",
      );
    }
    const bytes = new Uint8Array(await request.arrayBuffer());
    if (bytes.byteLength === 0 || bytes.byteLength > profilePhotoMaximumBytes) {
      throw new ApiError(
        413,
        "profile_photo_too_large",
        "Profile photo exceeds the maximum upload size.",
      );
    }
    return json(
      await profilePhotos.upload(identity.appUserId, bytes, contentType),
    );
  }

  if (request.method === "DELETE" && path === "/api/v1/me/profile/photo") {
    const identity = await db.requireIdentity(auth);
    await profilePhotos.remove(identity.appUserId);
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (
    request.method === "POST" &&
    path === "/api/v1/me/identities/sync"
  ) {
    const identity = await db.requireIdentity(auth);
    return json(await identityBridge.sync(identity, auth.identities));
  }

  if (
    request.method === "POST" &&
    path === "/api/v1/account/deletion-requests"
  ) {
    const identity = await db.requireIdentity(auth);
    return json(await accountLifecycle.requestDeletion(identity.appUserId), 202);
  }

  if (
    request.method === "GET" &&
    path === "/api/v1/account/deletion-requests/latest"
  ) {
    const identity = await db.requireIdentity(auth);
    return json(await accountLifecycle.latestDeletionRequest(identity.appUserId));
  }

  if (request.method === "GET" && path === "/api/v1/home-snapshot") {
    const identity = await db.requireIdentity(auth);
    const url = new URL(request.url);
    return json(
      await db.homeSnapshot(
        identity.appUserId,
        url.searchParams.get("fromDate"),
        url.searchParams.get("toDate"),
      ),
    );
  }

  if (request.method === "POST" && path === "/api/v1/medications") {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(await db.createMedication(identity.appUserId, body), 201);
  }

  if (request.method === "GET" && path === "/api/v1/medications") {
    const identity = await db.requireIdentity(auth);
    return json(await db.listMedications(identity.appUserId));
  }

  if (request.method === "POST" && path === "/api/v1/treatment-plans") {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(await db.createTreatmentPlan(identity.appUserId, body), 201);
  }

  if (request.method === "GET" && path === "/api/v1/treatment-plans") {
    const identity = await db.requireIdentity(auth);
    return json(await db.listTreatmentPlans(identity.appUserId));
  }

  if (request.method === "POST" && path === "/api/v1/care-events") {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(await careEvents.createCareEvent(identity.appUserId, body), 201);
  }

  if (request.method === "GET" && path === "/api/v1/care-events") {
    const identity = await db.requireIdentity(auth);
    const url = new URL(request.url);
    return json(
      await careEvents.listCareEvents(
        identity.appUserId,
        url.searchParams.get("fromDate"),
        url.searchParams.get("toDate"),
      ),
    );
  }

  if (request.method === "GET" && path === "/api/v1/dose-occurrences") {
    const identity = await db.requireIdentity(auth);
    const url = new URL(request.url);
    return json(
      await db.listDoseOccurrences(
        identity.appUserId,
        url.searchParams.get("fromDate"),
        url.searchParams.get("toDate"),
      ),
    );
  }

  const doseReport = path.match(
    /^\/api\/v1\/dose-occurrences\/([0-9a-f-]{36})\/report$/i,
  );
  if (request.method === "POST" && doseReport) {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(
      await db.reportDose(identity.appUserId, doseReport[1], body),
    );
  }

  if (request.method === "POST" && path === "/api/v1/care/invitations") {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(await db.createInvitation(identity, body), 201);
  }

  if (
    request.method === "POST" &&
    path === "/api/v1/care/invitations/qr"
  ) {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(await db.createQrInvitation(identity, body), 201);
  }

  if (request.method === "GET" && path === "/api/v1/care/invitations") {
    const identity = await db.requireIdentity(auth);
    return json(await db.listInvitations(identity.appUserId));
  }

  if (request.method === "POST" && path === "/api/v1/care/requests") {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(await careRequests.create(identity, body), 201);
  }

  if (
    request.method === "GET" &&
    path === "/api/v1/care/requests/outgoing"
  ) {
    const identity = await db.requireIdentity(auth);
    return json(await careRequests.listOutgoing(identity.appUserId));
  }

  if (
    request.method === "GET" &&
    path === "/api/v1/care/requests/incoming"
  ) {
    const identity = await db.requireIdentity(auth);
    return json(await careRequests.listIncoming(identity));
  }

  const careRequestResponse = path.match(
    /^\/api\/v1\/care\/requests\/([0-9a-f-]{36})\/respond$/i,
  );
  if (request.method === "POST" && careRequestResponse) {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(
      await careRequests.respond(identity, careRequestResponse[1], body),
    );
  }

  const careRequestRevoke = path.match(
    /^\/api\/v1\/care\/requests\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "DELETE" && careRequestRevoke) {
    const identity = await db.requireIdentity(auth);
    await careRequests.revoke(identity.appUserId, careRequestRevoke[1]);
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const invitationAccept = path.match(/^\/api\/v1\/care\/invitations\/accept$/i);
  if (request.method === "POST" && invitationAccept) {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(await db.acceptInvitation(identity, body));
  }

  const invitationRevoke = path.match(
    /^\/api\/v1\/care\/invitations\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "DELETE" && invitationRevoke) {
    const identity = await db.requireIdentity(auth);
    await db.revokeInvitation(identity.appUserId, invitationRevoke[1]);
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const relationshipPermissions = path.match(
    /^\/api\/v1\/care\/relationships\/([0-9a-f-]{36})\/permissions$/i,
  );
  if (request.method === "PATCH" && relationshipPermissions) {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(
      await db.updateRelationshipPermissions(
        identity.appUserId,
        relationshipPermissions[1],
        body,
      ),
    );
  }

  const relationship = path.match(
    /^\/api\/v1\/care\/relationships\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "DELETE" && relationship) {
    const identity = await db.requireIdentity(auth);
    await db.revokeRelationship(identity.appUserId, relationship[1]);
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (request.method === "GET" && path === "/api/v1/care/relationships") {
    const identity = await db.requireIdentity(auth);
    return json(await db.listRelationships(identity.appUserId));
  }

  const caregiverDoseList = path.match(
    /^\/api\/v1\/care\/patients\/([0-9a-f-]{36})\/dose-occurrences$/i,
  );
  if (request.method === "GET" && caregiverDoseList) {
    const identity = await db.requireIdentity(auth);
    return json(
      await db.listCaregiverDoseOccurrences(
        identity.appUserId,
        caregiverDoseList[1],
        new URL(request.url).searchParams.get("fromDate"),
        new URL(request.url).searchParams.get("toDate"),
      ),
    );
  }

  const caregiverCareEvents = path.match(
    /^\/api\/v1\/care\/patients\/([0-9a-f-]{36})\/care-events$/i,
  );
  if (request.method === "GET" && caregiverCareEvents) {
    const identity = await db.requireIdentity(auth);
    return json(
      await careEvents.listCareRecipientEvents(
        identity.appUserId,
        caregiverCareEvents[1],
        new URL(request.url).searchParams.get("fromDate"),
        new URL(request.url).searchParams.get("toDate"),
      ),
    );
  }

  const careEventEdit = path.match(
    /^\/api\/v1\/care-events\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "PATCH" && careEventEdit) {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(
      await edits.updateCareEvent(
        identity.appUserId,
        careEventEdit[1],
        body,
      ),
    );
  }

  if (
    request.method === "GET" &&
    path === "/api/v1/women-calendar/profile"
  ) {
    const identity = await db.requireIdentity(auth);
    return json(await womenCalendar.getProfile(identity.appUserId));
  }

  if (
    request.method === "PATCH" &&
    path === "/api/v1/women-calendar/profile"
  ) {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(await womenCalendar.updateProfile(identity.appUserId, body));
  }

  if (
    request.method === "PUT" &&
    path === "/api/v1/women-calendar/daily-logs"
  ) {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(await womenCalendar.upsertDailyLog(identity.appUserId, body));
  }

  if (
    request.method === "DELETE" &&
    path === "/api/v1/women-calendar/daily-logs"
  ) {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    await womenCalendar.deleteDailyLog(identity.appUserId, body);
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const healthObservation = path.match(
    /^\/api\/v1\/health\/observations\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "DELETE" && healthObservation) {
    const identity = await db.requireIdentity(auth);
    await healthObservations.deleteOwnerObservation(
      identity.appUserId,
      healthObservation[1],
    );
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (
    request.method === "GET" &&
    path === "/api/v1/health/observations"
  ) {
    const identity = await db.requireIdentity(auth);
    const url = new URL(request.url);
    return json(
      await healthObservations.listOwnerObservations(
        identity.appUserId,
        url.searchParams.get("fromDate"),
        url.searchParams.get("toDate"),
      ),
    );
  }

  if (
    request.method === "POST" &&
    path === "/api/v1/health/observations"
  ) {
    const identity = await db.requireIdentity(auth);
    const body = await readJsonObject(request);
    return json(
      await healthObservations.createOwnerObservation(
        identity.appUserId,
        body,
        "wellmate",
      ),
      201,
    );
  }

  throw new ApiError(404, "not_found", "Endpoint was not found.");
}

async function authenticate(request: Request): Promise<AuthenticatedUser> {
  const authorization = request.headers.get("authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new ApiError(401, "authentication_required", "Sign in required.");

  const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      apikey: publishableKey,
      Authorization: `Bearer ${token}`,
    },
  });
  if (!response.ok) {
    throw new ApiError(401, "invalid_token", "Authentication token is invalid.");
  }
  const payload = await response.json();
  const id = String(payload.id ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(id)) {
    throw new ApiError(401, "invalid_token", "Authentication token is invalid.");
  }
  return {
    id,
    email: normalizeOptional(payload.email),
    phone: normalizeOptional(payload.phone),
    userMetadata: payload.user_metadata && typeof payload.user_metadata === "object"
      ? payload.user_metadata
      : {},
    identities: Array.isArray(payload.identities)
      ? payload.identities
        .filter((entry: unknown) => entry && typeof entry === "object")
        .map((entry: any) => ({
          provider: String(entry.provider ?? "").toLowerCase(),
          providerSubject: String(entry.identity_id ?? entry.id ?? ""),
          identityData: entry.identity_data && typeof entry.identity_data === "object"
            ? entry.identity_data
            : {},
          lastSignInAt: normalizeOptional(entry.last_sign_in_at),
        }))
        .filter((entry: ProviderIdentity) =>
          entry.provider.length > 0 && entry.providerSubject.length > 0
        )
      : [],
  };
}
