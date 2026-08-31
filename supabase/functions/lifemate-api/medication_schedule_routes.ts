import { json } from "./http.ts";
import { createMedicationScheduleSettingsStore } from "./medication_schedule_settings.ts";
import { enforceRateLimit } from "./security.ts";
import { readJsonObject } from "./validation.ts";

export function createMedicationScheduleRouteHandler(databaseUrl: string) {
  const store = createMedicationScheduleSettingsStore(databaseUrl);

  return async function medicationScheduleRouteHandler(input: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> {
    const { request, path, appUserId } = input;

    if (
      request.method === "GET" &&
      path === "/api/v1/medication-schedule/preferences"
    ) {
      return json(await store.getPreferences(appUserId));
    }

    if (
      request.method === "PATCH" &&
      path === "/api/v1/medication-schedule/preferences"
    ) {
      enforceRateLimit(
        `medication-schedule-preferences:${appUserId}`,
        30,
        60 * 60_000,
      );
      return json(
        await store.updatePreferences(
          appUserId,
          await readJsonObject(request),
        ),
      );
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/medication-schedule/plans"
    ) {
      return json({ items: await store.listPlanTimings(appUserId) });
    }

    const timingMatch = path.match(
      /^\/api\/v1\/treatment-plans\/([0-9a-f-]{36})\/timing$/i,
    );
    if (request.method === "GET" && timingMatch) {
      return json(await store.getPlanTiming(appUserId, timingMatch[1]));
    }
    if (request.method === "PATCH" && timingMatch) {
      enforceRateLimit(
        `treatment-plan-timing:${appUserId}`,
        30,
        60 * 60_000,
      );
      return json(
        await store.updatePlanTiming(
          appUserId,
          timingMatch[1],
          await readJsonObject(request),
        ),
      );
    }

    return null;
  };
}
