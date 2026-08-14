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
};

const policies: Record<RateLimitClass, RateLimitPolicy> = {
  // These are project-wide admission ceilings. Existing route-specific local
  // limits in security.ts remain in place as a second layer and are often
  // intentionally stricter for sensitive mutations.
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
  private lastDegradedWarningAt = 0;
  private primaryHealthy = true;
  private lastPrimaryFailureAt = 0;
  private lastPrimaryFailureCode: string | null = null;

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
    let result: CounterResult;
    let effectiveLimit = policy.limit;

    try {
      result = await this.primary.consume(key, policy);
      this.primaryHealthy = true;
    } catch (error) {
      this.primaryHealthy = false;
      this.lastPrimaryFailureAt = Date.now();
      this.lastPrimaryFailureCode = safeRateLimitError(error);
      // Shared rate limiting must never silently become unlimited. If Redis is
      // unavailable, use a deliberately conservative isolate-local fallback.
      const degradedPolicy = {
        limit: Math.max(1, Math.ceil(policy.limit / 4)),
        windowMs: policy.windowMs,
      };
      effectiveLimit = degradedPolicy.limit;
      result = await this.fallback.consume(key, degradedPolicy);
      const now = Date.now();
      if (now - this.lastDegradedWarningAt >= 30_000) {
        this.lastDegradedWarningAt = now;
        console.warn("LifeMate distributed rate limiter degraded", {
          source: this.source,
          rateClass,
          code: this.lastPrimaryFailureCode,
        });
      }
    }

    if (result.count > effectiveLimit) {
      throw new ApiError(
        429,
        "rate_limit_exceeded",
        "Too many requests. Try again later.",
      );
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
    };
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

export function createRequestRateLimiterFromEnvironment(): RequestRateLimiter {
  const mode = (Deno.env.get("LIFEMATE_RATE_LIMIT_MODE") ?? "local")
    .trim()
    .toLowerCase();
  const requireDistributed =
    (Deno.env.get("LIFEMATE_REQUIRE_DISTRIBUTED_RATE_LIMIT") ?? "false")
      .trim()
      .toLowerCase() === "true";

  if (mode === "redis") {
    const url = Deno.env.get("UPSTASH_REDIS_REST_URL")?.trim() ?? "";
    const token = Deno.env.get("UPSTASH_REDIS_REST_TOKEN")?.trim() ?? "";
    if (!/^https:\/\//i.test(url) || token.length < 20) {
      throw new Error(
        "Redis rate-limit mode requires UPSTASH_REDIS_REST_URL over HTTPS and a valid REST token.",
      );
    }
    return new RequestRateLimiter(
      new UpstashRestCounterStore(url, token),
      "redis",
    );
  }

  if (mode !== "local") {
    throw new Error("LIFEMATE_RATE_LIMIT_MODE must be local or redis.");
  }
  if (requireDistributed) {
    throw new Error(
      "Distributed rate limiting is required but Redis mode is not configured.",
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

function safeRateLimitError(error: unknown): string {
  if (error instanceof DOMException && error.name === "TimeoutError") {
    return "timeout";
  }
  if (error instanceof Error) {
    return error.message.replace(/[^a-zA-Z0-9:_-]/g, "_").slice(0, 64) ||
      "error";
  }
  return "error";
}
