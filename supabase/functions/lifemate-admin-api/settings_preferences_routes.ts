import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import {
  hashConfigureCommandCenterPreferencesRequest,
  parseConfigureCommandCenterPreferencesPayload,
  supportedCommandCenterLocales,
} from "./settings_preferences.ts";
import { createCommandCenterPreferencesStore } from "./settings_preferences_service.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

const SETTINGS_PATH = "/api/v1/settings/preferences";

function checkedStatus(result: Record<string, unknown>): number {
  const httpStatus = Number(result.httpStatus);
  if (!Number.isInteger(httpStatus) || httpStatus < 100 || httpStatus > 599) {
    throw new ApiError(
      503,
      "settings_workflow_unavailable",
      "Settings workflow returned an invalid status.",
    );
  }
  return httpStatus;
}

export function createCommandCenterPreferencesRouteHandler(
  databaseUrl: string,
) {
  const store = createCommandCenterPreferencesStore(databaseUrl);

  return async function commandCenterPreferencesRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = input;
    if (path !== SETTINGS_PATH) return null;

    if (request.method === "GET") {
      requirePermission(admin, "settings.read");
      return json(
        {
          preferences: await store.get(),
          capabilities: {
            mutableFields: ["locale", "timeZone", "displayName"],
            supportedLocales: [...supportedCommandCenterLocales],
            timeZoneValidation: "iana",
            secretsEditable: false,
          },
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (request.method !== "PUT") return null;
    requirePermission(admin, "settings.write");
    const idempotencyKey = requireIdempotencyKey(request);
    const payload = await parseConfigureCommandCenterPreferencesPayload(
      request,
    );
    const result = await store.configure({
      actorAccountId: accountId,
      payload,
      correlationId,
      idempotencyKey,
      requestHash: await hashConfigureCommandCenterPreferencesRequest(payload),
    });
    const httpStatus = checkedStatus(result);
    if (httpStatus >= 400) {
      throw new ApiError(
        httpStatus,
        String(result.code),
        typeof result.message === "string"
          ? result.message
          : "Settings update was not completed.",
      );
    }
    return json(
      {
        preferences: {
          locale: String(result.locale),
          timeZone: String(result.timeZone),
          displayName: String(result.displayName),
          version: Number(result.version),
          updatedAtUtc: String(result.updatedAtUtc),
        },
        replayed: Boolean(result.replayed),
      },
      httpStatus,
      origin,
    );
  };
}
