import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { parseClientErrorTelemetry } from "./privacy_safe_event.ts";

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
    () => parseClientErrorTelemetry({ ...valid, errorType: "Error: email=x@y.z" }),
    Error,
    "error_type_invalid",
  );
  assertThrows(
    () => parseClientErrorTelemetry({ ...valid, stackFingerprint: "raw stack" }),
    Error,
    "stack_fingerprint_invalid",
  );
});
