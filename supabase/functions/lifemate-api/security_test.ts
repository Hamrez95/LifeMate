import {
  assert,
  assertEquals,
  assertNotEquals,
  assertThrows,
} from "jsr:@std/assert@1.0.14";
import {
  createHmac,
  createToken,
  enforceRateLimit,
  maskEmail,
  timingSafeEqual,
} from "./security.ts";
import { ApiError } from "./validation.ts";

Deno.test("invitation tokens are URL-safe high-entropy values", () => {
  const first = createToken();
  const second = createToken();
  assert(/^[A-Za-z0-9_-]{43}$/.test(first));
  assert(/^[A-Za-z0-9_-]{43}$/.test(second));
  assertNotEquals(first, second);
});

Deno.test("HMAC is deterministic, namespaced by caller, and not plaintext", async () => {
  const hmac = createHmac("a-dedicated-test-secret-with-enough-entropy");
  const first = await hmac("contact:user@example.com");
  const second = await hmac("contact:user@example.com");
  const tokenHash = await hmac("token:user@example.com");
  assertEquals(first, second);
  assertNotEquals(first, tokenHash);
  assertNotEquals(first, "user@example.com");
  assertEquals(first.length, 64);
});

Deno.test("timingSafeEqual compares equal-length secrets without early return", () => {
  assert(timingSafeEqual("abc123", "abc123"));
  assert(!timingSafeEqual("abc123", "abc124"));
  assert(!timingSafeEqual("abc123", "short"));
});

Deno.test("maskEmail hides the local part while preserving delivery hint", () => {
  assertEquals(maskEmail("hamidreza@example.com"), "ha********@example.com");
  assertEquals(maskEmail("a@example.com"), "a**@example.com");
});

Deno.test("rate limit blocks excess writes and resets by window", () => {
  const key = `test:${crypto.randomUUID()}`;
  enforceRateLimit(key, 2, 1_000, 1_000);
  enforceRateLimit(key, 2, 1_000, 1_100);
  const error = assertThrows(
    () => enforceRateLimit(key, 2, 1_000, 1_200),
    ApiError,
  );
  assertEquals(error.status, 429);
  enforceRateLimit(key, 2, 1_000, 2_001);
});
