import { json } from "./http.ts";
import { createMedicationScheduleAuditWriter } from "./medication_schedule_audit.ts";
import { createMedicationScheduleOptimizationRouteHandler } from "./medication_schedule_optimization_routes.ts";
import { createMedicationScheduleSettingsStore } from "./medication_schedule_settings.ts";
import { createMedicationScheduleSleepRouteHandler } from "./medication_schedule_sleep_routes.ts";
import { enforceRateLimit } from "./security.ts";
import { readJsonObject } from "./validation.ts";

export function createMedicationScheduleRouteHandler(databaseUrl: string) {
  const store = createMedicationScheduleSettingsStore(databaseUrl);
  const audit = createMedicationScheduleAuditWriter(databaseUrl);
  const optimizationRoutes = createMedicationScheduleOptimizationRouteHandler(
    databaseUrl,
  );
  const sleepRoutes = createMedicationScheduleSleepRouteHandler(databaseUrl);

  return async function medicationScheduleRouteHandler(input: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> {
    const sleepResponse = await sleepRoutes(input);
    if (sleepResponse) return sleepResponse;
    const optimizationResponse = await optimizationRoutes(input);
    if (optimizationResponse) return optimizationResponse;

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
      const body = await readJsonObject(request);
      const updated = await store.updatePreferences(appUserId, body);
      await audit.record({
        actorAppUserId: appUserId,
        action: "medication_schedule.preferences.updated",
        resourceType: "medication_schedule_preferences",
        metadata: {
          version: updated.version,
          sleepWindowEnabled: updated.sleepWindowEnabled === true,
          hasSleepWindow: updated.sleepWindowEnabled === true,
          idempotencyKey: request.headers.get("idempotency-key")?.trim() ??
            null,
        },
      });
      return json(updated);
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/medication-schedule/plans"
    ) {
      return json({ items: await store.listPlanTimings(appUserId) });
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/medication-schedule/export"
    ) {
      const [preferences, plans] = await Promise.all([
        store.getPreferences(appUserId),
        store.listPlanTimings(appUserId),
      ]);
      return json({
        schemaVersion: 1,
        exportedAtUtc: new Date().toISOString(),
        preferences,
        plans,
      });
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
      const body = await readJsonObject(request);
      const updated = await store.updatePlanTiming(
        appUserId,
        timingMatch[1],
        body,
      );
      await audit.record({
        actorAppUserId: appUserId,
        action: "medication_schedule.plan_timing.updated",
        resourceType: "treatment_plan",
        resourceId: timingMatch[1],
        metadata: {
          version: updated.version,
          nearbyGroupingEnabled: updated.nearbyGroupingEnabled === true,
          timingLocked: updated.timingLocked === true,
          hasManualSpacing:
            Number(updated.manualSpacingBeforeMinutes ?? 0) > 0 ||
            Number(updated.manualSpacingAfterMinutes ?? 0) > 0,
          hasTimingNote: typeof updated.timingNote === "string" &&
            updated.timingNote.length > 0,
          idempotencyKey: request.headers.get("idempotency-key")?.trim() ??
            null,
        },
      });
      return json(updated);
    }

    return null;
  };
}
