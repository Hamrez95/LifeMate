import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ApiObservability,
  inferTelemetrySubsystem,
  normalizeTelemetryRoute,
  withCorrelationId,
} from "./observability.ts";

Deno.test("telemetry route labels remove high-cardinality identifiers", () => {
  assertEquals(
    normalizeTelemetryRoute(
      "/api/v1/dose-occurrences/123e4567-e89b-42d3-a456-426614174888/report",
    ),
    "/api/v1/dose-occurrences/:id/report",
  );
  assertEquals(
    normalizeTelemetryRoute("/api/v1/resource/1234567890"),
    "/api/v1/resource/:number",
  );
  assertEquals(
    normalizeTelemetryRoute(
      "/api/v1/invitations/abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN0123456789",
    ),
    "/api/v1/invitations/:opaque",
  );
});

Deno.test("telemetry windows classify overload and expose bounded latency histograms", () => {
  const start = Date.parse("2026-08-14T17:00:00.000Z");
  const telemetry = new ApiObservability(
    "lifemate-api",
    "test-release",
    1000,
    start,
  );
  const healthy = {
    source: "redis" as const,
    state: "healthy" as const,
    lastFailureCode: null,
    lastFailureAgeMs: null,
    lastPrimaryLatencyMs: 7,
  };

  assertEquals(
    telemetry.record({
      method: "GET",
      path: "/api/v1/home-snapshot",
      status: 200,
      controlledOverload: false,
      durationMs: 112,
      subsystem: "application",
      concurrency: { total: 3, nonCritical: 3, expensive: 1 },
      rateLimiter: healthy,
    }, start + 100),
    null,
  );

  const window = telemetry.record({
    method: "GET",
    path: "/api/v1/home-snapshot",
    status: 503,
    controlledOverload: true,
    durationMs: 8,
    subsystem: "concurrency",
    concurrency: { total: 16, nonCritical: 12, expensive: 6 },
    rateLimiter: healthy,
  }, start + 1000);

  assert(window !== null);
  assertEquals(window.requests, 2);
  assertEquals(window.status.success, 1);
  assertEquals(window.status.controlledOverload, 1);
  assertEquals(window.failuresBySubsystem.concurrency, 1);
  assertEquals(window.concurrencyHighWater.total, 16);
  assertEquals(window.latency.bucketsMs["<=50"], 1);
  assertEquals(window.latency.bucketsMs["<=250"], 1);
  assertEquals(window.routes["GET /api/v1/home-snapshot"].count, 2);
  assertEquals(window.rateLimiter.lastPrimaryLatencyMs, 7);
});

Deno.test("telemetry subsystem inference distinguishes capacity failures", () => {
  assertEquals(
    inferTelemetrySubsystem(429, "rate_limit_exceeded"),
    "rate_limit",
  );
  assertEquals(
    inferTelemetrySubsystem(503, "server_overloaded"),
    "concurrency",
  );
  assertEquals(inferTelemetrySubsystem(503, "database_busy"), "database");
  assertEquals(
    inferTelemetrySubsystem(409, "idempotency_in_progress"),
    "idempotency",
  );
  assertEquals(inferTelemetrySubsystem(500, "internal_error"), "application");
});

Deno.test("correlation response header is added without changing status", async () => {
  const original = new Response(JSON.stringify({ ok: true }), {
    status: 202,
    headers: { "content-type": "application/json" },
  });
  const response = withCorrelationId(
    original,
    "123e4567-e89b-42d3-a456-426614174888",
  );

  assertEquals(response.status, 202);
  assertEquals(
    response.headers.get("x-correlation-id"),
    "123e4567-e89b-42d3-a456-426614174888",
  );
  assertEquals(await response.json(), { ok: true });
});
