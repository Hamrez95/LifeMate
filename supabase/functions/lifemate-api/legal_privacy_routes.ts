import { json } from "./http.ts";
import {
  createPrivacyPreferenceStore,
  parseLegalAcceptances,
} from "./privacy_preferences.ts";
import { enforceRateLimit } from "./security.ts";
import { ApiError, readJsonObject } from "./validation.ts";

export function createLegalPrivacyRouteHandler(databaseUrl: string) {
  const store = createPrivacyPreferenceStore(databaseUrl);

  return async function legalPrivacyRouteHandler(input: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> {
    const { request, path, appUserId } = input;

    if (request.method === "GET" && path === "/api/v1/account/registration") {
      return json(await store.registrationStatus(appUserId));
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/account/registration/legal-acceptance"
    ) {
      enforceRateLimit(`legal-acceptance:${appUserId}`, 10, 60 * 60_000);
      const body = await readJsonObject(request);
      const acceptances = parseLegalAcceptances(body.acceptances);
      await store.assertAcceptancesCurrent(acceptances);
      return json(await store.finalizeRegistration(appUserId, acceptances));
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/account/privacy-preferences"
    ) {
      return json({ items: await store.preferences(appUserId) });
    }

    const preferenceMatch = path.match(
      /^\/api\/v1\/account\/privacy-preferences\/([a-z][a-z0-9._-]{2,79})$/,
    );
    if (request.method === "PATCH" && preferenceMatch) {
      enforceRateLimit(`privacy-preference:${appUserId}`, 30, 60 * 60_000);
      const body = await readJsonObject(request);
      if (typeof body.enabled !== "boolean") {
        throw new ApiError(
          400,
          "privacy_preference_invalid",
          "enabled must be a boolean.",
        );
      }
      return json(
        await store.setPreference(
          appUserId,
          preferenceMatch[1],
          body.enabled,
        ),
      );
    }

    return null;
  };
}
