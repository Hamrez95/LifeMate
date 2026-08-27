import { createClientRemoteConfigRouteHandler } from "./client_remote_config_routes.ts";
import { createExperimentAssignmentRouteHandler } from "./experiment_assignments_routes.ts";
import { createGrowthStore } from "./growth.ts";
import { requireMutationIdempotencyKey } from "./idempotency.ts";
import { json } from "./http.ts";
import { createLegalPrivacyRouteHandler } from "./legal_privacy_routes.ts";
import { createProductTelemetryV2RouteHandler } from "./product_telemetry_v2_routes.ts";
import { createPushRegistrationRouteHandler } from "./push_registrations_routes.ts";
import { enforceRateLimit } from "./security.ts";
import {
  type createSupportAttachmentRuntime,
  createSupportAttachmentRuntimeFromEnvironment,
} from "./support_attachment_storage.ts";
import { createSupportConversationStore } from "./support_conversations.ts";
import { createSupportConversationRouteHandler } from "./support_conversations_routes.ts";
import { readJsonObject } from "./validation.ts";

type AttachmentRuntime = ReturnType<typeof createSupportAttachmentRuntime>;

/// Compatibility entrypoint for delegated authenticated consumer API modules
/// intentionally kept out of the large root router. Delegates remain independent
/// and return null when a route is not theirs; this is not an authorization bypass.
export function createGrowthRouteHandler(
  databaseUrl: string,
  contactHashingSecret: string,
  supportAttachments?: AttachmentRuntime,
) {
  const store = createGrowthStore(databaseUrl, contactHashingSecret);
  const experimentAssignmentRoutes = createExperimentAssignmentRouteHandler(
    databaseUrl,
    contactHashingSecret,
  );
  const legalPrivacyRoutes = createLegalPrivacyRouteHandler(databaseUrl);
  const productTelemetryRoutes = createProductTelemetryV2RouteHandler(databaseUrl);
  const clientRemoteConfigRoutes = createClientRemoteConfigRouteHandler(databaseUrl);
  const pushRegistrationRoutes = createPushRegistrationRouteHandler(databaseUrl);
  const supportRoutes = createSupportConversationRouteHandler(
    createSupportConversationStore(databaseUrl),
    supportAttachments ?? createSupportAttachmentRuntimeFromEnvironment(),
  );

  return async function growthRouteHandler(input: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> {
    const experimentAssignmentResponse = await experimentAssignmentRoutes(input);
    if (experimentAssignmentResponse) return experimentAssignmentResponse;

    const legalPrivacyResponse = await legalPrivacyRoutes(input);
    if (legalPrivacyResponse) return legalPrivacyResponse;

    const productTelemetryResponse = await productTelemetryRoutes(input);
    if (productTelemetryResponse) return productTelemetryResponse;

    const runtimeConfigResponse = await clientRemoteConfigRoutes(input);
    if (runtimeConfigResponse) return runtimeConfigResponse;

    const pushRegistrationResponse = await pushRegistrationRoutes(input);
    if (pushRegistrationResponse) return pushRegistrationResponse;

    const supportResponse = await supportRoutes(input);
    if (supportResponse) return supportResponse;

    const { request, path, appUserId } = input;

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
