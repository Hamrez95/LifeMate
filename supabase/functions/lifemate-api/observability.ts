export type TelemetrySubsystem =
  | "application"
  | "authentication"
  | "concurrency"
  | "database"
  | "idempotency"
  | "rate_limit";

export type ConcurrencyTelemetrySnapshot = {
  total: number;
  nonCritical: number;
  expensive: number;
};

export type RateLimiterTelemetrySnapshot = {
  source: "local" | "redis";
  state: "healthy" | "degraded";
  lastFailureCode: string | null;
  lastFailureAgeMs: number | null;
};

export type RequestTelemetryInput = {
  method: string;
  path: string;
  status: number;
  controlledOverload: boolean;
  durationMs: number;
  subsystem: TelemetrySubsystem;
  concurrency: ConcurrencyTelemetrySnapshot;
  rateLimiter: RateLimiterTelemetrySnapshot;
};

type RouteStats = {
  count: number;
  success: number;
  controlledOverload: number;
  clientError: number;
  serverError: number;
};

export type TelemetryWindow = {
  event: "lifemate.telemetry.window";
  service: string;
  releaseVersion: string;
  windowStartedAtUtc: string;
  windowEndedAtUtc: string;
  durationMs: number;
  requests: number;
  status: {
    success: number;
    controlledOverload: number;
    clientError: number;
    serverError: number;
  };
  failuresBySubsystem: Record<TelemetrySubsystem, number>;
  latency: {
    bucketsMs: Record<string, number>;
    p50UpperBoundMs: number | null;
    p95UpperBoundMs: number | null;
    p99UpperBoundMs: number | null;
    maxMs: number;
  };
  concurrencyHighWater: ConcurrencyTelemetrySnapshot;
  rateLimiter: RateLimiterTelemetrySnapshot;
  routes: Record<string, RouteStats>;
};

const latencyBoundsMs = [50, 100, 250, 500, 1000, 2000, 5000, 10000] as const;
const maximumRouteDimensions = 64;

export class ApiObservability {
  private windowStartedAtMs: number;
  private requests = 0;
  private success = 0;
  private controlledOverload = 0;
  private clientError = 0;
  private serverError = 0;
  private maxLatencyMs = 0;
  private readonly latencyBuckets = new Map<string, number>();
  private readonly failuresBySubsystem = new Map<TelemetrySubsystem, number>();
  private readonly routes = new Map<string, RouteStats>();
  private concurrencyHighWater: ConcurrencyTelemetrySnapshot = {
    total: 0,
    nonCritical: 0,
    expensive: 0,
  };
  private rateLimiter: RateLimiterTelemetrySnapshot = {
    source: "local",
    state: "healthy",
    lastFailureCode: null,
    lastFailureAgeMs: null,
  };

  constructor(
    private readonly service: string,
    private readonly releaseVersion: string,
    private readonly windowMs = 10_000,
    nowMs = Date.now(),
  ) {
    if (!Number.isFinite(windowMs) || windowMs < 1_000 || windowMs > 60_000) {
      throw new Error("Observability window must be between 1s and 60s.");
    }
    this.windowStartedAtMs = nowMs;
    this.resetBuckets();
    this.resetSubsystems();
  }

  record(
    input: RequestTelemetryInput,
    nowMs = Date.now(),
  ): TelemetryWindow | null {
    this.requests += 1;
    const category = statusCategory(
      input.status,
      input.controlledOverload,
    );
    this[category] += 1;
    if (category !== "success") {
      this.failuresBySubsystem.set(
        input.subsystem,
        (this.failuresBySubsystem.get(input.subsystem) ?? 0) + 1,
      );
    }

    const duration = Math.max(
      0,
      Math.min(60_000, Math.round(input.durationMs)),
    );
    this.maxLatencyMs = Math.max(this.maxLatencyMs, duration);
    this.latencyBuckets.set(
      latencyBucket(duration),
      (this.latencyBuckets.get(latencyBucket(duration)) ?? 0) + 1,
    );

    this.concurrencyHighWater = {
      total: Math.max(this.concurrencyHighWater.total, input.concurrency.total),
      nonCritical: Math.max(
        this.concurrencyHighWater.nonCritical,
        input.concurrency.nonCritical,
      ),
      expensive: Math.max(
        this.concurrencyHighWater.expensive,
        input.concurrency.expensive,
      ),
    };
    this.rateLimiter = { ...input.rateLimiter };

    const route = `${input.method.toUpperCase()} ${
      normalizeTelemetryRoute(input.path)
    }`;
    const routeKey =
      this.routes.has(route) || this.routes.size < maximumRouteDimensions
        ? route
        : "OTHER";
    const stats = this.routes.get(routeKey) ?? {
      count: 0,
      success: 0,
      controlledOverload: 0,
      clientError: 0,
      serverError: 0,
    };
    stats.count += 1;
    stats[category] += 1;
    this.routes.set(routeKey, stats);

    if (nowMs - this.windowStartedAtMs < this.windowMs) return null;
    return this.rotate(nowMs);
  }

  flush(nowMs = Date.now()): TelemetryWindow | null {
    if (this.requests === 0) return null;
    return this.rotate(nowMs);
  }

  private rotate(nowMs: number): TelemetryWindow {
    const requestCount = this.requests;
    const buckets = Object.fromEntries(this.latencyBuckets);
    const failures = Object.fromEntries(this.failuresBySubsystem) as Record<
      TelemetrySubsystem,
      number
    >;
    const window: TelemetryWindow = {
      event: "lifemate.telemetry.window",
      service: this.service,
      releaseVersion: this.releaseVersion,
      windowStartedAtUtc: new Date(this.windowStartedAtMs).toISOString(),
      windowEndedAtUtc: new Date(nowMs).toISOString(),
      durationMs: Math.max(1, nowMs - this.windowStartedAtMs),
      requests: requestCount,
      status: {
        success: this.success,
        controlledOverload: this.controlledOverload,
        clientError: this.clientError,
        serverError: this.serverError,
      },
      failuresBySubsystem: failures,
      latency: {
        bucketsMs: buckets,
        p50UpperBoundMs: percentileUpperBound(buckets, requestCount, 0.50),
        p95UpperBoundMs: percentileUpperBound(buckets, requestCount, 0.95),
        p99UpperBoundMs: percentileUpperBound(buckets, requestCount, 0.99),
        maxMs: this.maxLatencyMs,
      },
      concurrencyHighWater: { ...this.concurrencyHighWater },
      rateLimiter: { ...this.rateLimiter },
      routes: Object.fromEntries(this.routes),
    };

    this.windowStartedAtMs = nowMs;
    this.requests = 0;
    this.success = 0;
    this.controlledOverload = 0;
    this.clientError = 0;
    this.serverError = 0;
    this.maxLatencyMs = 0;
    this.routes.clear();
    this.concurrencyHighWater = { total: 0, nonCritical: 0, expensive: 0 };
    this.resetBuckets();
    this.resetSubsystems();
    return window;
  }

  private resetBuckets(): void {
    this.latencyBuckets.clear();
    for (const bound of latencyBoundsMs) {
      this.latencyBuckets.set(`<=${bound}`, 0);
    }
    this.latencyBuckets.set(">10000", 0);
  }

  private resetSubsystems(): void {
    this.failuresBySubsystem.clear();
    for (
      const subsystem of [
        "application",
        "authentication",
        "concurrency",
        "database",
        "idempotency",
        "rate_limit",
      ] as const
    ) {
      this.failuresBySubsystem.set(subsystem, 0);
    }
  }
}

export function normalizeTelemetryRoute(path: string): string {
  const safePath = path.split("?", 1)[0] || "/";
  const segments = safePath.split("/").map((segment) => {
    if (!segment) return segment;
    if (/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(segment)) return ":id";
    if (/^\d+$/.test(segment)) return ":number";
    if (/^[A-Za-z0-9_-]{32,}$/.test(segment)) return ":opaque";
    return segment.slice(0, 80);
  });
  return segments.join("/").slice(0, 240) || "/";
}

export function inferTelemetrySubsystem(
  status: number,
  code?: string | null,
): TelemetrySubsystem {
  const normalized = code ?? "";
  if (normalized === "rate_limit_exceeded") return "rate_limit";
  if (normalized === "server_overloaded") return "concurrency";
  if (normalized.startsWith("database_")) return "database";
  if (
    normalized === "authorization_missing" ||
    normalized === "invalid_session" ||
    normalized === "identity_provider_unavailable"
  ) {
    return "authentication";
  }
  if (normalized.startsWith("idempotency_")) return "idempotency";
  if (status === 429) return "rate_limit";
  return "application";
}

export function withCorrelationId(
  response: Response,
  correlationId: string,
): Response {
  const headers = new Headers(response.headers);
  headers.set("X-Correlation-Id", correlationId);
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function statusCategory(
  status: number,
  controlledOverload: boolean,
): "success" | "controlledOverload" | "clientError" | "serverError" {
  if (status >= 200 && status < 400) return "success";
  if (controlledOverload) return "controlledOverload";
  if (status >= 400 && status < 500) return "clientError";
  return "serverError";
}

function latencyBucket(durationMs: number): string {
  for (const bound of latencyBoundsMs) {
    if (durationMs <= bound) return `<=${bound}`;
  }
  return ">10000";
}

function percentileUpperBound(
  buckets: Record<string, number>,
  count: number,
  percentile: number,
): number | null {
  if (count < 1) return null;
  const target = Math.max(1, Math.ceil(count * percentile));
  let cumulative = 0;
  for (const bound of latencyBoundsMs) {
    cumulative += buckets[`<=${bound}`] ?? 0;
    if (cumulative >= target) return bound;
  }
  return 60_000;
}
