import { json } from "./http.ts";
import { createMedicationScheduleOptimizationStore } from "./medication_schedule_optimization_store.ts";
import { enforceRateLimit } from "./security.ts";

export function createMedicationScheduleOptimizationRouteHandler(
  databaseUrl: string,
) {
  const store = createMedicationScheduleOptimizationStore(databaseUrl);

  return async function medicationScheduleOptimizationRouteHandler(input: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> {
    const { request, path, appUserId } = input;

    if (
      request.method === "POST" &&
      path === "/api/v1/medication-schedule-optimizations/nearby/preview"
    ) {
      enforceRateLimit(
        `medication-schedule-preview:${appUserId}`,
        30,
        60 * 60_000,
      );
      return json(await store.preview(appUserId), 201);
    }

    const applyMatch = path.match(
      /^\/api\/v1\/medication-schedule-optimizations\/([0-9a-f-]{36})\/apply$/i,
    );
    if (request.method === "POST" && applyMatch) {
      enforceRateLimit(
        `medication-schedule-apply:${appUserId}`,
        20,
        60 * 60_000,
      );
      return json(await store.apply(appUserId, applyMatch[1]));
    }

    const undoMatch = path.match(
      /^\/api\/v1\/medication-schedule-optimizations\/([0-9a-f-]{36})\/undo$/i,
    );
    if (request.method === "POST" && undoMatch) {
      enforceRateLimit(
        `medication-schedule-undo:${appUserId}`,
        20,
        60 * 60_000,
      );
      return json(await store.undo(appUserId, undoMatch[1]));
    }

    return null;
  };
}
