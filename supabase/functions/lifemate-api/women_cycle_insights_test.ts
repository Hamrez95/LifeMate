import { assertEquals } from "jsr:@std/assert@1";
import { evaluateWomenCycleInsights } from "./women_cycle_insights.ts";

const estimate = {
  cycleStart: "2026-08-05",
  cycleDay: 26,
  cycleLength: 28,
  periodLength: 5,
  estimatedBleeding: false,
  phase: "pre_period" as const,
  detailedPhase: "pms" as const,
  ovulationDay: 14,
  fertileWindowStartDay: 9,
  fertileWindowEndDay: 15,
  pmsStartDay: 24,
  nextPeriodStart: "2026-09-02",
  daysUntilNextPeriod: 2,
  algorithmVersion: "calendar-estimate-v1" as const,
  confidence: "high" as const,
  cyclePattern: "regular" as const,
  fertilityEstimateReliable: true,
};

Deno.test("insights fail safely when globally disabled", () => {
  assertEquals(
    evaluateWomenCycleInsights({
      today: "2026-08-31",
      estimate,
      periodStarts: ["2026-06-10", "2026-07-08", "2026-08-05"],
      dailyLogs: [],
      insightsEnabled: false,
      notificationsEnabled: true,
      notificationCategories: ["expected_period_window"],
      recentInsightIds: [],
      deliveredTodayCount: 0,
      lastLoggedOn: null,
    }),
    { inApp: [], notifications: [], suppressedReason: "disabled" },
  );
});

Deno.test("in-app insights remain available when notifications are disabled", () => {
  const result = evaluateWomenCycleInsights({
    today: "2026-08-31",
    estimate,
    periodStarts: ["2026-06-10", "2026-07-08", "2026-08-05"],
    dailyLogs: [],
    insightsEnabled: true,
    notificationsEnabled: false,
    notificationCategories: ["expected_period_window", "logging_reminder"],
    recentInsightIds: [],
    deliveredTodayCount: 0,
    lastLoggedOn: null,
  });
  assertEquals(
    result.inApp.some((row) => row.type === "expected_period_window"),
    true,
  );
  assertEquals(result.notifications, []);
});

Deno.test("recurring symptom requires repeated evidence near comparable cycle day", () => {
  const result = evaluateWomenCycleInsights({
    today: "2026-08-31",
    estimate,
    periodStarts: ["2026-06-10", "2026-07-08", "2026-08-05"],
    dailyLogs: [
      { loggedOn: "2026-08-30", symptoms: ["Headache"] },
      { loggedOn: "2026-08-02", symptoms: ["Headache"] },
      { loggedOn: "2026-07-05", symptoms: ["Headache"] },
    ],
    insightsEnabled: true,
    notificationsEnabled: false,
    notificationCategories: [],
    recentInsightIds: [],
    deliveredTodayCount: 0,
    lastLoggedOn: "2026-08-30",
  });
  const recurring = result.inApp.find((row) =>
    row.type === "recurring_symptom_pattern"
  );
  assertEquals(recurring?.subjectId, "headache");
  assertEquals(recurring?.observed, true);
  assertEquals(recurring?.predicted, false);
});

Deno.test("recent insight ids deduplicate and daily frequency cap suppresses notifications", () => {
  const periodId = `period-window:${estimate.nextPeriodStart}`;
  const result = evaluateWomenCycleInsights({
    today: "2026-08-31",
    estimate,
    periodStarts: ["2026-06-10", "2026-07-08", "2026-08-05"],
    dailyLogs: [],
    insightsEnabled: true,
    notificationsEnabled: true,
    notificationCategories: ["expected_period_window", "logging_reminder"],
    recentInsightIds: [periodId],
    deliveredTodayCount: 2,
    lastLoggedOn: null,
  });
  assertEquals(result.inApp.some((row) => row.id === periodId), false);
  assertEquals(result.notifications, []);
});

Deno.test("low-confidence estimate never emits predictive period-window insight", () => {
  const result = evaluateWomenCycleInsights({
    today: "2026-08-31",
    estimate: { ...estimate, confidence: "low" as const },
    periodStarts: ["2026-08-05"],
    dailyLogs: [],
    insightsEnabled: true,
    notificationsEnabled: true,
    notificationCategories: ["expected_period_window"],
    recentInsightIds: [],
    deliveredTodayCount: 0,
    lastLoggedOn: null,
  });
  assertEquals(
    result.inApp.some((row) => row.type === "expected_period_window"),
    false,
  );
});
