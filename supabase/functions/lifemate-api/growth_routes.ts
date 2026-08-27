import { createGrowthStore } from "./growth.ts";
import { requireMutationIdempotencyKey } from "./idempotency.ts";
import { json } from "./http.ts";
import { createPushRegistrationRouteHandler } from "./push_registrations_routes.ts";
import { enforceRateLimit } from "./security.ts";
import { readJsonObject } from "./validation.ts";

export function createGrowthRouteHandler(
  databaseUrl: string,
  contactHashingSecret: string,
) {
  const store = createGrowthStore(databaseUrl, contactHashingSecret);
  // Growth and messaging registration are both authenticated consumer-extension
  // routes. Keeping them behind this already-wired dispatcher avoids a second
  // HTTP entry point while each domain retains its own store/route module.
  const pushRegistrationRoutes = createPushRegistrationRouteHandler(databaseUrl);

  return async function growthRouteHandler(input: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> {
    const { request, path, appUserId } = input;

    const pushRegistrationResponse = await pushRegistrationRoutes(input);
    if (pushRegistrationResponse) return pushRegistrationResponse;

    if (request.method === "POST" && path === "/api/v1/growth/gifts") {
      enforceRateLimit(`growth-gift:${appUserId}`, 10, 60 * 60_000);
      return json(
        await store.createGift({
          appUserId,
          body: await readJsonObject(request),
          idempotencyKey: requireMutationIdempotencyKey(request),
        }),
        201,
      );
    }

    if (
      request.method === "POST" && path === "/api/v1/growth/referral-code"
    ) {
      enforceRateLimit(`growth-referral-code:${appUserId}`, 5, 24 * 60 * 60_000);
      return json(await store.ensureReferralCode(appUserId));
    }

    if (
      request.method === "POST" && path === "/api/v1/growth/referrals/attribute"
    ) {
      enforceRateLimit(
        `growth-referral-attribute:${appUserId}`,
        5,
        24 * 60 * 60_000,
      );
      return json(
        await store.attributeReferral({
          appUserId,
          body: await readJsonObject(request),
          idempotencyKey: requireMutationIdempotencyKey(request),
        }),
        201,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/growth/advocacy-submissions"
    ) {
      enforceRateLimit(`growth-advocacy:${appUserId}`, 10, 24 * 60 * 60_000);
      return json(
        await store.submitAdvocacy({
          appUserId,
          body: await readJsonObject(request),
          idempotencyKey: requireMutationIdempotencyKey(request),
        }),
        201,
      );
    }

    if (request.method === "GET" && path === "/api/v1/growth/rewards") {
      return json({ items: await store.listRewards(appUserId) });
    }

    return null;
  };
}
