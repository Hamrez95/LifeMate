import { ApiError } from "./validation.ts";

export type RateLimitClass =
  | "bootstrap"
  | "expensive-read"
  | "read"
  | "critical-write"
  | "sensitive"
  | "upload"
  | "write";

export type RateLimitPolicy = {
  limit: number;
  windowMs: number;
};

type CounterResult = {
  count: number;
  ttlMs: number;
};

type CounterStore = {
  consume(
    key: string,
    policy: RateLimitPolicy,
    now?: number,
  ): Promise<CounterResult>;
};

type FetchLike = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

export type RateLimiterSnapshot = {
  source: "local" | "redis";
  state: "healthy" | "degraded";
  lastFailureCode: string | null;
  lastFailureAgeMs: number | null;
  lastPrimaryLatencyMs: number | null;
};

export type RateLimitRuntimeConfig = {
  mode: "local" | "redis";
  requireDistributed: boolean;
  redisUrl: string | null;
  redisToken: string | null;
};

export type RateLimitRuntimeSources = {
  mode?: string | null;
  requireDistributed?: string | null;
  redisUrl?: string | null;
  redisToken?: string | null;
};

const policies: Record<RateLimitClass, RateLimitPolicy> = {
  // These are project-wide admission ceilings when Redis mode is active.
  // Existing route-specific local limits in security.ts remain in place as a
  // second layer and are often intentionally stricter for sensitive mutations.
  bootstrap: { limit: 30, windowMs: 60_000 },
  "expensive-read": { limit: 90, windowMs: 60_000 },
  read: { limit: 240, windowMs: 60_000 },
  "critical-write": { limit: 120, windowMs: 60_000 },
  sensitive: { limit: 60, windowMs: 60 * 60_000 },
  upload: { limit: 24, windowMs: 60 * 60_000 },
  write: { limit: 120, windowMs: 60_000 },
};

export class RequestRateLimiter {
  private readonly fallback: InMemoryCounterStore;
  private readonly denyCache = new Map<string, number>();
  private lastDegradedWarningAt = 0;
  private primaryHealthy = true;
  private lastPrimaryFailureAt = 0;
  private lastPrimaryFailureCode: string | null = null;
  private lastPrimaryLatencyMs: number | null = null;

  constructor(
    private readonly primary: CounterStore,
    private readonly source: "local" | "redis",
    fallback?: InMemoryCounterStore,
  ) {
    this.fallback = fallback ?? new InMemoryCounterStore();
  }

  async enforce(method: string, path: string, subject: string): Promise<void> {
    const rateClass = classifyRequest(method, path);
    const policy = policies[rateClass];
    const key = await buildRateLimitKey(subject, rateClass);
    const now = Date.now();

    if (this.source === "redis" && this.isLocallyDenied(key, now)) {
      throw rateLimited();
    }

    let result: CounterResult;
    let effectiveLimit = policy.limit;
    let usedPrimary = false;
    const primaryStartedAt = performance.now();

    try {
      result = await this.primary.consume(key, policy);
      usedPrimary = true;
      this.lastPrimaryLatencyMs = boundedLatencyMs(
        performance.now() - primaryStartedAt,
      );
      this.primaryHealthy = true;
    } catch (error) {
      this.lastPrimaryLatencyMs = boundedLatencyMs(
        performance.now() - primaryStartedAt,
      );
      this.primaryHealthy = false;
      this.lastPrimaryFailureAt = now;
      this.lastPrimaryFailureCode = classifyRateLimitFailure(error);
      // Shared rate limiting must never silently become unlimited. If Redis is
      // unavailable, use a deliberately conservative isolate-local fallback.
      const degradedPolicy = {
        limit: Math.max(1, Math.ceil(policy.limit / 4)),
        windowMs: policy.windowMs,
      };
      effectiveLimit = degradedPolicy.limit;
      result = await this.fallback.consume(key, degradedPolicy, now);
      if (now - this.lastDegradedWarningAt >= 30_000) {
        this.lastDegradedWarningAt = now;
        console.warn("LifeMate distributed rate limiter degraded", {
          source: this.source,
          rateClass,
          code: this.lastPrimaryFailureCode,
          latencyMs: this.lastPrimaryLatencyMs,
        });
      }
    }

    if (result.count > effectiveLimit) {
      if (this.source === "redis" && usedPrimary) {
        this.rememberSharedDenial(key, result.ttlMs, now);
      }
      throw rateLimited();
    }
  }

  snapshot(now = Date.now()): RateLimiterSnapshot {
    return {
      source: this.source,
      state: this.primaryHealthy ? "healthy" : "degraded",
      lastFailureCode: this.lastPrimaryFailureCode,
      lastFailureAgeMs: this.lastPrimaryFailureAt > 0
        ? Math.max(0, now - this.lastPrimaryFailureAt)
        : null,
      lastPrimaryLatencyMs: this.lastPrimaryLatencyMs,
    };
  }

  private isLocallyDenied(key: string, now: number): boolean {
    const deniedUntil = this.denyCache.get(key);
    if (deniedUntil === undefined) return false;
    if (deniedUntil <= now) {
      this.denyCache.delete(key);
      return false;
    }
    return true;
  }

  private rememberSharedDenial(key: string, ttlMs: number, now: number): void {
    if (this.denyCache.size >= 4_000) {
      for (const [entryKey, deniedUntil] of this.denyCache) {
        if (deniedUntil <= now) this.denyCache.delete(entryKey);
      }
      if (this.denyCache.size >= 4_000) {
        const oldestKey = this.denyCache.keys().next().value;
        if (typeof oldestKey === "string") this.denyCache.delete(oldestKey);
      }
    }
    const boundedTtl = Math.max(1, Math.min(ttlMs, 60 * 60_000));
    this.denyCache.set(key, now + boundedTtl);
  }
}

export class InMemoryCounterStore implements CounterStore {
  private readonly windows = new Map<
    string,
    { count: number; resetAt: number }
  >();

  async consume(
    key: string,
    policy: RateLimitPolicy,
    now = Date.now(),
  ): Promise<CounterResult> {
    const current = this.windows.get(key);
    if (!current || current.resetAt <= now) {
      const resetAt = now + policy.windowMs;
      this.windows.set(key, { count: 1, resetAt });
      return { count: 1, ttlMs: policy.windowMs };
    }

    current.count += 1;
    if (this.windows.size > 4_000) {
      for (const [entryKey, entry] of this.windows) {
        if (entry.resetAt <= now) this.windows.delete(entryKey);
      }
    }
    return {
      count: current.count,
      ttlMs: Math.max(1, current.resetAt - now),
    };
  }
}

export class UpstashRestCounterStore implements CounterStore {
  private static readonly script = [
    "local current = redis.call('INCR', KEYS[1])",
    "local ttl = redis.call('PTTL', KEYS[1])",
    "if current == 1 or ttl < 0 then",
    "  redis.call('PEXPIRE', KEYS[1], ARGV[1])",
    "  ttl = tonumber(ARGV[1])",
    "end",
    "return {current, ttl}",
  ].join("\n");

  constructor(
    private readonly url: string,
    private readonly token: string,
    private readonly fetcher: FetchLike = fetch,
    private readonly timeoutMs = 800,
  ) {}

  async consume(
    key: string,
    policy: RateLimitPolicy,
  ): Promise<CounterResult> {
    const response = await this.fetcher(this.url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify([
        "EVAL",
        UpstashRestCounterStore.script,
        "1",
        key,
        String(policy.windowMs),
      ]),
      signal: AbortSignal.timeout(this.timeoutMs),
    });
    if (!response.ok) {
      throw new Error(`redis_http_${response.status}`);
    }
    const payload = await response.json();
    const result = Array.isArray(payload?.result) ? payload.result : null;
    if (!result || result.length < 2) {
      throw new Error("redis_invalid_response");
    }
    const count = Number(result[0]);
    const ttlMs = Number(result[1]);
    if (!Number.isFinite(count) || !Number.isFinite(ttlMs) || count < 1) {
      throw new Error("redis_invalid_counter");
    }
    return {
      count,
      ttlMs: Math.max(1, Math.min(policy.windowMs, ttlMs)),
    };
  }
}

export function resolveRateLimitRuntimeConfig(
  sources: RateLimitRuntimeSources,
): RateLimitRuntimeConfig {
  const mode = (sources.mode ?? "local").trim().toLowerCase();
  const requireDistributed = parseBooleanSetting(
    "LIFEMATE_REQUIRE_DISTRIBUTED_RATE_LIMIT",
    sources.requireDistributed,
    false,
  );

  if (mode === "redis") {
    const redisUrl = sources.redisUrl?.trim() ?? "";
    const redisToken = sources.redisToken?.trim() ?? "";
    if (!/^https:\/\//i.test(redisUrl) || redisToken.length < 20) {
      throw new Error(
        "Redis rate-limit mode requires UPSTASH_REDIS_REST_URL over HTTPS and a valid REST token.",
      );
    }
    return {
      mode: "redis",
      requireDistributed,
      redisUrl,
      redisToken,
    };
  }

  if (mode !== "local") {
    throw new Error("LIFEMATE_RATE_LIMIT_MODE must be local or redis.");
  }
  if (requireDistributed) {
    throw new Error(
      "Distributed rate limiting is required but Redis mode is not configured.",
    );
  }
  return {
    mode: "local",
    requireDistributed,
    redisUrl: null,
    redisToken: null,
  };
}

export function createRequestRateLimiterFromEnvironment(): RequestRateLimiter {
  const config = resolveRateLimitRuntimeConfig({
    mode: Deno.env.get("LIFEMATE_RATE_LIMIT_MODE"),
    requireDistributed: Deno.env.get("LIFEMATE_REQUIRE_DISTRIBUTED_RATE_LIMIT"),
    redisUrl: Deno.env.get("UPSTASH_REDIS_REST_URL"),
    redisToken: Deno.env.get("UPSTASH_REDIS_REST_TOKEN"),
  });

  if (config.mode === "redis") {
    return new RequestRateLimiter(
      new UpstashRestCounterStore(config.redisUrl!, config.redisToken!),
      "redis",
    );
  }
  return new RequestRateLimiter(new InMemoryCounterStore(), "local");
}

export function classifyRequest(method: string, path: string): RateLimitClass {
  const verb = method.toUpperCase();
  if (verb === "POST" && path === "/api/v1/users/bootstrap") {
    return "bootstrap";
  }
  if (path === "/api/v1/me/profile/photo") return "upload";
  if (path === "/api/v1/account/data-export") return "sensitive";
  if (
    path === "/api/v1/home-snapshot" ||
    path === "/api/v1/women-calendar/dashboard"
  ) {
    return "expensive-read";
  }
  if (
    verb === "POST" &&
    /^\/api\/v1\/dose-occurrences\/[0-9a-f-]{36}\/report$/i.test(path)
  ) {
    return "critical-write";
  }
  if (
    path.startsWith("/api/v1/care/invitations") ||
    path.startsWith("/api/v1/care/requests") ||
    path.startsWith("/api/v1/account/deletion-requests") ||
    path === "/api/v1/me/identities/sync"
  ) {
    return verb === "GET" ? "read" : "sensitive";
  }
  if (verb === "GET" || verb === "HEAD") return "read";
  return "write";
}

export async function buildRateLimitKey(
  subject: string,
  rateClass: RateLimitClass,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`lifemate:${subject}`),
  );
  const suffix = Array.from(new Uint8Array(digest).slice(0, 16))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return `lm:rl:v1:${rateClass}:${suffix}`;
}

export function classifyRateLimitFailure(error: unknown): string {
  if (
    error instanceof DOMException &&
    (error.name === "TimeoutError" || error.name === "AbortError")
  ) {
    return "timeout";
  }
  if (error instanceof Error) {
    if (/^redis_http_[1-5][0-9]{2}$/.test(error.message)) {
      return error.message;
    }
    if (
      error.message === "redis_invalid_response" ||
      error.message === "redis_invalid_counter"
    ) {
      return error.message;
    }
  }
  return "error";
}

function parseBooleanSetting(
  name: string,
  raw: string | null | undefined,
  fallback: boolean,
): boolean {
  if (raw === null || raw === undefined || raw.trim() === "") return fallback;
  const normalized = raw.trim().toLowerCase();
  if (normalized === "true") return true;
  if (normalized === "false") return false;
  throw new Error(`${name} must be true or false.`);
}

function boundedLatencyMs(value: number): number {
  if (!Number.isFinite(value)) return 60_000;
  return Math.max(0, Math.min(60_000, Math.round(value)));
}

function rateLimited(): ApiError {
  return new ApiError(
    429,
    "rate_limit_exceeded",
    "Too many requests. Try again later.",
  );
}
