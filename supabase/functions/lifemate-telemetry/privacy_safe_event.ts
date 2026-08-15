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

export function parseClientErrorTelemetry(
  input: Record<string, unknown>,
): ClientErrorTelemetry {
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
    if (!allowed.has(key)) invalid("client_telemetry_field_forbidden");
  }

  const eventId = stringValue(input.eventId, "event_id_invalid");
  const application = stringValue(input.application, "application_invalid");
  const releaseVersion = stringValue(
    input.releaseVersion,
    "release_version_invalid",
  );
  const platform = stringValue(input.platform, "platform_invalid");
  const source = stringValue(input.source, "source_invalid");
  const errorType = stringValue(input.errorType, "error_type_invalid");
  const stackFingerprint = stringValue(
    input.stackFingerprint,
    "stack_fingerprint_invalid",
  ).toLowerCase();

  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(eventId)
  ) {
    invalid("event_id_invalid");
  }
  if (application !== "wellmate" && application !== "caremate") {
    invalid("application_invalid");
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$/.test(releaseVersion)) {
    invalid("release_version_invalid");
  }
  if (
    ![
      "android",
      "ios",
      "web",
      "windows",
      "macos",
      "linux",
      "unknown",
    ].includes(platform)
  ) {
    invalid("platform_invalid");
  }
  if (
    ![
      "flutter_framework",
      "platform_dispatcher",
      "zone",
    ].includes(source)
  ) {
    invalid("source_invalid");
  }
  if (!/^[A-Za-z_][A-Za-z0-9_.]{0,79}$/.test(errorType)) {
    invalid("error_type_invalid");
  }
  if (!/^[0-9a-f]{16}$/.test(stackFingerprint)) {
    invalid("stack_fingerprint_invalid");
  }
  if (typeof input.fatal !== "boolean") invalid("fatal_invalid");

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

function stringValue(value: unknown, code: string): string {
  if (typeof value !== "string") invalid(code);
  return value;
}

function invalid(code: string): never {
  throw new Error(code);
}

export function safeValidationCode(error: unknown): string {
  const message = error instanceof Error ? error.message : "invalid_payload";
  return /^[a-z0-9_]{3,48}$/.test(message) ? message : "invalid_payload";
}
