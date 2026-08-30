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
import { createCommerceSubscriptionStore } from "./commerce_subscription.ts";
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
const growthRoutes = createGrowthRouteHandler(databaseUrl, contactHashingSecret);
const commerceSubscriptions = createCommerceSubscriptionStore(databaseUrl);
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
    if (telemetryWindow) console.info("LifeMate telemetry window", telemetryWindow);
    return withCorrelationId(response, correlationId);
  };

  if (request.method === "OPTIONS") {
    return finish(new Response("ok", { headers: corsHeaders }));
  }

  if (request.method === "GET" && path === "/health") {
    try {
      await db.health();
      return finish(json({status:"ok",database:"ready",service:"lifemate-api",version:releaseVersion}));
    } catch (error) {
      console.error("LifeMate health check failed", {correlationId,...safeError(error)});
      return finish(problem(503,"database_unavailable","Database is not ready.",correlationId),"database");
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
      return finish(problem(error.status,error.code,error.message,correlationId),inferTelemetrySubsystem(error.status,error.code));
    }
    if (isPostgresUnavailable(error)) {
      console.warn("LifeMate database temporarily unavailable", {correlationId,method:request.method,path,...safeError(error)});
      return finish(problem(503,"database_busy","Database is temporarily busy. Please retry.",correlationId),"database");
    }
    if (isPostgresConflict(error)) {
      return finish(problem(409,"database_conflict","The request conflicts with the current state.",correlationId),"database");
    }
    console.error("Unhandled LifeMate API error", {correlationId,method:request.method,path,...safeError(error)});
    return finish(problem(500,"internal_error","The request could not be completed.",correlationId));
  } finally {
    concurrencyLease?.release();
  }
});

async function routeWithIdempotency(request: Request,path: string,auth: AuthenticatedUser): Promise<Response> {
  if (!shouldProtectMutation(request.method,path)) return await route(request,path,auth);
  const idempotencyKey = requireMutationIdempotencyKey(request);
  const body = await request.text();
  const replayableRequest = new Request(request.url,{method:request.method,headers:request.headers,body:body.length===0?undefined:body});
  return await mutationIdempotency.execute(auth.id,`${request.method} ${path}`,idempotencyKey,body,()=>route(replayableRequest,path,auth));
}

async function route(request: Request,path: string,auth: AuthenticatedUser): Promise<Response> {
  if (request.method === "POST" && path === "/api/v1/users/bootstrap") {
    enforceRateLimit(`bootstrap:${auth.id}`,10,60_000);
    const bootstrapped = await db.bootstrapUser(auth,await readJsonObject(request));
    const accountId = String(bootstrapped.id ?? "");
    if (accountId) await identityBridge.syncExternalIdentities(accountId,auth);
    return json(bootstrapped);
  }

  const identity = await db.requireIdentity(auth);
  const growthResponse = await growthRoutes({request,path,appUserId:identity.appUserId});
  if (growthResponse) return growthResponse;

  if (request.method === "GET" && path === "/api/v1/commerce/subscriptions") {
    return json(await commerceSubscriptions.snapshot(identity.appUserId));
  }

  if (request.method === "GET" && path === "/api/v1/capabilities") {
    return json(await authorizationStore.capabilitySnapshot(identity.appUserId));
  }

  if (request.method === "POST" && path === "/api/v1/me/identities/sync") {
    enforceRateLimit(`identity-sync:${identity.appUserId}`,10,60*60_000);
    return json({providers:await identityBridge.syncExternalIdentities(identity.appUserId,auth)});
  }

  if (request.method === "GET" && path === "/api/v1/account/data-export") {
    enforceRateLimit(`account-export:${identity.appUserId}`,3,60*60_000);
    const exported = await dataExport.exportAccountData(identity.appUserId);
    const date = new Date().toISOString().slice(0,10);
    return json(exported,200,{"Content-Disposition":`attachment; filename="lifemate-data-export-${date}.json"`,"X-LifeMate-Export-Schema":portableExportSchemaVersion});
  }

  if (request.method === "GET" && path === "/api/v1/account/deletion-requests/latest") {
    return json(await accountLifecycle.latestDeletionRequest(identity.appUserId));
  }

  if (request.method === "POST" && path === "/api/v1/account/deletion-requests") {
    enforceRateLimit(`account-deletion:${identity.appUserId}`,3,24*60*60_000);
    const deletion = await accountLifecycle.requestDeletion(identity.appUserId);
    const authorizationHeader = request.headers.get("authorization");
    if (authorizationHeader) {
      await fetch(`${supabaseUrl}/auth/v1/logout?scope=global`,{method:"POST",headers:{Authorization:authorizationHeader,apikey:publishableKey},signal:AbortSignal.timeout(5_000)}).catch(()=>undefined);
    }
    return json(deletion,202);
  }

  if (request.method === "GET" && path === "/api/v1/home-snapshot") {
    const url = new URL(request.url);
    const fromDate=url.searchParams.get("fromDate"),toDate=url.searchParams.get("toDate");
    if (!fromDate || !toDate) throw new ApiError(400,"invalid_date_range","fromDate and toDate are required.");
    return json(await db.getHomeSnapshot(identity.appUserId,fromDate,toDate));
  }

  if (request.method === "GET" && path === "/api/v1/me") return json(await db.currentUser(identity));
  if (request.method === "GET" && path === "/api/v1/me/profile") return json(await profiles.getProfile(identity.appUserId));
  if (request.method === "PATCH" && path === "/api/v1/me/profile") return json(await profiles.updateProfile(identity.appUserId,await readJsonObject(request)));

  if (request.method === "PUT" && path === "/api/v1/me/profile/photo") {
    const contentType=normalizeOptional(request.headers.get("content-type"));
    const bytes=new Uint8Array(await request.arrayBuffer());
    if (bytes.byteLength===0 || bytes.byteLength>profilePhotoMaximumBytes) throw new ApiError(400,"profile_photo_invalid","Profile photo is empty or too large.");
    const uploaded=await profilePhotos.upload(identity.appUserId,contentType??"application/octet-stream",bytes);
    return json(await profiles.setPhoto(identity.appUserId,uploaded),201);
  }

  if (request.method === "DELETE" && path === "/api/v1/me/profile/photo") {
    const profile=await profiles.getProfile(identity.appUserId);
    const photoPath=typeof profile.photoStoragePath==="string"?profile.photoStoragePath:null;
    if (photoPath) await profilePhotos.remove(photoPath);
    return json(await profiles.clearPhoto(identity.appUserId));
  }

  if (request.method === "GET" && path === "/api/v1/medications") return json(await db.getMedications(identity.appUserId));
  if (request.method === "POST" && path === "/api/v1/medications") return json(await db.createMedication(identity.appUserId,await readJsonObject(request)),201);
  if (request.method === "GET" && path === "/api/v1/treatment-plans") return json(await db.getTreatmentPlans(identity.appUserId));
  if (request.method === "POST" && path === "/api/v1/treatment-plans") return json(await db.createTreatmentPlan(identity.appUserId,await readJsonObject(request)),201);

  if (request.method === "GET" && path === "/api/v1/care-events") {
    const url=new URL(request.url); const fromDate=url.searchParams.get("fromDate"),toDate=url.searchParams.get("toDate");
    if (!fromDate || !toDate) throw new ApiError(400,"invalid_date_range","fromDate and toDate are required.");
    return json(await careEvents.list(identity.appUserId,fromDate,toDate));
  }
  if (request.method === "POST" && path === "/api/v1/care-events") return json(await careEvents.create(identity.appUserId,await readJsonObject(request)),201);

  if (request.method === "GET" && path === "/api/v1/dose-occurrences") {
    const url=new URL(request.url); const fromDate=url.searchParams.get("fromDate"),toDate=url.searchParams.get("toDate");
    if (!fromDate || !toDate) throw new ApiError(400,"invalid_date_range","fromDate and toDate are required.");
    return json(await db.getDoseOccurrences(identity.appUserId,fromDate,toDate));
  }
  const reportDoseMatch=path.match(/^\/api\/v1\/dose-occurrences\/([^/]+)\/report$/);
  if (request.method === "POST" && reportDoseMatch) return json(await db.reportDose(identity.appUserId,reportDoseMatch[1],await readJsonObject(request)));

  if (request.method === "GET" && path === "/api/v1/care/relationships") return json(await db.getCareRelationships(identity.appUserId));
  if (request.method === "GET" && path === "/api/v1/care/invitations") return json(await db.getOutgoingCareInvitations(identity.appUserId));
  if (request.method === "POST" && path === "/api/v1/care/invitations") return json(await db.createCareInvitation(identity.appUserId,await readJsonObject(request)),201);
  if (request.method === "POST" && path === "/api/v1/care/invitations/qr") return json(await db.createQrCareInvitation(identity.appUserId),201);
  const revokeInvitationMatch=path.match(/^\/api\/v1\/care\/invitations\/([^/]+)$/);
  if (request.method === "DELETE" && revokeInvitationMatch) { await db.revokeCareInvitation(identity.appUserId,revokeInvitationMatch[1]); return new Response(null,{status:204}); }

  if (request.method === "GET" && path === "/api/v1/care/requests") return json(await db.getCareRequests(identity.appUserId));
  if (request.method === "POST" && path === "/api/v1/care/requests") return json(await db.createCareRequest(identity.appUserId,await readJsonObject(request)),201);

  if (request.method === "GET" && path === "/api/v1/women/calendar") {
    if (!womenCalendarPilotEnabled) throw new ApiError(404,"not_found","Resource not found.");
    return json(await womenCalendar.get(identity.appUserId));
  }
  if (request.method === "PUT" && path === "/api/v1/women/calendar") {
    if (!womenCalendarPilotEnabled) throw new ApiError(404,"not_found","Resource not found.");
    return json(await womenCalendar.update(identity.appUserId,await readJsonObject(request)));
  }
  if (request.method === "GET" && path === "/api/v1/women/companion/privacy") return json(await womenCompanionPrivacy.get(identity.appUserId));
  if (request.method === "PUT" && path === "/api/v1/women/companion/privacy") return json(await womenCompanionPrivacy.update(identity.appUserId,await readJsonObject(request)));

  return problem(404,"not_found","Resource not found.",crypto.randomUUID());
}

async function authenticate(request: Request): Promise<AuthenticatedUser> {
  const authorization=request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) throw new ApiError(401,"unauthorized","Authentication is required.");
  const token=authorization.slice("Bearer ".length).trim();
  if (!token) throw new ApiError(401,"unauthorized","Authentication is required.");
  const response=await fetch(`${supabaseUrl}/auth/v1/user`,{headers:{Authorization:`Bearer ${token}`,apikey:publishableKey},signal:AbortSignal.timeout(5_000)});
  if (!response.ok) throw new ApiError(401,"unauthorized","Authentication is invalid.");
  const payload=await response.json() as Record<string,unknown>;
  const id=String(payload.id??"");
  if (!id) throw new ApiError(401,"unauthorized","Authentication is invalid.");
  const email=typeof payload.email==="string"?payload.email:null;
  const identities=Array.isArray(payload.identities)?payload.identities.flatMap((value):ProviderIdentity[]=>{
    if (!value || typeof value!=="object") return [];
    const row=value as Record<string,unknown>;
    const provider=typeof row.provider==="string"?row.provider:null;
    const identityData=row.identity_data&&typeof row.identity_data==="object"?row.identity_data as Record<string,unknown>:{};
    const providerSubject=typeof identityData.sub==="string"?identityData.sub:typeof row.id==="string"?row.id:null;
    return provider&&providerSubject?[{provider,providerSubject}]:[];
  }):[];
  return {id,email,identities};
}

function isPostgresConflict(error: unknown): boolean {
  if (!error || typeof error!=="object") return false;
  const code=String((error as Record<string,unknown>).code??"");
  return code==="23505" || code==="23P01" || code==="40001";
}
