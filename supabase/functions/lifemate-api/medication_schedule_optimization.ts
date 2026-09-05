export const nearbyDoseThresholdMinutes = 30;
export const nearbyDoseRoundMinutes = 5;
export const medicationScheduleOptimizationAlgorithmVersion = "nearby-v1";

export type NearbyDosePlanCandidate = {
  treatmentPlanId: string;
  medicationName: string;
  anchorLocalTime: string;
  intervalHours: number;
  treatmentPlanVersion: number;
  timingVersion: number;
  nearbyGroupingEnabled: boolean;
  timingLocked: boolean;
  manualSpacingBeforeMinutes: number;
  manualSpacingAfterMinutes: number;
};

export type NearbyDoseExclusionReason =
  | "not_opted_in"
  | "timing_locked"
  | "manual_spacing"
  | "no_nearby_candidate"
  | "ambiguous_cluster";

export type NearbyDosePlanChange = {
  treatmentPlanId: string;
  medicationName: string;
  oldAnchorLocalTime: string;
  newAnchorLocalTime: string;
  intervalHoursBefore: number;
  intervalHoursAfter: number;
  treatmentPlanVersion: number;
  timingVersion: number;
  shiftMinutes: number;
};

export type NearbyDoseGroup = {
  sharedLocalTime: string;
  changes: NearbyDosePlanChange[];
};

export type NearbyDoseProposal = {
  algorithmVersion: string;
  groups: NearbyDoseGroup[];
  exclusions: Array<{
    treatmentPlanId: string;
    medicationName: string;
    reason: NearbyDoseExclusionReason;
  }>;
  expectedNotificationReduction: number;
};

function parseLocalMinutes(value: string): number {
  const match = /^(?:([01]\d|2[0-3])):([0-5]\d)(?::[0-5]\d)?$/.exec(value);
  if (!match) throw new Error("invalid_anchor_local_time");
  return Number(match[1]) * 60 + Number(match[2]);
}

function formatLocalMinutes(value: number): string {
  const normalized = ((value % 1440) + 1440) % 1440;
  const hour = Math.floor(normalized / 60);
  const minute = normalized % 60;
  return `${hour.toString().padStart(2, "0")}:${
    minute.toString().padStart(2, "0")
  }`;
}

function circularDistanceMinutes(left: number, right: number): number {
  const direct = Math.abs(left - right);
  return Math.min(direct, 1440 - direct);
}

function unwrapAround(reference: number, value: number): number {
  const options = [value - 1440, value, value + 1440];
  return options.reduce((best, current) =>
    Math.abs(current - reference) < Math.abs(best - reference) ? current : best
  );
}

function roundedMeanMinutes(values: number[]): number {
  const reference = values[0];
  const unwrapped = values.map((value) => unwrapAround(reference, value));
  const mean = unwrapped.reduce((sum, value) => sum + value, 0) /
    unwrapped.length;
  return Math.round(mean / nearbyDoseRoundMinutes) * nearbyDoseRoundMinutes;
}

function eligible(
  candidate: NearbyDosePlanCandidate,
): NearbyDoseExclusionReason | null {
  if (!candidate.nearbyGroupingEnabled) return "not_opted_in";
  if (candidate.timingLocked) return "timing_locked";
  if (
    candidate.manualSpacingBeforeMinutes > 0 ||
    candidate.manualSpacingAfterMinutes > 0
  ) {
    return "manual_spacing";
  }
  return null;
}

/**
 * Deterministic convenience-only grouping. This function does not infer drug
 * safety or change recurrence intervals. It only proposes a shared local anchor
 * for user-entered plans that explicitly opted in.
 */
export function buildNearbyDoseProposal(
  candidates: NearbyDosePlanCandidate[],
): NearbyDoseProposal {
  const sorted = [...candidates].sort((a, b) =>
    a.treatmentPlanId.localeCompare(b.treatmentPlanId)
  );
  const exclusions: NearbyDoseProposal["exclusions"] = [];
  const pool = sorted.filter((candidate) => {
    const reason = eligible(candidate);
    if (reason != null) {
      exclusions.push({
        treatmentPlanId: candidate.treatmentPlanId,
        medicationName: candidate.medicationName,
        reason,
      });
      return false;
    }
    return true;
  });

  const minuteById = new Map(
    pool.map((
      candidate,
    ) => [
      candidate.treatmentPlanId,
      parseLocalMinutes(candidate.anchorLocalTime),
    ]),
  );
  const adjacency = new Map<string, Set<string>>();
  for (const candidate of pool) {
    adjacency.set(candidate.treatmentPlanId, new Set());
  }
  for (let i = 0; i < pool.length; i += 1) {
    for (let j = i + 1; j < pool.length; j += 1) {
      const left = pool[i];
      const right = pool[j];
      const distance = circularDistanceMinutes(
        minuteById.get(left.treatmentPlanId)!,
        minuteById.get(right.treatmentPlanId)!,
      );
      if (distance < nearbyDoseThresholdMinutes) {
        adjacency.get(left.treatmentPlanId)!.add(right.treatmentPlanId);
        adjacency.get(right.treatmentPlanId)!.add(left.treatmentPlanId);
      }
    }
  }

  const byId = new Map(
    pool.map((candidate) => [candidate.treatmentPlanId, candidate]),
  );
  const visited = new Set<string>();
  const groups: NearbyDoseGroup[] = [];

  for (const candidate of pool) {
    const id = candidate.treatmentPlanId;
    if (visited.has(id)) continue;
    const stack = [id];
    const component: string[] = [];
    visited.add(id);
    while (stack.length > 0) {
      const current = stack.pop()!;
      component.push(current);
      for (const neighbor of adjacency.get(current) ?? []) {
        if (!visited.has(neighbor)) {
          visited.add(neighbor);
          stack.push(neighbor);
        }
      }
    }

    if (component.length < 2) {
      const item = byId.get(component[0])!;
      exclusions.push({
        treatmentPlanId: item.treatmentPlanId,
        medicationName: item.medicationName,
        reason: "no_nearby_candidate",
      });
      continue;
    }

    // A chain such as 08:00, 08:25, 08:50 is ambiguous because the endpoints
    // are not mutually within threshold. Fail closed instead of generating a
    // contradictory shared time.
    let clique = true;
    for (let i = 0; i < component.length && clique; i += 1) {
      for (let j = i + 1; j < component.length; j += 1) {
        if (
          circularDistanceMinutes(
            minuteById.get(component[i])!,
            minuteById.get(component[j])!,
          ) >= nearbyDoseThresholdMinutes
        ) {
          clique = false;
          break;
        }
      }
    }
    if (!clique) {
      for (const componentId of component.sort()) {
        const item = byId.get(componentId)!;
        exclusions.push({
          treatmentPlanId: item.treatmentPlanId,
          medicationName: item.medicationName,
          reason: "ambiguous_cluster",
        });
      }
      continue;
    }

    const sharedMinutes = roundedMeanMinutes(
      component.map((componentId) => minuteById.get(componentId)!),
    );
    const sharedLocalTime = formatLocalMinutes(sharedMinutes);
    const changes = component
      .map((componentId) => {
        const item = byId.get(componentId)!;
        return {
          treatmentPlanId: item.treatmentPlanId,
          medicationName: item.medicationName,
          oldAnchorLocalTime: item.anchorLocalTime.slice(0, 5),
          newAnchorLocalTime: sharedLocalTime,
          intervalHoursBefore: item.intervalHours,
          intervalHoursAfter: item.intervalHours,
          treatmentPlanVersion: item.treatmentPlanVersion,
          timingVersion: item.timingVersion,
          shiftMinutes: circularDistanceMinutes(
            minuteById.get(componentId)!,
            sharedMinutes,
          ),
        } satisfies NearbyDosePlanChange;
      })
      .sort((a, b) => a.treatmentPlanId.localeCompare(b.treatmentPlanId));
    groups.push({ sharedLocalTime, changes });
  }

  groups.sort((a, b) => a.sharedLocalTime.localeCompare(b.sharedLocalTime));
  exclusions.sort((a, b) => a.treatmentPlanId.localeCompare(b.treatmentPlanId));
  return {
    algorithmVersion: medicationScheduleOptimizationAlgorithmVersion,
    groups,
    exclusions,
    expectedNotificationReduction: groups.reduce(
      (sum, group) => sum + Math.max(0, group.changes.length - 1),
      0,
    ),
  };
}
