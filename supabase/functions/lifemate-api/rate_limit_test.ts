import {
  assert,
  assertEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import {
  buildRateLimitKey,
  classifyRequest,
  InMemoryCounterStore,
  RequestRateLimiter,
  UpstashRestCounterStore,
} from "./rate_limit.ts";
import { ApiError } from "./validation.ts";

Deno.test("request classes distinguish expensive reads and critical writes", () => {
  assertEquals(classifyRequest("GET", "/api/v1/home-snapshot"), "expensive-read");
  assertEquals(classifyRequest("GET", "/api/v1/me"), "read");
  assertEquals(
    classifyRequest(
      "POST",
      "/api/v1/dose-occurrences/123e4567-e89b-42d3-a456-426614174000/report",
    ),
    "critical-write",
  );
  assertEquals(classifyRequest("POST", "/api/v1/care/invitations"), "sensitive");
  assertEquals(classifyRequest("PUT", "/api/v1/me/profile/photo"), "upload");
});

Deno.test("rate-limit keys are stable and do not expose the raw account id", async () => {
  const subject = "123e4567-e89b-42d3-a456-426614174000";
  const first = await buildRateLimitKey(subject, "read");
  const second = await buildRateLimitKey(subject, "read");
  assertEquals(first, second);
  assert(first.startsWith("lm:rl:v1:read:"));
  assert(!first.includes(subject));
});

Deno.test("local request limiter rejects excess requests", async () => {
  const limiter = new RequestRateLimiter(new InMemoryCounterStore(), "local");
  const subject = crypto.randomUUID();
  for (let index = 0; index < 240; index++) {
    await limiter.enforce("GET", "/api/v1/me", subject);
  }
  const error = await assertRejects(
    () => limiter.enforce("GET", "/api/v1/me", subject),
    ApiError,
  );
  assertEquals(error.status, 429);
  assertEquals(error.code, "rate_limit_exceeded");
});

Deno.test("two Redis-backed limiter instances consume one shared quota", async () => {
  const counters = new Map<string, number>();
  const fakeFetch = async (_input: string | URL | Request, init?: RequestInit) => {
    const command = JSON.parse(String(init?.body ?? "[]"));
    const key = String(command[3]);
    const count = (counters.get(key) ?? 0) + 1;
    counters.set(key, count);
    return Response.json({ result: [count, 60_000] });
  };

  const first = new RequestRateLimiter(
    new UpstashRestCounterStore("https://redis.example", "token-token-token-token", fakeFetch),
    "redis",
  );
  const second = new RequestRateLimiter(
    new UpstashRestCounterStore("https://redis.example", "token-token-token-token", fakeFetch),
    "redis",
  );
  const subject = crypto.randomUUID();
  for (let index = 0; index < 120; index++) {
    await (index % 2 === 0 ? first : second).enforce(
      "POST",
      "/api/v1/treatment-plans",
      subject,
    );
  }
  const error = await assertRejects(
    () => first.enforce("POST", "/api/v1/treatment-plans", subject),
    ApiError,
  );
  assertEquals(error.status, 429);
});

Deno.test("Redis failure falls back to a conservative local quota", async () => {
  const failingFetch = async () => {
    throw new Error("redis_down");
  };
  const limiter = new RequestRateLimiter(
    new UpstashRestCounterStore(
      "https://redis.example",
      "token-token-token-token",
      failingFetch,
    ),
    "redis",
  );
  const subject = crypto.randomUUID();
  // read policy is 240/min, degraded fallback is 60/min.
  for (let index = 0; index < 60; index++) {
    await limiter.enforce("GET", "/api/v1/me", subject);
  }
  const error = await assertRejects(
    () => limiter.enforce("GET", "/api/v1/me", subject),
    ApiError,
  );
  assertEquals(error.status, 429);
});
