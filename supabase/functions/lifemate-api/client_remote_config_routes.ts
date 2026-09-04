import {
  createClientRemoteConfigStore,
  parseClientRuntimeConfigQuery,
} from "./client_remote_config.ts";
import { json } from "./http.ts";
import { enforceRateLimit } from "./security.ts";

export function createClientRemoteConfigRouteHandler(databaseUrl: string) {
  const store = createClientRemoteConfigStore(databaseUrl);

  return async function clientRemoteConfigRouteHandler(input: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> {
    const { request, path, appUserId } = input;
    if (request.method !== "GET" || path !== "/api/v1/product/runtime-config") {
      return null;
    }
    enforceRateLimit(`runtime-config:${appUserId}`, 120, 60 * 60_000);
    const query = parseClientRuntimeConfigQuery(new URL(request.url));
    return json(await store.snapshot({ appUserId, ...query }));
  };
}
