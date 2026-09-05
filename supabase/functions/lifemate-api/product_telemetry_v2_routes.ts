import { json } from "./http.ts";
import {
  createProductTelemetryV2Store,
  parseProductVersionPresence,
  parseUpdatePolicyQuery,
} from "./product_telemetry_v2.ts";
import { enforceRateLimit } from "./security.ts";
import { readJsonObject } from "./validation.ts";

export function createProductTelemetryV2RouteHandler(databaseUrl: string) {
  const store = createProductTelemetryV2Store(databaseUrl);

  return async function productTelemetryV2RouteHandler(input: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> {
    const { request, path, appUserId } = input;

    if (
      request.method === "POST" &&
      path === "/api/v1/product/version-presence"
    ) {
      enforceRateLimit(`product-version:${appUserId}`, 30, 60 * 60_000);
      const payload = parseProductVersionPresence(
        await readJsonObject(request),
      );
      return json(await store.recordPresence(appUserId, payload), 202);
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/product/update-policy"
    ) {
      const query = parseUpdatePolicyQuery(new URL(request.url));
      return json(
        await store.updatePolicy(
          query.product,
          query.platform,
          query.currentVersion,
        ),
      );
    }

    return null;
  };
}
