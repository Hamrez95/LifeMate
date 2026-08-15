import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { parseClientErrorTelemetry } from "./client_error_telemetry.ts";
import { safeError } from "./http.ts";

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

Deno.test("client crash telemetry accepts bounded non-sensitive dimensions", () => {
  assertEquals(parseClientErrorTelemetry(valid), valid);
});

Deno.test("client crash telemetry rejects raw messages and stacks", () => {
  assertThrows(
    () => parseClientErrorTelemetry({ ...valid, message: "patient@example.test" }),
    Error,
    "client_telemetry_field_forbidden",
  );
  assertThrows(
    () => parseClientErrorTelemetry({ ...valid, stack: "Bearer secret-token" }),
    Error,
    "client_telemetry_field_forbidden",
  );
});

Deno.test("safeError never copies exception messages into logs", () => {
  const safe = safeError(
    new Error("email=patient@example.test medication=private-secret"),
  );
  assertEquals(safe.name, "Error");
  assertEquals("message" in safe, false);
});
