import { createPushRegistrationStore } from "./push_registrations.ts";
import { json } from "./http.ts";
import { ApiError, readJsonObject } from "./validation.ts";

const registrationPath =
  /^\/api\/v1\/messaging\/push-registrations\/([0-9a-f-]{36})$/i;

export function createPushRegistrationRouteHandler(databaseUrl: string) {
  const store = createPushRegistrationStore(databaseUrl);
  return async function handlePushRegistrationRoute(input: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> {
    if (
      input.request.method === "POST" &&
      input.path === "/api/v1/messaging/push-registrations"
    ) {
      const result = await store.upsert(
        input.appUserId,
        await readJsonObject(input.request),
      );
      return json(result, Number(result.httpStatus ?? 200));
    }
    const match = input.path.match(registrationPath);
    if (input.request.method === "DELETE" && match) {
      const result = await store.revoke(
        input.appUserId,
        match[1].toLowerCase(),
      );
      return json(result, Number(result.httpStatus ?? 200));
    }
    if (input.path.startsWith("/api/v1/messaging/push-registrations")) {
      throw new ApiError(404, "route_not_found", "API route was not found.");
    }
    return null;
  };
}
