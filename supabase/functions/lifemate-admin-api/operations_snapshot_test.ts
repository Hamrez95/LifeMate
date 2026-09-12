import { buildOperationsSnapshot } from "./operations_snapshot.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("operations snapshot reports only observed database readiness and keeps missing telemetry unknown", async () => {
  let probes = 0;
  const ticks = [10, 12.34];
  const snapshot = await buildOperationsSnapshot({
    checkDatabase: async () => {
      probes += 1;
    },
    now: () => new Date("2026-08-26T00:00:00.000Z"),
    monotonicNow: () => ticks.shift() ?? 12.34,
  });

  assert(probes === 1, "database health must be probed exactly once");
  assert(
    snapshot.services.length === 1,
    "only the observed service signal should be emitted",
  );
  assert(
    snapshot.services[0].state === "ready",
    "successful live database probe must be ready",
  );
  assert(
    snapshot.services[0].latencyMs === 2.3,
    "latency must come from the live probe duration",
  );
  assert(
    snapshot.backgroundJobs.state === "unknown",
    "jobs must remain unknown without instrumentation",
  );
  assert(
    snapshot.deployments.state === "unknown",
    "deployments must remain unknown without instrumentation",
  );
  assert(
    snapshot.deployments.releaseReference === null,
    "release reference must not be fabricated",
  );
  assert(
    snapshot.providers.state === "unknown",
    "provider connectivity must remain unknown without instrumentation",
  );
  assert(
    snapshot.incidents.state === "unknown",
    "incidents must remain unknown without instrumentation",
  );
  assert(
    snapshot.incidents.activeCount === null,
    "incident count must not be fabricated",
  );
  assert(
    snapshot.freshness.asOfUtc === "2026-08-26T00:00:00.000Z",
    "freshness must be explicit",
  );
});

Deno.test("operations snapshot fails closed when the live database probe fails", async () => {
  let failed = false;
  try {
    await buildOperationsSnapshot({
      checkDatabase: () => Promise.reject(new Error("database unavailable")),
    });
  } catch {
    failed = true;
  }
  assert(
    failed,
    "failed live probe must not be converted into a fabricated ready snapshot",
  );
});
