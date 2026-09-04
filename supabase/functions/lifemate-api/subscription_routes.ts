import { getLifeMateSql } from "./database_client.ts";
import { json } from "./http.ts";
import { requireMutationIdempotencyKey } from "./idempotency.ts";
import { createPregnancyRouteHandler } from "./pregnancy_routes.ts";
import { enforceRateLimit } from "./security.ts";
import { ApiError, readJsonObject } from "./validation.ts";

type Row = Record<string, unknown>;
const hash = async (value: string) => {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
};
const result = (value: unknown, fallback: string): Row => {
  if (!value || typeof value !== "object") throw new ApiError(503, fallback, "Subscription service is unavailable.");
  const item = value as Row;
  const status = Number(item.httpStatus);
  if (!Number.isInteger(status)) throw new ApiError(503, fallback, "Subscription service is unavailable.");
  if (status >= 400) throw new ApiError(status, typeof item.code === "string" ? item.code : fallback, "Subscription request could not be completed.");
  return item;
};

export function createSubscriptionRouteHandler(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  // Cocoon routes are composed here so the existing authenticated product-route
  // seam remains stable while Phase 0 freezes contracts. The pregnancy handler
  // owns all health authorization; Commerce state never authorizes pregnancy PHI.
  const pregnancyRoutes = createPregnancyRouteHandler(databaseUrl);
  return async ({ request, path, appUserId }: { request: Request; path: string; appUserId: string }): Promise<Response | null> => {
    const pregnancyResponse = await pregnancyRoutes({ request, path, appUserId });
    if (pregnancyResponse) return pregnancyResponse;

    if (request.method === "GET" && path === "/api/v1/subscription/snapshot") {
      const rows = await sql`select commerce.mobile_subscription_snapshot(${appUserId}::uuid) as result`;
      return json(result(rows[0]?.result, "subscription_snapshot_unavailable"));
    }
    if (request.method === "GET" && path === "/api/v1/subscription/period-access") {
      const rows = await sql`select commerce.period_access_snapshot(${appUserId}::uuid) as result`;
      return json(result(rows[0]?.result, "period_access_unavailable"));
    }
    if (request.method === "POST" && path === "/api/v1/subscription/period-trial") {
      enforceRateLimit(`period-trial:${appUserId}`, 5, 24 * 60 * 60_000);
      const rows = await sql`select commerce.start_or_get_period_trial(${appUserId}::uuid) as result`;
      return json(result(rows[0]?.result, "period_trial_unavailable"));
    }
    if (request.method === "GET" && path === "/api/v1/subscription/gifts/status") {
      const giftIntentId = new URL(request.url).searchParams.get("giftIntentId");
      if (!giftIntentId) throw new ApiError(400, "gift_request_invalid", "Gift reference is required.");
      const rows = await sql`select growth.gift_status_for_purchaser(${appUserId}::uuid,${giftIntentId}::uuid) as result`;
      return json(result(rows[0]?.result, "gift_status_unavailable"));
    }
    if (request.method === "POST" && path === "/api/v1/subscription/gifts/claim") {
      enforceRateLimit(`gift-claim:${appUserId}`, 10, 60 * 60_000);
      const body = await readJsonObject(request);
      const claimToken = typeof body.claimToken === "string" ? body.claimToken.trim() : "";
      if (claimToken.length < 16 || claimToken.length > 512) throw new ApiError(400, "gift_claim_invalid", "Gift claim is invalid.");
      const tokenHash = await hash(claimToken);
      const rows = await sql`select growth.claim_subscription_gift(${appUserId}::uuid,${tokenHash}::varchar) as result`;
      return json(result(rows[0]?.result, "gift_claim_unavailable"));
    }
    if (request.method === "POST" && path === "/api/v1/subscription/period-to-cocoon/convert") {
      enforceRateLimit(`period-cocoon-conversion:${appUserId}`, 5, 24 * 60 * 60_000);
      const body = await readJsonObject(request);
      if (body.confirmed !== true) throw new ApiError(400, "conversion_confirmation_required", "Explicit conversion confirmation is required.");
      const key = requireMutationIdempotencyKey(request);
      const requestHash = await hash(JSON.stringify({ confirmed: true }));
      const rows = await sql`select commerce.convert_period_to_cocoon(${appUserId}::uuid,${key}::varchar,${requestHash}::varchar,${crypto.randomUUID()}::uuid) as result`;
      return json(result(rows[0]?.result, "conversion_unavailable"));
    }
    return null;
  };
}
