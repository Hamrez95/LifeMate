import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import {
  matchAccountProductVersionsPath,
  parseProductVersionAdoptionQuery,
} from "./product_version_analytics.ts";
import { createProductVersionAnalyticsStore } from "./product_version_analytics_service.ts";

export function createProductVersionAnalyticsRouteHandler(databaseUrl: string) {
  const store = createProductVersionAnalyticsStore(databaseUrl);

  return async function productVersionAnalyticsRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, admin, origin } = input;

    if (
      request.method === "GET" &&
      path === "/api/v1/analytics/product-version-adoption"
    ) {
      requirePermission(admin, "analytics.product_versions.read");
      const query = parseProductVersionAdoptionQuery(new URL(request.url));
      const items = await store.listAdoption(query);
      return json(
        {
          items,
          filters: query,
          definitionVersion: "product-version-adoption-v1",
          source: "analytics.product_version_adoption_v1",
          freshness: {
            status: "fresh",
            asOfUtc: items.reduce<string | null>(
              (latest, item) =>
                latest == null || item.freshnessAtUtc > latest
                  ? item.freshnessAtUtc
                  : latest,
              null,
            ),
          },
        },
        200,
        origin,
      );
    }

    const targetAccountId = matchAccountProductVersionsPath(path);
    if (request.method === "GET" && targetAccountId) {
      requirePermission(admin, "analytics.product_versions.read");
      const items = await store.listAccountVersions(targetAccountId);
      return json(
        {
          accountId: targetAccountId,
          items,
          definitionVersion: "account-product-version-v1",
          source: "analytics.account_product_version_v1",
          freshness: {
            status: "fresh",
            asOfUtc: items.reduce<string | null>(
              (latest, item) =>
                latest == null || item.lastSeenAtUtc > latest
                  ? item.lastSeenAtUtc
                  : latest,
              null,
            ),
          },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/platform/product-update-policies"
    ) {
      requirePermission(admin, "analytics.product_versions.read");
      return json(
        {
          items: await store.listPolicies(),
          definitionVersion: "product-update-policy-v1",
          source: "platform.product_update_policies",
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    return null;
  };
}
