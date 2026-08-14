export type GateLevel = "green" | "yellow" | "red";

export type ViralPreflightEvidence = {
  schemaVersion: 1;
  generatedAtUtc: string;
  releaseCommit: string;
  deployedReleaseCommit: string;
  campaign: {
    expectedSustainedRps: number;
    expectedPeakRps: number;
    expectedPeakSeconds: number;
    safetyFactor: number;
  };
  capacity: {
    measuredAtUtc: string;
    sustainedRps: number;
    sustainedMinutes: number;
    spikeRps: number;
    spikeSeconds: number;
    soakRps: number;
    soakMinutes: number;
    p95Ms: number;
    p99Ms: number;
    uncontrolled5xxRate: number;
    duplicateCriticalWrites: number;
    lostCriticalWrites: number;
    recoveredAfterOverload: boolean;
  };
  database: {
    maxConnections: number;
    peakConnections: number;
    poolerEnforced: boolean;
    queryTimeouts: number;
  };
  admissionControl: {
    distributed: boolean;
    healthy: boolean;
    outageFallbackTested: boolean;
  };
  auth: {
    quotasReviewed: boolean;
    expectedBurstWithinQuota: boolean;
  };
  worker: {
    oldestReadyAgeSeconds: number;
    unexplainedDeadLetters: number;
  };
  observability: {
    correlationIds: boolean;
    latencyAndStatusMetrics: boolean;
    databasePressureMetrics: boolean;
    workerLagMetrics: boolean;
    alertsEnabled: boolean;
  };
  readiness: {
    lightweight: boolean;
    deepVerificationPassed: boolean;
  };
  gateway: {
    enabled: boolean;
    stagedLogToBlockCompleted: boolean;
    emergencyRuleTested: boolean;
  };
  rollback: {
    tested: boolean;
  };
  budget: {
    usageAlertsEnabled: boolean;
  };
};

export type GateFinding = {
  level: Exclude<GateLevel, "green">;
  code: string;
  message: string;
};

export type ViralPreflightResult = {
  status: GateLevel;
  evaluatedAtUtc: string;
  releaseCommit: string;
  measuredCapacityHeadroom: {
    sustainedRatio: number;
    peakRatio: number;
    databaseConnectionRatio: number;
  };
  findings: GateFinding[];
};

const maximumEvidenceAgeMs = 7 * 24 * 60 * 60 * 1000;
const p95TargetMs = 1500;
const p99TargetMs = 3000;
const uncontrolled5xxTarget = 0.005;

export function evaluateViralPreflight(
  evidence: ViralPreflightEvidence,
  now = new Date(),
): ViralPreflightResult {
  validateEvidence(evidence);
  const findings: GateFinding[] = [];
  const add = (
    level: GateFinding["level"],
    code: string,
    message: string,
  ) => findings.push({ level, code, message });

  const measuredAt = parseUtc(evidence.capacity.measuredAtUtc, "capacity.measuredAtUtc");
  const ageMs = now.getTime() - measuredAt.getTime();
  if (ageMs < -5 * 60 * 1000 || ageMs > maximumEvidenceAgeMs) {
    add(
      "red",
      "capacity_report_stale",
      "Capacity evidence must be measured within the last 7 days.",
    );
  }

  if (evidence.releaseCommit !== evidence.deployedReleaseCommit) {
    add(
      "red",
      "release_mismatch",
      "Capacity/preflight evidence must match the exact deployed release commit.",
    );
  }

  const requiredSustained = evidence.campaign.expectedSustainedRps *
    evidence.campaign.safetyFactor;
  const requiredPeak = evidence.campaign.expectedPeakRps *
    evidence.campaign.safetyFactor;
  if (evidence.capacity.sustainedRps < requiredSustained) {
    add(
      "red",
      "sustained_capacity_insufficient",
      `Measured sustained capacity ${evidence.capacity.sustainedRps} RPS is below required ${round(requiredSustained)} RPS including safety factor.`,
    );
  }
  if (evidence.capacity.spikeRps < requiredPeak) {
    add(
      "red",
      "peak_capacity_insufficient",
      `Measured spike capacity ${evidence.capacity.spikeRps} RPS is below required ${round(requiredPeak)} RPS including safety factor.`,
    );
  }
  if (evidence.capacity.spikeSeconds < evidence.campaign.expectedPeakSeconds) {
    add(
      "red",
      "peak_duration_insufficient",
      "Measured spike duration is shorter than the campaign peak-duration assumption.",
    );
  }
  if (evidence.capacity.sustainedMinutes < 10 || evidence.capacity.soakMinutes < 30) {
    add(
      "yellow",
      "capacity_duration_weak",
      "Capacity evidence is short; use at least 10 minutes sustained and 30 minutes soak before a major campaign.",
    );
  }

  if (evidence.capacity.p95Ms > p95TargetMs) {
    add("red", "p95_slo_failed", `p95 ${evidence.capacity.p95Ms} ms exceeds ${p95TargetMs} ms.`);
  } else if (evidence.capacity.p95Ms > 1200) {
    add("yellow", "p95_headroom_low", "p95 latency is within SLO but leaves little campaign headroom.");
  }
  if (evidence.capacity.p99Ms > p99TargetMs) {
    add("red", "p99_slo_failed", `p99 ${evidence.capacity.p99Ms} ms exceeds ${p99TargetMs} ms.`);
  } else if (evidence.capacity.p99Ms > 2400) {
    add("yellow", "p99_headroom_low", "p99 latency is within SLO but leaves little campaign headroom.");
  }
  if (evidence.capacity.uncontrolled5xxRate >= uncontrolled5xxTarget) {
    add(
      "red",
      "uncontrolled_5xx_high",
      `Uncontrolled 5xx rate ${(evidence.capacity.uncontrolled5xxRate * 100).toFixed(2)}% exceeds the 0.5% launch gate.`,
    );
  }
  if (
    evidence.capacity.duplicateCriticalWrites > 0 ||
    evidence.capacity.lostCriticalWrites > 0
  ) {
    add(
      "red",
      "critical_write_integrity_failed",
      "Any duplicate or lost critical write blocks campaign launch.",
    );
  }
  if (!evidence.capacity.recoveredAfterOverload) {
    add(
      "red",
      "overload_recovery_unproven",
      "The measured system did not prove automatic recovery after overload.",
    );
  }

  const connectionRatio = evidence.database.peakConnections /
    evidence.database.maxConnections;
  if (!evidence.database.poolerEnforced) {
    add("red", "pooler_not_enforced", "Serverless database traffic must use the approved transaction pooler.");
  }
  if (connectionRatio >= 0.85) {
    add("red", "database_headroom_critical", "Peak database connections consumed at least 85% of max connections.");
  } else if (connectionRatio >= 0.70) {
    add("yellow", "database_headroom_low", "Peak database connections consumed at least 70% of max connections.");
  }
  if (evidence.database.queryTimeouts > 0) {
    add("red", "database_timeouts", "Database query timeouts occurred during the measured capacity run.");
  }

  if (!evidence.admissionControl.distributed) {
    add("red", "distributed_admission_missing", "Shared/distributed request admission is not enabled.");
  }
  if (!evidence.admissionControl.healthy) {
    add("red", "distributed_admission_unhealthy", "Distributed request admission is not healthy.");
  }
  if (!evidence.admissionControl.outageFallbackTested) {
    add("red", "admission_fallback_unproven", "Rate-limiter outage fallback has not been tested.");
  }

  if (!evidence.auth.quotasReviewed || !evidence.auth.expectedBurstWithinQuota) {
    add("red", "auth_quota_unverified", "Signup/login burst assumptions are not verified against current Auth quotas.");
  }

  if (evidence.worker.oldestReadyAgeSeconds >= 900) {
    add("red", "worker_lag_critical", "Outbox oldest-ready age is at or above 15 minutes.");
  } else if (evidence.worker.oldestReadyAgeSeconds >= 120) {
    add("yellow", "worker_lag_elevated", "Outbox oldest-ready age is at or above 2 minutes.");
  }
  if (evidence.worker.unexplainedDeadLetters > 0) {
    add("red", "dead_letters_unexplained", "Unexplained dead-letter messages must be resolved before launch.");
  }

  if (
    !evidence.observability.correlationIds ||
    !evidence.observability.latencyAndStatusMetrics ||
    !evidence.observability.databasePressureMetrics ||
    !evidence.observability.workerLagMetrics ||
    !evidence.observability.alertsEnabled
  ) {
    add("red", "observability_incomplete", "Campaign telemetry/alerts are incomplete.");
  }
  if (!evidence.readiness.lightweight || !evidence.readiness.deepVerificationPassed) {
    add("red", "readiness_gate_incomplete", "Lightweight readiness and deep deployment verification must both be green.");
  }
  if (
    !evidence.gateway.enabled ||
    !evidence.gateway.stagedLogToBlockCompleted ||
    !evidence.gateway.emergencyRuleTested
  ) {
    add("red", "gateway_gate_incomplete", "Managed edge gateway controls and emergency rule must be staged and tested.");
  }
  if (!evidence.rollback.tested) {
    add("red", "rollback_unproven", "Rollback must be tested for the exact release path.");
  }
  if (!evidence.budget.usageAlertsEnabled) {
    add("red", "budget_alerts_missing", "Provider budget/usage alerts must be enabled before a viral campaign.");
  }

  const status: GateLevel = findings.some((finding) => finding.level === "red")
    ? "red"
    : findings.some((finding) => finding.level === "yellow")
    ? "yellow"
    : "green";

  return {
    status,
    evaluatedAtUtc: now.toISOString(),
    releaseCommit: evidence.releaseCommit,
    measuredCapacityHeadroom: {
      sustainedRatio: round(evidence.capacity.sustainedRps / evidence.campaign.expectedSustainedRps),
      peakRatio: round(evidence.capacity.spikeRps / evidence.campaign.expectedPeakRps),
      databaseConnectionRatio: round(connectionRatio),
    },
    findings,
  };
}

function validateEvidence(evidence: ViralPreflightEvidence): void {
  if (evidence.schemaVersion !== 1) throw new Error("unsupported_schema_version");
  parseUtc(evidence.generatedAtUtc, "generatedAtUtc");
  if (!/^[0-9a-f]{40}$/i.test(evidence.releaseCommit)) throw new Error("invalid_release_commit");
  if (!/^[0-9a-f]{40}$/i.test(evidence.deployedReleaseCommit)) {
    throw new Error("invalid_deployed_release_commit");
  }
  positive(evidence.campaign.expectedSustainedRps, "expectedSustainedRps");
  positive(evidence.campaign.expectedPeakRps, "expectedPeakRps");
  positive(evidence.campaign.expectedPeakSeconds, "expectedPeakSeconds");
  if (
    !Number.isFinite(evidence.campaign.safetyFactor) ||
    evidence.campaign.safetyFactor < 1.1 ||
    evidence.campaign.safetyFactor > 3
  ) {
    throw new Error("invalid_safety_factor");
  }
  positive(evidence.database.maxConnections, "maxConnections");
  if (evidence.database.peakConnections < 0) throw new Error("invalid_peak_connections");
  if (evidence.capacity.uncontrolled5xxRate < 0 || evidence.capacity.uncontrolled5xxRate > 1) {
    throw new Error("invalid_5xx_rate");
  }
}

function positive(value: number, field: string): void {
  if (!Number.isFinite(value) || value <= 0) throw new Error(`invalid_${field}`);
}

function parseUtc(value: string, field: string): Date {
  const parsed = new Date(value);
  if (!value.endsWith("Z") || Number.isNaN(parsed.getTime())) throw new Error(`invalid_${field}`);
  return parsed;
}

function round(value: number): number {
  return Math.round(value * 1000) / 1000;
}

if (import.meta.main) {
  const inputPath = Deno.args[0];
  const outputPath = Deno.args[1] ?? "viral-preflight-result.json";
  if (!inputPath) {
    console.error("Usage: deno run --allow-read --allow-write viral_preflight.ts <evidence.json> [result.json]");
    Deno.exit(2);
  }
  const evidence = JSON.parse(await Deno.readTextFile(inputPath)) as ViralPreflightEvidence;
  const result = evaluateViralPreflight(evidence);
  await Deno.writeTextFile(outputPath, `${JSON.stringify(result, null, 2)}\n`);
  console.log(JSON.stringify(result, null, 2));
  if (result.status !== "green") Deno.exit(1);
}
