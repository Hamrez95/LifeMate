export type OperationalSignalState = "ready" | "unknown" | "unavailable";

export type OperationsSnapshot = {
  services: Array<{
    key: string;
    state: OperationalSignalState;
    source: string;
    latencyMs: number | null;
    checkedAtUtc: string;
  }>;
  backgroundJobs: {
    state: OperationalSignalState;
    source: string;
  };
  deployments: {
    state: OperationalSignalState;
    source: string;
    releaseReference: string | null;
  };
  providers: {
    state: OperationalSignalState;
    source: string;
  };
  incidents: {
    state: OperationalSignalState;
    source: string;
    activeCount: number | null;
  };
  freshness: {
    status: "fresh";
    asOfUtc: string;
  };
};

type BuildOperationsSnapshotInput = {
  checkDatabase: () => Promise<void>;
  now?: () => Date;
  monotonicNow?: () => number;
};

export async function buildOperationsSnapshot(
  input: BuildOperationsSnapshotInput,
): Promise<OperationsSnapshot> {
  const now = input.now ?? (() => new Date());
  const monotonicNow = input.monotonicNow ?? (() => performance.now());
  const startedAt = monotonicNow();
  await input.checkDatabase();
  const latencyMs = Math.max(
    0,
    Math.round((monotonicNow() - startedAt) * 10) / 10,
  );
  const checkedAtUtc = now().toISOString();

  return {
    services: [
      {
        key: "lifemate-admin-api.database",
        state: "ready",
        source: "live-database-health-probe",
        latencyMs,
        checkedAtUtc,
      },
    ],
    backgroundJobs: {
      state: "unknown",
      source: "not-instrumented",
    },
    deployments: {
      state: "unknown",
      source: "not-instrumented",
      releaseReference: null,
    },
    providers: {
      state: "unknown",
      source: "not-instrumented",
    },
    incidents: {
      state: "unknown",
      source: "not-instrumented",
      activeCount: null,
    },
    freshness: {
      status: "fresh",
      asOfUtc: checkedAtUtc,
    },
  };
}
