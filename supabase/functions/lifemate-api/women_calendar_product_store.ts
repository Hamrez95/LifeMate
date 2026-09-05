import { createWomenCalendarRichPeriodStore } from "./women_calendar_rich_period.ts";
import { createWomenInsightPreferencesStore } from "./women_insight_preferences_store.ts";
import { ApiError } from "./validation.ts";

export function createWomenCalendarProductStore(databaseUrl: string) {
  const base = createWomenCalendarRichPeriodStore(databaseUrl);
  const insightPreferences = createWomenInsightPreferencesStore(databaseUrl);

  async function getOwnerProfile(
    appUserId: string,
  ): Promise<Record<string, unknown>> {
    return {
      ...await base.getOwnerProfile(appUserId),
      insightPreferences: await insightPreferences.get(appUserId),
    };
  }

  async function updateOwnerProfile(
    appUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    if (body.insightPreferences != null) {
      if (
        typeof body.insightPreferences !== "object" ||
        Array.isArray(body.insightPreferences)
      ) {
        throw new ApiError(
          400,
          "invalid_cycle_insight_preferences",
          "insightPreferences must be an object.",
        );
      }
      await insightPreferences.update(
        appUserId,
        body.insightPreferences as Record<string, unknown>,
      );
      return await getOwnerProfile(appUserId);
    }
    if (body.insightDelivery != null) {
      if (
        typeof body.insightDelivery !== "object" ||
        Array.isArray(body.insightDelivery)
      ) {
        throw new ApiError(
          400,
          "invalid_cycle_insight_delivery",
          "insightDelivery must be an object.",
        );
      }
      await insightPreferences.recordDelivery(
        appUserId,
        body.insightDelivery as Record<string, unknown>,
      );
      return await getOwnerProfile(appUserId);
    }
    return {
      ...await base.updateOwnerProfile(appUserId, body),
      insightPreferences: await insightPreferences.get(appUserId),
    };
  }

  return {
    ...base,
    getOwnerProfile,
    updateOwnerProfile,
  };
}
