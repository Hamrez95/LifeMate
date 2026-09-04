import { json } from "./http.ts";
import { createMedicationScheduleSleepStore } from "./medication_schedule_sleep_store.ts";
import { enforceRateLimit } from "./security.ts";
import { readJsonObject } from "./validation.ts";

export function createMedicationScheduleSleepRouteHandler(databaseUrl: string) {
  const store = createMedicationScheduleSleepStore(databaseUrl);

  return async function medicationScheduleSleepRouteHandler(input: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> {
    const { request, path, appUserId } = input;

    if (
      request.method === "POST" &&
      path === "/api/v1/medication-schedule-optimizations/sleep/preview"
    ) {
      enforceRateLimit(
        `medication-sleep-preview:${appUserId}`,
        20,
        60 * 60_000,
      );
      return json(
        await store.preview(appUserId, await readJsonObject(request)),
        201,
      );
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/medication-schedule-optimizations/active"
    ) {
      return json({ items: await store.active(appUserId) });
    }

    const actionMatch = path.match(
      /^\/api\/v1\/medication-schedule-optimizations\/([0-9a-f-]{36})\/(apply|undo)$/i,
    );
    if (!actionMatch) return null;

    if (request.method === "POST" && actionMatch[2] === "apply") {
      enforceRateLimit(`medication-sleep-apply:${appUserId}`, 20, 60 * 60_000);
      return json(
        await store.apply(
          appUserId,
          actionMatch[1],
          await readJsonObject(request),
        ),
      );
    }

    if (request.method === "POST" && actionMatch[2] === "undo") {
      enforceRateLimit(`medication-sleep-undo:${appUserId}`, 20, 60 * 60_000);
      return json(await store.undo(appUserId, actionMatch[1]));
    }

    return null;
  };
}
