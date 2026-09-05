export const medicationSleepSolverAlgorithmVersion = "sleep-flex-v1";

export type SleepWindow = {
  startLocalTime: string;
  endLocalTime: string;
};

export type ExactAnchorProposal = {
  mode: "strict_anchor_shift";
  enteredIntervalMinutes: number;
  oldAnchorLocalTime: string;
  newAnchorLocalTime: string;
  shiftMinutes: number;
  sleepHitsBefore: number;
  sleepHitsAfter: number;
  horizonDoseCount: number;
};

export type FlexibleOccurrence = {
  index: number;
  originalMinuteOffset: number;
  proposedMinuteOffset: number;
  originalLocalTime: string;
  proposedLocalTime: string;
  previousGapMinutes: number | null;
  proposedGapMinutes: number | null;
  variationMinutes: number;
  sleepHitBefore: boolean;
  sleepHitAfter: boolean;
};

export type FlexibleScheduleProposal = {
  mode: "flexible_interval";
  enteredIntervalMinutes: number;
  maxVariationMinutes: number;
  occurrences: FlexibleOccurrence[];
  sleepHitsBefore: number;
  sleepHitsAfter: number;
  feasible: boolean;
};

function parseClock(value: string): number {
  const match = /^(?:([01]\d|2[0-3])):([0-5]\d)(?::[0-5]\d)?$/.exec(value);
  if (!match) throw new Error("invalid_local_time");
  return Number(match[1]) * 60 + Number(match[2]);
}

function formatClock(totalMinutes: number): string {
  const value = ((Math.round(totalMinutes) % 1440) + 1440) % 1440;
  const hour = Math.floor(value / 60);
  const minute = value % 60;
  return `${hour.toString().padStart(2, "0")}:${
    minute.toString().padStart(2, "0")
  }`;
}

export function isMinuteInsideSleepWindow(
  minuteOfDay: number,
  sleep: SleepWindow,
): boolean {
  const start = parseClock(sleep.startLocalTime);
  const end = parseClock(sleep.endLocalTime);
  const minute = ((minuteOfDay % 1440) + 1440) % 1440;
  if (start === end) return false;
  if (start < end) return minute >= start && minute < end;
  return minute >= start || minute < end;
}

function countSleepHits(
  anchorMinutes: number,
  intervalMinutes: number,
  doseCount: number,
  sleep: SleepWindow,
): number {
  let hits = 0;
  for (let i = 0; i < doseCount; i += 1) {
    if (isMinuteInsideSleepWindow(anchorMinutes + i * intervalMinutes, sleep)) {
      hits += 1;
    }
  }
  return hits;
}

function circularShiftMinutes(left: number, right: number): number {
  const direct = Math.abs(left - right) % 1440;
  return Math.min(direct, 1440 - direct);
}

/**
 * Searches all five-minute wall-clock anchors. The interval remains exact;
 * only the anchor may move. Objective order: fewer sleep hits, then minimal
 * total anchor movement, then earliest deterministic clock value.
 */
export function proposeExactSleepAwareAnchor(input: {
  anchorLocalTime: string;
  intervalHours: number;
  sleep: SleepWindow;
  horizonDoseCount?: number;
}): ExactAnchorProposal {
  const intervalMinutes = input.intervalHours * 60;
  if (!Number.isInteger(intervalMinutes) || intervalMinutes < 60) {
    throw new Error("invalid_interval");
  }
  const oldAnchor = parseClock(input.anchorLocalTime);
  const doseCount = Math.max(1, Math.min(input.horizonDoseCount ?? 16, 128));
  const before = countSleepHits(
    oldAnchor,
    intervalMinutes,
    doseCount,
    input.sleep,
  );

  let bestAnchor = oldAnchor;
  let bestHits = before;
  let bestShift = 0;
  for (let candidate = 0; candidate < 1440; candidate += 5) {
    const hits = countSleepHits(
      candidate,
      intervalMinutes,
      doseCount,
      input.sleep,
    );
    const shift = circularShiftMinutes(oldAnchor, candidate);
    if (
      hits < bestHits ||
      (hits === bestHits && shift < bestShift) ||
      (hits === bestHits && shift === bestShift && candidate < bestAnchor)
    ) {
      bestAnchor = candidate;
      bestHits = hits;
      bestShift = shift;
    }
  }

  return {
    mode: "strict_anchor_shift",
    enteredIntervalMinutes: intervalMinutes,
    oldAnchorLocalTime: formatClock(oldAnchor),
    newAnchorLocalTime: formatClock(bestAnchor),
    shiftMinutes: bestShift,
    sleepHitsBefore: before,
    sleepHitsAfter: bestHits,
    horizonDoseCount: doseCount,
  };
}

function candidateOffsetsAround(
  targetOffset: number,
  maxVariationMinutes: number,
): number[] {
  const values: number[] = [];
  for (
    let delta = -maxVariationMinutes;
    delta <= maxVariationMinutes;
    delta += 5
  ) {
    values.push(targetOffset + delta);
  }
  return values;
}

/**
 * Builds a bounded sequence of occurrence overrides. Each proposed gap is
 * constrained to enteredInterval ± maxVariationMinutes. The solver never
 * changes the canonical recurrence and never creates an indefinite cadence.
 */
export function proposeFlexibleSleepAwareSequence(input: {
  anchorLocalTime: string;
  intervalHours: number;
  maxVariationMinutes: number;
  doseCount: number;
  sleep: SleepWindow;
}): FlexibleScheduleProposal {
  const intervalMinutes = input.intervalHours * 60;
  if (!Number.isInteger(intervalMinutes) || intervalMinutes < 60) {
    throw new Error("invalid_interval");
  }
  if (
    !Number.isInteger(input.maxVariationMinutes) ||
    input.maxVariationMinutes < 5 ||
    input.maxVariationMinutes > 180
  ) {
    throw new Error("invalid_variation_bound");
  }
  if (
    !Number.isInteger(input.doseCount) || input.doseCount < 2 ||
    input.doseCount > 64
  ) {
    throw new Error("invalid_dose_count");
  }

  const anchor = parseClock(input.anchorLocalTime);
  const proposedOffsets: number[] = [0];
  const occurrences: FlexibleOccurrence[] = [];

  for (let index = 1; index < input.doseCount; index += 1) {
    const previous = proposedOffsets[index - 1];
    const exactNext = previous + intervalMinutes;
    const candidates = candidateOffsetsAround(
      exactNext,
      input.maxVariationMinutes,
    ).filter((candidate) => candidate > previous);

    candidates.sort((left, right) => {
      const leftSleep = isMinuteInsideSleepWindow(anchor + left, input.sleep)
        ? 1
        : 0;
      const rightSleep = isMinuteInsideSleepWindow(anchor + right, input.sleep)
        ? 1
        : 0;
      if (leftSleep !== rightSleep) return leftSleep - rightSleep;
      const leftVariation = Math.abs((left - previous) - intervalMinutes);
      const rightVariation = Math.abs((right - previous) - intervalMinutes);
      if (leftVariation !== rightVariation) {
        return leftVariation - rightVariation;
      }
      return left - right;
    });

    if (candidates.length === 0) {
      return {
        mode: "flexible_interval",
        enteredIntervalMinutes: intervalMinutes,
        maxVariationMinutes: input.maxVariationMinutes,
        occurrences: [],
        sleepHitsBefore: 0,
        sleepHitsAfter: 0,
        feasible: false,
      };
    }
    proposedOffsets.push(candidates[0]);
  }

  let beforeHits = 0;
  let afterHits = 0;
  for (let index = 0; index < input.doseCount; index += 1) {
    const originalOffset = index * intervalMinutes;
    const proposedOffset = proposedOffsets[index];
    const before = isMinuteInsideSleepWindow(
      anchor + originalOffset,
      input.sleep,
    );
    const after = isMinuteInsideSleepWindow(
      anchor + proposedOffset,
      input.sleep,
    );
    if (before) beforeHits += 1;
    if (after) afterHits += 1;
    const proposedGap = index === 0
      ? null
      : proposedOffset - proposedOffsets[index - 1];
    occurrences.push({
      index,
      originalMinuteOffset: originalOffset,
      proposedMinuteOffset: proposedOffset,
      originalLocalTime: formatClock(anchor + originalOffset),
      proposedLocalTime: formatClock(anchor + proposedOffset),
      previousGapMinutes: index === 0 ? null : intervalMinutes,
      proposedGapMinutes: proposedGap,
      variationMinutes: proposedGap == null ? 0 : proposedGap - intervalMinutes,
      sleepHitBefore: before,
      sleepHitAfter: after,
    });
  }

  return {
    mode: "flexible_interval",
    enteredIntervalMinutes: intervalMinutes,
    maxVariationMinutes: input.maxVariationMinutes,
    occurrences,
    sleepHitsBefore: beforeHits,
    sleepHitsAfter: afterHits,
    feasible: afterHits <= beforeHits,
  };
}
