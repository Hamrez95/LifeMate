import { mergeLegacySymptomsIntoObservations } from "./women_symptom_catalog.ts";

export const womenCycleAnalyticsVersion = "cycle-analytics-v1";

export type AnalyticsEpisode = {
  startedOn: string;
  endedOn: string | null;
};

export type AnalyticsDailyLog = {
  loggedOn: string;
  painLevel: number | null;
  symptoms: unknown;
  symptomObservations?: unknown;
  periodFlow?: string | null;
  bloodAppearance?: string | null;
  bloodTexture?: string | null;
};

export type NumericSummary = {
  average: number | null;
  min: number | null;
  max: number | null;
  sampleSize: number;
};

export type WomenCycleAnalytics = {
  version: string;
  evidenceState: "none" | "learning" | "ready";
  cycleLength: NumericSummary;
  periodDuration: NumericSummary;
  cycleVariationDays: number | null;
  regularity: "insufficient_data" | "stable" | "variable";
  recurringSymptoms: Array<{ id: string; occurrences: number }>;
  pain: NumericSummary;
  flowDistribution: Record<string, number>;
  bloodAppearanceDistribution: Record<string, number>;
  bloodTextureDistribution: Record<string, number>;
  recordedFactsOnly: true;
};

export function calculateWomenCycleAnalytics(
  episodesValue: AnalyticsEpisode[],
  dailyLogs: AnalyticsDailyLog[],
): WomenCycleAnalytics {
  const episodes = normalizeEpisodes(episodesValue);
  const cycleIntervals = cycleIntervalsFromEpisodes(episodes);
  const periodDurations = episodes
    .map((episode) => periodDuration(episode))
    .filter((value): value is number =>
      value != null && value >= 1 && value <= 14
    );
  const usableCycleIntervals = filterCycleIntervalOutliers(cycleIntervals);
  const cycleLength = summarize(usableCycleIntervals);
  const periodDurationSummary = summarize(periodDurations);
  const cycleVariationDays = usableCycleIntervals.length >= 2
    ? Math.max(...usableCycleIntervals) - Math.min(...usableCycleIntervals)
    : null;
  const regularity = usableCycleIntervals.length < 2
    ? "insufficient_data" as const
    : cycleVariationDays != null && cycleVariationDays <= 7
    ? "stable" as const
    : "variable" as const;

  const recurringSymptoms = recurringSymptomSummary(dailyLogs);
  const painValues = dailyLogs
    .map((log) => Number(log.painLevel))
    .filter((value) => Number.isFinite(value) && value >= 0 && value <= 5);

  const evidenceState = episodes.length === 0 && dailyLogs.length === 0
    ? "none" as const
    : usableCycleIntervals.length < 2
    ? "learning" as const
    : "ready" as const;

  return {
    version: womenCycleAnalyticsVersion,
    evidenceState,
    cycleLength,
    periodDuration: periodDurationSummary,
    cycleVariationDays,
    regularity,
    recurringSymptoms,
    pain: summarize(painValues),
    flowDistribution: distribution(dailyLogs.map((log) => log.periodFlow)),
    bloodAppearanceDistribution: distribution(
      dailyLogs.map((log) => log.bloodAppearance),
    ),
    bloodTextureDistribution: distribution(
      dailyLogs.map((log) => log.bloodTexture),
    ),
    recordedFactsOnly: true,
  };
}

function normalizeEpisodes(value: AnalyticsEpisode[]): AnalyticsEpisode[] {
  return value
    .filter((episode) => isDate(episode.startedOn))
    .map((episode) => ({
      startedOn: episode.startedOn.slice(0, 10),
      endedOn: episode.endedOn && isDate(episode.endedOn)
        ? episode.endedOn.slice(0, 10)
        : null,
    }))
    .sort((a, b) => a.startedOn.localeCompare(b.startedOn));
}

function cycleIntervalsFromEpisodes(episodes: AnalyticsEpisode[]): number[] {
  const result: number[] = [];
  for (let index = 1; index < episodes.length; index++) {
    const days = daysBetween(
      episodes[index - 1].startedOn,
      episodes[index].startedOn,
    );
    if (days >= 15 && days <= 90) result.push(days);
  }
  return result;
}

function filterCycleIntervalOutliers(values: number[]): number[] {
  if (values.length < 3) {
    return values.filter((value) => value >= 21 && value <= 45);
  }
  const sorted = [...values].sort((a, b) => a - b);
  const median = medianOf(sorted);
  const absoluteDeviations = sorted.map((value) => Math.abs(value - median));
  const mad = medianOf([...absoluteDeviations].sort((a, b) => a - b));
  const tolerance = Math.max(7, mad * 3);
  return values.filter(
    (value) =>
      value >= 21 && value <= 45 && Math.abs(value - median) <= tolerance,
  );
}

function periodDuration(episode: AnalyticsEpisode): number | null {
  if (!episode.endedOn) return null;
  const diff = daysBetween(episode.startedOn, episode.endedOn);
  return diff >= 0 ? diff + 1 : null;
}

function recurringSymptomSummary(
  logs: AnalyticsDailyLog[],
): Array<{ id: string; occurrences: number }> {
  const counts = new Map<string, number>();
  for (const log of logs) {
    const observations = mergeLegacySymptomsIntoObservations(
      log.symptoms,
      log.symptomObservations,
    );
    const dayIds = new Set(
      observations.map((row) => row.id).filter((id) => id !== "no_symptom"),
    );
    for (const id of dayIds) counts.set(id, (counts.get(id) ?? 0) + 1);
  }
  return [...counts.entries()]
    .filter(([, count]) => count >= 2)
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, 8)
    .map(([id, occurrences]) => ({ id, occurrences }));
}

function distribution(
  values: Array<string | null | undefined>,
): Record<string, number> {
  const result: Record<string, number> = {};
  for (const raw of values) {
    const value = String(raw ?? "").trim().toLowerCase();
    if (!value) continue;
    result[value] = (result[value] ?? 0) + 1;
  }
  return result;
}

function summarize(values: number[]): NumericSummary {
  if (values.length === 0) {
    return { average: null, min: null, max: null, sampleSize: 0 };
  }
  const sum = values.reduce((total, value) => total + value, 0);
  return {
    average: Math.round((sum / values.length) * 10) / 10,
    min: Math.min(...values),
    max: Math.max(...values),
    sampleSize: values.length,
  };
}

function medianOf(values: number[]): number {
  if (values.length === 0) return 0;
  const middle = Math.floor(values.length / 2);
  return values.length % 2 === 1
    ? values[middle]
    : (values[middle - 1] + values[middle]) / 2;
}

function daysBetween(left: string, right: string): number {
  return Math.round(
    (parseDate(right).getTime() - parseDate(left).getTime()) / 86_400_000,
  );
}

function parseDate(value: string): Date {
  return new Date(`${value.slice(0, 10)}T00:00:00.000Z`);
}

function isDate(value: string): boolean {
  const date = parseDate(value);
  return Number.isFinite(date.getTime());
}
