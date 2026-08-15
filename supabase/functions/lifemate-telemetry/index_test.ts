import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  parseClientErrorTelemetry,
  SubjectTelemetryRateLimiter,
} from "./privacy_safe_event.ts";

const valid = {
  eventId: "123e4567-e89b-42d3-a456-426614174888",
  application: "wellmate",
  releaseVersion: "0.9.0-internal.9+20",
  platform: "android",
  source: "flutter_framework",
  errorType: "StateError",
  stackFingerprint: "0123456789abcdef",
  fatal: true,
};

Deno.test("accepts only bounded privacy-safe crash dimensions", () => {
  assertEquals(parseClientErrorTelemetry(valid), valid);
});

Deno.test("rejects raw message, stack, token, and user identifiers", () => {
  for (
    const [key, value] of Object.entries({
      message: "patient@example.test took medication X",
      stack: "Bearer secret-token",
      accessToken: "secret",
      userId: "123e4567-e89b-42d3-a456-426614174000",
      requestBody: "health-data",
    })
  ) {
    assertThrows(
      () => parseClientErrorTelemetry({ ...valid, [key]: value }),
      Error,
      "client_telemetry_field_forbidden",
    );
  }
});

Deno.test("rejects unbounded or free-form error fields", () => {
  assertThrows(
    () =>
      parseClientErrorTelemetry({ ...valid, errorType: "Error: email=x@y.z" }),
    Error,
    "error_type_invalid",
  );
  assertThrows(
    () =>
      parseClientErrorTelemetry({ ...valid, stackFingerprint: "raw stack" }),
    Error,
    "stack_fingerprint_invalid",
  );
});

Deno.test("rate limiter bounds events per authenticated subject", () => {
  const limiter = new SubjectTelemetryRateLimiter(2, 60_000, 10);
  assertEquals(limiter.allow("subject-a", 1_000), true);
  assertEquals(limiter.allow("subject-a", 2_000), true);
  assertEquals(limiter.allow("subject-a", 3_000), false);
  assertEquals(limiter.allow("subject-b", 3_000), true);
  assertEquals(limiter.allow("subject-a", 61_001), true);
});

Deno.test("rate limiter fails closed when subject memory cap is reached", () => {
  const limiter = new SubjectTelemetryRateLimiter(2, 60_000, 1);
  assertEquals(limiter.allow("subject-a", 1_000), true);
  assertEquals(limiter.allow("subject-b", 2_000), false);
  assertEquals(limiter.allow("subject-b", 61_001), true);
});
