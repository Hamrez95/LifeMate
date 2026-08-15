import { ApiError } from "./validation.ts";

export type ClientErrorTelemetry = {
  eventId: string;
  application: "wellmate" | "caremate";
  releaseVersion: string;
  platform:
    | "android"
    | "ios"
    | "web"
    | "windows"
    | "macos"
    | "linux"
    | "unknown";
  source: "flutter_framework" | "platform_dispatcher" | "zone";
  errorType: string;
  stackFingerprint: string;
  fatal: boolean;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const safeReleasePattern = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$/;
const safeErrorTypePattern = /^[A-Za-z_][A-Za-z0-9_.]{0,79}$/;
const fingerprintPattern = /^[0-9a-f]{16}$/;
const applications = new Set(["wellmate", "caremate"]);
const platforms = new Set([
  "android",
  "ios",
  "web",
  "windows",
  "macos",
  "linux",
  "unknown",
]);
const sources = new Set(["flutter_framework", "platform_dispatcher", "zone"]);

export function parseClientErrorTelemetry(
  input: Record<string, unknown>,
): ClientErrorTelemetry {
  const eventId = requireString(input.eventId, "event_id_invalid");
  const application = requireString(input.application, "application_invalid");
  const releaseVersion = requireString(
    input.releaseVersion,
    "release_version_invalid",
  );
  const platform = requireString(input.platform, "platform_invalid");
  const source = requireString(input.source, "source_invalid");
  const errorType = requireString(input.errorType, "error_type_invalid");
  const stackFingerprint = requireString(
    input.stackFingerprint,
    "stack_fingerprint_invalid",
  ).toLowerCase();

  if (!uuidPattern.test(eventId)) {
    invalid("event_id_invalid");
  }
  if (!applications.has(application)) {
    invalid("application_invalid");
  }
  if (!safeReleasePattern.test(releaseVersion)) {
    invalid("release_version_invalid");
  }
  if (!platforms.has(platform)) {
    invalid("platform_invalid");
  }
  if (!sources.has(source)) {
    invalid("source_invalid");
  }
  if (!safeErrorTypePattern.test(errorType)) {
    invalid("error_type_invalid");
  }
  if (!fingerprintPattern.test(stackFingerprint)) {
    invalid("stack_fingerprint_invalid");
  }
  if (typeof input.fatal !== "boolean") {
    invalid("fatal_invalid");
  }

  // Intentionally reject any payload fields that could tempt clients to send
  // raw exception messages, stack traces, health records, JWTs, or request
  // bodies. Operational crash visibility is based on bounded dimensions only.
  const allowed = new Set([
    "eventId",
    "application",
    "releaseVersion",
    "platform",
    "source",
    "errorType",
    "stackFingerprint",
    "fatal",
  ]);
  for (const key of Object.keys(input)) {
    if (!allowed.has(key)) {
      throw new ApiError(
        400,
        "client_telemetry_field_forbidden",
        "Client telemetry contains a forbidden field.",
      );
    }
  }

  return {
    eventId,
    application: application as ClientErrorTelemetry["application"],
    releaseVersion,
    platform: platform as ClientErrorTelemetry["platform"],
    source: source as ClientErrorTelemetry["source"],
    errorType,
    stackFingerprint,
    fatal: input.fatal,
  };
}

function requireString(value: unknown, code: string): string {
  if (typeof value !== "string") invalid(code);
  return value;
}

function invalid(code: string): never {
  throw new ApiError(400, code, "Client telemetry is invalid.");
}
