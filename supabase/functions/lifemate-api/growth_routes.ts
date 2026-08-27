import { createGrowthStore } from "./growth.ts";
import { requireMutationIdempotencyKey } from "./idempotency.ts";
import { json } from "./http.ts";
import { enforceRateLimit } from "./security.ts";
import type { createSupportAttachmentRuntime } from "./support_attachment_storage.ts";
import { createSupportConversationStore } from "./support_conversations.ts";
import { createSupportConversationRouteHandler } from "./support_conversations_routes.ts";
import { readJsonObject } from "./validation.ts";

type AttachmentRuntime = ReturnType<typeof createSupportAttachmentRuntime>;

export function createGrowthRouteHandler(
  databaseUrl: string,
  contactHashingSecret: string,
  supportAttachments?: AttachmentRuntime,
) {
  const store = createGrowthStore(databaseUrl, contactHashingSecret);
  const supportRoutes = createSupportConversationRouteHandler(
    createSupportConversationStore(databaseUrl),
    supportAttachments,
  );

  return async function growthRouteHandler(input: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> {
    const { request, path, appUserId } = input;

    // This authenticated consumer-extension dispatcher is already invoked only
    // after db.requireIdentity() in index.ts. Keep Support on the same boundary
    // rather than creating a second HTTP entry point or browser database path.
    const supportResponse = await supportRoutes(input);
    if (supportResponse) return supportResponse;

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
