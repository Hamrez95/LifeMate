import type { AdminCapabilitySnapshot } from "./authorization.ts";
import { requirePermission } from "./authorization.ts";
import {
  hashCatalogMutation,
  isCatalogBundleCreatePath,
  isCatalogOfferCreatePath,
  matchCatalogBundlePath,
  matchCatalogOfferPath,
  matchCatalogOfferPricesPath,
  matchCatalogPolicyPath,
  matchCatalogProductPath,
  parseCreateCatalogBundle,
  parseCreateCatalogOffer,
  parseScheduleOfferPrice,
  parseUpdateCatalogBundle,
  parseUpdateCatalogOffer,
  parseUpdateCatalogProduct,
  parseUpsertCatalogPolicy,
} from "./commerce_catalog_v2_mutations.ts";
import { createCommerceCatalogV2MutationStore } from "./commerce_catalog_v2_mutation_service.ts";
import { json } from "./http.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

function status(result: Record<string, unknown>): number {
  const value = Number(result.httpStatus);
  if (!Number.isInteger(value) || value < 100 || value > 599) {
    throw new ApiError(
      503,
      "commerce_catalog_v2_workflow_unavailable",
      "Commerce catalog v2 mutation returned an invalid status.",
    );
  }
  return value;
}

function respond(result: Record<string, unknown>, origin: string | null) {
  const httpStatus = status(result);
  if (httpStatus >= 400) {
    throw new ApiError(
      httpStatus,
      typeof result.code === "string"
        ? result.code
        : "commerce_catalog_v2_mutation_failed",
      typeof result.message === "string"
        ? result.message
        : "Commerce catalog v2 mutation was not completed.",
    );
  }
  const { httpStatus: _ignored, ...body } = result;
  return json(body, httpStatus, origin);
}

export function createCommerceCatalogV2MutationRouteHandler(
  databaseUrl: string,
) {
  const store = createCommerceCatalogV2MutationStore(databaseUrl);
  return async function handler(
    input: {
      request: Request;
      path: string;
      accountId: string;
      admin: AdminCapabilitySnapshot;
      correlationId: string;
      origin: string | null;
    },
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = input;
    if (!path.startsWith("/api/v1/commerce/catalog-v2/")) return null;
    if (request.method !== "POST" && request.method !== "PUT") return null;
    requirePermission(admin, "commerce.catalog.write");
    const idempotencyKey = requireIdempotencyKey(request);

    const productId = matchCatalogProductPath(path);
    if (request.method === "PUT" && productId) {
      const payload = await parseUpdateCatalogProduct(request);
      return respond(
        await store.updateProduct({
          actorAccountId: accountId,
          productId,
          payload,
          correlationId,
          idempotencyKey,
          requestHash: await hashCatalogMutation(
            "commerce.catalog.product.update",
            productId,
            payload,
          ),
        }),
        origin,
      );
    }
    if (request.method === "POST" && isCatalogOfferCreatePath(path)) {
      const payload = await parseCreateCatalogOffer(request);
      return respond(
        await store.createOffer({
          actorAccountId: accountId,
          payload,
          correlationId,
          idempotencyKey,
          requestHash: await hashCatalogMutation(
            "commerce.catalog.offer.create",
            null,
            payload,
          ),
        }),
        origin,
      );
    }
    const offerPriceId = matchCatalogOfferPricesPath(path);
    if (request.method === "POST" && offerPriceId) {
      const payload = await parseScheduleOfferPrice(request);
      return respond(
        await store.scheduleOfferPrice({
          actorAccountId: accountId,
          offerId: offerPriceId,
          payload,
          correlationId,
          idempotencyKey,
          requestHash: await hashCatalogMutation(
            "commerce.catalog.offer.price.schedule",
            offerPriceId,
            payload,
          ),
        }),
        origin,
      );
    }
    const offerId = matchCatalogOfferPath(path);
    if (request.method === "PUT" && offerId) {
      const payload = await parseUpdateCatalogOffer(request);
      return respond(
        await store.updateOffer({
          actorAccountId: accountId,
          offerId,
          payload,
          correlationId,
          idempotencyKey,
          requestHash: await hashCatalogMutation(
            "commerce.catalog.offer.update",
            offerId,
            payload,
          ),
        }),
        origin,
      );
    }
    const policy = matchCatalogPolicyPath(path);
    if (request.method === "PUT" && policy) {
      const payload = await parseUpsertCatalogPolicy(request);
      return respond(
        await store.upsertPolicy({
          actorAccountId: accountId,
          productId: policy.productId,
          policyKey: policy.policyKey,
          payload,
          correlationId,
          idempotencyKey,
          requestHash: await hashCatalogMutation(
            "commerce.catalog.policy.upsert",
            `${policy.productId}:${policy.policyKey}`,
            payload,
          ),
        }),
        origin,
      );
    }
    if (request.method === "POST" && isCatalogBundleCreatePath(path)) {
      const payload = await parseCreateCatalogBundle(request);
      return respond(
        await store.createBundle({
          actorAccountId: accountId,
          payload,
          correlationId,
          idempotencyKey,
          requestHash: await hashCatalogMutation(
            "commerce.catalog.bundle.create",
            null,
            payload,
          ),
        }),
        origin,
      );
    }
    const bundleId = matchCatalogBundlePath(path);
    if (request.method === "PUT" && bundleId) {
      const payload = await parseUpdateCatalogBundle(request);
      return respond(
        await store.updateBundle({
          actorAccountId: accountId,
          bundleId,
          payload,
          correlationId,
          idempotencyKey,
          requestHash: await hashCatalogMutation(
            "commerce.catalog.bundle.update",
            bundleId,
            payload,
          ),
        }),
        origin,
      );
    }
    return null;
  };
}
