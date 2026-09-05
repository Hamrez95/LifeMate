import type { WomenCalendarEstimate } from "./women_calendar_legacy.ts";
import {
  canonicalizeLegacySymptoms,
  type WomenSymptomId,
} from "./women_symptom_catalog.ts";

export const womenCycleInsightRuleVersion = "cycle-insights-v1";

export type WomenCycleInsightType =
  | "expected_period_window"
  | "recurring_symptom_pattern"
  | "logging_reminder"
  | "cycle_history_observation";

export type WomenCycleInsight = {
  id: string;
  type: WomenCycleInsightType;
  ruleVersion: string;
  observed: boolean;
  predicted: boolean;
  priority: number;
  evidenceCount: number;
  subjectId: string | null;
  notificationEligible: boolean;
  analyticsKey: string;
};

export type WomenCycleInsightLog = {
  loggedOn: string;
  symptoms: unknown;
};

export type WomenCycleInsightContext = {
  today: string;
  estimate: WomenCalendarEstimate | null;
  periodStarts: string[];
  dailyLogs: WomenCycleInsightLog[];
  insightsEnabled: boolean;
  notificationsEnabled: boolean;
  notificationCategories: WomenCycleInsightType[];
  recentInsightIds: string[];
  deliveredTodayCount: number;
  lastLoggedOn: string | null;
};

export type WomenCycleInsightResult = {
  inApp: WomenCycleInsight[];
  notifications: WomenCycleInsight[];
  suppressedReason: "disabled" | "insufficient_data" | null;
};

const maxNotificationsPerDay = 2;

export function evaluateWomenCycleInsights(
  context: WomenCycleInsightContext,
): WomenCycleInsightResult {
  if (!context.insightsEnabled) {
    return { inApp: [], notifications: [], suppressedReason: "disabled" };
  }

  const candidates = [
    expectedPeriodInsight(context),
    recurringSymptomInsight(context),
    loggingReminderInsight(context),
    cycleHistoryInsight(context),
  ].filter((value): value is WomenCycleInsight => value != null)
    .filter((value) => !context.recentInsightIds.includes(value.id))
    .sort((left, right) =>
      right.priority - left.priority || left.id.localeCompare(right.id)
    );

  if (candidates.length === 0) {
    return {
      inApp: [],
      notifications: [],
      suppressedReason: "insufficient_data",
    };
  }

  const remainingNotificationSlots = Math.max(
    0,
    maxNotificationsPerDay - context.deliveredTodayCount,
  );
  const notificationCategorySet = new Set(context.notificationCategories);
  const notifications = context.notificationsEnabled
    ? candidates
      .filter((value) => value.notificationEligible)
      .filter((value) => notificationCategorySet.has(value.type))
      .slice(0, remainingNotificationSlots)
    : [];

  return { inApp: candidates, notifications, suppressedReason: null };
}

function expectedPeriodInsight(
  context: WomenCycleInsightContext,
): WomenCycleInsight | null {
  const estimate = context.estimate;
  if (!estimate || estimate.confidence === "low") return null;
  if (estimate.daysUntilNextPeriod < 0 || estimate.daysUntilNextPeriod > 3) {
    return null;
  }
  return {
    id: `period-window:${estimate.nextPeriodStart}`,
    type: "expected_period_window",
    ruleVersion: womenCycleInsightRuleVersion,
    observed: false,
    predicted: true,
    priority: 90,
    evidenceCount: context.periodStarts.length,
    subjectId: null,
    notificationEligible: true,
    analyticsKey: "women_insight.period_window",
  };
}

function recurringSymptomInsight(
  context: WomenCycleInsightContext,
): WomenCycleInsight | null {
  const estimate = context.estimate;
  if (
    !estimate || estimate.confidence === "low" || context.dailyLogs.length < 3
  ) {
    return null;
  }
  const currentCycleDay = estimate.cycleDay;
  const counts = new Map<WomenSymptomId, number>();
  for (const log of context.dailyLogs) {
    const symptoms = canonicalizeLegacySymptoms(log.symptoms);
    const relativeDay = cycleDayForDate(
      log.loggedOn,
      estimate.cycleStart,
      estimate.cycleLength,
    );
    if (Math.abs(relativeDay - currentCycleDay) > 2) continue;
    for (const symptom of symptoms) {
      if (symptom === "no_symptom" || symptom === "other") continue;
      counts.set(symptom, (counts.get(symptom) ?? 0) + 1);
    }
  }
  const ranked = [...counts.entries()].sort((a, b) =>
    b[1] - a[1] || a[0].localeCompare(b[0])
  );
  const [symptom, count] = ranked[0] ?? [];
  if (!symptom || count < 2) return null;
  return {
    id: `recurring-symptom:${symptom}:day-${currentCycleDay}`,
    type: "recurring_symptom_pattern",
    ruleVersion: womenCycleInsightRuleVersion,
    observed: true,
    predicted: false,
    priority: 75,
    evidenceCount: count,
    subjectId: symptom,
    notificationEligible: false,
    analyticsKey: "women_insight.recurring_symptom",
  };
}

function loggingReminderInsight(
  context: WomenCycleInsightContext,
): WomenCycleInsight | null {
  if (context.lastLoggedOn === context.today) return null;
  const estimate = context.estimate;
  if (!estimate) return null;
  const relevant = estimate.estimatedBleeding ||
    estimate.daysUntilNextPeriod <= 2;
  if (!relevant) return null;
  return {
    id: `logging-reminder:${context.today}`,
    type: "logging_reminder",
    ruleVersion: womenCycleInsightRuleVersion,
    observed: false,
    predicted: true,
    priority: 60,
    evidenceCount: context.periodStarts.length,
    subjectId: null,
    notificationEligible: true,
    analyticsKey: "women_insight.logging_reminder",
  };
}

function cycleHistoryInsight(
  context: WomenCycleInsightContext,
): WomenCycleInsight | null {
  const estimate = context.estimate;
  if (!estimate || context.periodStarts.length < 3) return null;
  if (
    estimate.cyclePattern !== "regular" && estimate.cyclePattern !== "variable"
  ) return null;
  return {
    id: `cycle-history:${estimate.cyclePattern}:${estimate.cycleLength}`,
    type: "cycle_history_observation",
    ruleVersion: womenCycleInsightRuleVersion,
    observed: true,
    predicted: false,
    priority: 40,
    evidenceCount: context.periodStarts.length,
    subjectId: estimate.cyclePattern,
    notificationEligible: false,
    analyticsKey: "women_insight.cycle_history",
  };
}

function cycleDayForDate(
  dateValue: string,
  cycleStartValue: string,
  cycleLength: number,
): number {
  const date = parseDate(dateValue);
  const start = parseDate(cycleStartValue);
  const days = Math.floor((date.getTime() - start.getTime()) / 86_400_000);
  const normalized = ((days % cycleLength) + cycleLength) % cycleLength;
  return normalized + 1;
}

function parseDate(value: string): Date {
  return new Date(`${value.slice(0, 10)}T00:00:00.000Z`);
}
