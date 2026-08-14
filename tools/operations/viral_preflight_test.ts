import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  evaluateViralPreflight,
  type ViralPreflightEvidence,
} from "./viral_preflight.ts";

const now = new Date("2026-08-14T18:00:00.000Z");

function greenEvidence(): ViralPreflightEvidence {
  return {
    schemaVersion: 1,
    generatedAtUtc: "2026-08-14T17:55:00.000Z",
    releaseCommit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    deployedReleaseCommit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    campaign: {
      expectedSustainedRps: 300,
      expectedPeakRps: 1000,
      expectedPeakSeconds: 45,
      safetyFactor: 1.5,
    },
    capacity: {
      measuredAtUtc: "2026-08-14T17:30:00.000Z",
      sustainedRps: 500,
      sustainedMinutes: 10,
      spikeRps: 2000,
      spikeSeconds: 60,
      soakRps: 300,
      soakMinutes: 60,
      p95Ms: 800,
      p99Ms: 1600,
      uncontrolled5xxRate: 0.001,
      duplicateCriticalWrites: 0,
      lostCriticalWrites: 0,
      recoveredAfterOverload: true,
    },
    database: {
      maxConnections: 60,
      peakConnections: 30,
      poolerEnforced: true,
      queryTimeouts: 0,
    },
    admissionControl: {
      distributed: true,
      healthy: true,
      outageFallbackTested: true,
    },
    auth: {
      quotasReviewed: true,
      expectedBurstWithinQuota: true,
    },
    worker: {
      oldestReadyAgeSeconds: 5,
      unexplainedDeadLetters: 0,
    },
    observability: {
      correlationIds: true,
      latencyAndStatusMetrics: true,
      databasePressureMetrics: true,
      workerLagMetrics: true,
      alertsEnabled: true,
    },
    readiness: {
      lightweight: true,
      deepVerificationPassed: true,
    },
    gateway: {
      enabled: true,
      stagedLogToBlockCompleted: true,
      emergencyRuleTested: true,
    },
    rollback: { tested: true },
    budget: { usageAlertsEnabled: true },
  };
}

Deno.test("green requires measured headroom and every operational control", () => {
  const result = evaluateViralPreflight(greenEvidence(), now);
  assertEquals(result.status, "green");
  assertEquals(result.findings, []);
  assertEquals(result.measuredCapacityHeadroom.peakRatio, 2);
});

Deno.test("red blocks stale evidence, write-integrity failures and missing gateway", () => {
  const evidence = greenEvidence();
  evidence.capacity.measuredAtUtc = "2026-08-01T00:00:00.000Z";
  evidence.capacity.duplicateCriticalWrites = 1;
  evidence.gateway.enabled = false;
  const result = evaluateViralPreflight(evidence, now);

  assertEquals(result.status, "red");
  for (const code of [
    "capacity_report_stale",
    "critical_write_integrity_failed",
    "gateway_gate_incomplete",
  ]) {
    assertExists(result.findings.find((finding) => finding.code === code));
  }
});

Deno.test("yellow preserves a go-with-caution state only when no red gate fails", () => {
  const evidence = greenEvidence();
  evidence.capacity.p95Ms = 1300;
  evidence.database.peakConnections = 42;
  evidence.worker.oldestReadyAgeSeconds = 180;
  const result = evaluateViralPreflight(evidence, now);

  assertEquals(result.status, "yellow");
  assertExists(result.findings.find((finding) => finding.code === "p95_headroom_low"));
  assertExists(result.findings.find((finding) => finding.code === "database_headroom_low"));
  assertExists(result.findings.find((finding) => finding.code === "worker_lag_elevated"));
});

Deno.test("capacity is evaluated against campaign demand plus safety factor", () => {
  const evidence = greenEvidence();
  evidence.campaign.expectedPeakRps = 1500;
  evidence.campaign.safetyFactor = 1.5;
  const result = evaluateViralPreflight(evidence, now);

  assertEquals(result.status, "red");
  assertExists(result.findings.find((finding) => finding.code === "peak_capacity_insufficient"));
});
