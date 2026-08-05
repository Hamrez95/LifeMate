import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createCareEventStore } from "./care_events.ts";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { createEditStore } from "./edit_store.ts";
import { corsHeaders, json, problem, safeError } from "./http.ts";
import { createProfileStore } from "./profile.ts";
import {
  createProfilePhotoStorage,
  profilePhotoMaximumBytes,
} from "./profile_photo.ts";
import { createWomenCalendarStore } from "./women_calendar.ts";
import { loadRuntimeConfig } from "./runtime_config.ts";
import { enforceRateLimit } from "./security.ts";
import {
  ApiError,
  normalizeOptional,
  normalizePath,
  readJsonObject,
} from "./validation.ts";

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
const edits = createEditStore(databaseUrl);
const womenCalendar = createWomenCalendarStore(databaseUrl);
const womenCalendarPilotEnabled =
  (Deno.env.get("ENABLE_WOMEN_CALENDAR_PILOT") ?? "true").toLowerCase() !==
    "false";

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

  try {
    const auth = await authenticate(request);
    return await route(request, path, auth);
  } catch (error) {
    if (error instanceof ApiError) {
      return problem(error.status, error.code, error.message, correlationId);
    }
    if (isPostgresConflict(error)) {
      return problem(
        409,
        "database_conflict",
        "The request conflicts with the current state.",
        correlationId,
      );
    }
    console.error("Unhandled LifeMate API error", {
      correlationId,
      method: request.method,
      path,
      ...safeError(error),
    });
    return problem(
      500,
      "internal_error",
      "The request could not be completed.",
      correlationId,
    );
  }
});

async function route(
  request: Request,
  path: string,
  auth: AuthUser,
): Promise<Response> {
  if (request.method === "POST" && path === "/api/v1/users/bootstrap") {
    enforceRateLimit(`bootstrap:${auth.id}`, 10, 60_000);
    return json(await db.bootstrapUser(auth, await readJsonObject(request)));
  }

  const identity = await db.requireIdentity(auth);

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
  if (request.method === "GET" && path === "/api/v1/women-calendar/daily-logs") {
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
  if (request.method === "PUT" && path === "/api/v1/women-calendar/daily-logs") {
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
    return json(await db.listRelationships(identity.appUserId));
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
    return json(
      await womenCalendar.getCareSummary(
        identity.appUserId,
        careWomenCalendarMatch[1],
      ),
    );
  }
  const careWomenSupportMatch = path.match(
    /^\/api\/v1\/care\/patients\/([0-9a-f-]{36})\/women-calendar\/support-actions$/i,
  );
  if (request.method === "POST" && careWomenSupportMatch) {
    requireWomenCalendarPilot();
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

async function authenticate(request: Request): Promise<AuthUser> {
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
