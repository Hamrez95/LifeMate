import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createCareEventStore } from "./care_events.ts";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { corsHeaders, json, problem, safeError } from "./http.ts";
import { createProfileStore } from "./profile.ts";
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
  contactHashingSecret,
  releaseVersion,
} = await loadRuntimeConfig();

const db = createLifeMateDatabase(databaseUrl, contactHashingSecret);
const profiles = createProfileStore(databaseUrl);
const careEvents = createCareEventStore(databaseUrl);

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
    return json(await db.currentUser(identity));
  }
  if (request.method === "GET" && path === "/api/v1/me/profile") {
    return json(await profiles.getProfile(identity.appUserId));
  }
  if (request.method === "PATCH" && path === "/api/v1/me/profile") {
    enforceRateLimit(`profile:${identity.appUserId}`, 20, 60 * 60_000);
    return json(
      await profiles.updateProfile(
        identity.appUserId,
        auth,
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

function isPostgresConflict(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const code = String((error as Record<string, unknown>).code ?? "");
  return code === "23505" || code === "23503" || code === "23514";
}
