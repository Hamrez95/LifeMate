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

export type ProductTelemetryEventName =
  | "app_opened"
  | "auth_login_succeeded"
  | "auth_session_restored"
  | "onboarding_started"
  | "onboarding_completed"
  | "care_pairing_started"
  | "care_pairing_completed"
  | "care_access_revoked"
  | "offline_queue_enqueued"
  | "offline_queue_recovered";

export type ProductTelemetry = {
  kind: "product";
  eventId: string;
  application: "wellmate" | "caremate";
  releaseVersion: string;
  platform: ClientErrorTelemetry["platform"];
  eventName: ProductTelemetryEventName;
  localeFamily: "fa" | "en" | "other";
  connectivity: "online" | "offline" | "recovering" | "unknown";
  outcome:
    | "success"
    | "failure"
    | "cancelled"
    | "queued"
    | "replayed"
    | "not_applicable";
};

const productEventNames = new Set<ProductTelemetryEventName>([
  "app_opened",
  "auth_login_succeeded",
  "auth_session_restored",
  "onboarding_started",
  "onboarding_completed",
  "care_pairing_started",
  "care_pairing_completed",
  "care_access_revoked",
  "offline_queue_enqueued",
  "offline_queue_recovered",
]);

export class SubjectTelemetryRateLimiter {
  #windows = new Map<string, { startedAt: number; count: number }>();

  constructor(
    private readonly permitLimit = 20,
    private readonly windowMs = 60_000,
    private readonly maximumSubjects = 5_000,
  ) {}

  allow(subject: string, now = Date.now()): boolean {
    this.#prune(now);
    const current = this.#windows.get(subject);
    if (!current || now - current.startedAt >= this.windowMs) {
      if (!current && this.#windows.size >= this.maximumSubjects) return false;
      this.#windows.set(subject, { startedAt: now, count: 1 });
      return true;
    }
    if (current.count >= this.permitLimit) return false;
    current.count += 1;
    return true;
  }

  #prune(now: number): void {
    if (this.#windows.size < this.maximumSubjects) return;
    for (const [subject, window] of this.#windows) {
      if (now - window.startedAt >= this.windowMs) {
        this.#windows.delete(subject);
      }
    }
  }
}

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
  rejectUnknownFields(input, allowed, "client_telemetry_field_forbidden");

  const eventId = validEventId(input.eventId);
  const application = validApplication(input.application);
  const releaseVersion = validReleaseVersion(input.releaseVersion);
  const platform = validPlatform(input.platform);
  const source = stringValue(input.source, "source_invalid");
  const errorType = stringValue(input.errorType, "error_type_invalid");
  const stackFingerprint = stringValue(
    input.stackFingerprint,
    "stack_fingerprint_invalid",
  ).toLowerCase();

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
    application,
    releaseVersion,
    platform,
    source: source as ClientErrorTelemetry["source"],
    errorType,
    stackFingerprint,
    fatal: input.fatal,
  };
}

export function parseProductTelemetry(
  input: Record<string, unknown>,
): ProductTelemetry {
  const allowed = new Set([
    "kind",
    "eventId",
    "application",
    "releaseVersion",
    "platform",
    "eventName",
    "localeFamily",
    "connectivity",
    "outcome",
  ]);
  rejectUnknownFields(input, allowed, "product_telemetry_field_forbidden");

  if (input.kind !== "product") invalid("product_kind_invalid");
  const eventId = validEventId(input.eventId);
  const application = validApplication(input.application);
  const releaseVersion = validReleaseVersion(input.releaseVersion);
  const platform = validPlatform(input.platform);
  const rawEventName = stringValue(input.eventName, "product_event_invalid");
  // `app_open` shipped in the pre-persistence telemetry client. Normalize it
  // at ingestion so already-installed clients remain compatible while every
  // persisted fact uses the canonical taxonomy name `app_opened`.
  const eventName = rawEventName === "app_open" ? "app_opened" : rawEventName;
  const localeFamily = stringValue(
    input.localeFamily,
    "locale_family_invalid",
  );
  const connectivity = stringValue(
    input.connectivity,
    "connectivity_invalid",
  );
  const outcome = stringValue(input.outcome, "outcome_invalid");

  if (!productEventNames.has(eventName as ProductTelemetryEventName)) {
    invalid("product_event_invalid");
  }
  if (!["fa", "en", "other"].includes(localeFamily)) {
    invalid("locale_family_invalid");
  }
  if (!["online", "offline", "recovering", "unknown"].includes(connectivity)) {
    invalid("connectivity_invalid");
  }
  if (
    ![
      "success",
      "failure",
      "cancelled",
      "queued",
      "replayed",
      "not_applicable",
    ].includes(outcome)
  ) {
    invalid("outcome_invalid");
  }

  return {
    kind: "product",
    eventId,
    application,
    releaseVersion,
    platform,
    eventName: eventName as ProductTelemetryEventName,
    localeFamily: localeFamily as ProductTelemetry["localeFamily"],
    connectivity: connectivity as ProductTelemetry["connectivity"],
    outcome: outcome as ProductTelemetry["outcome"],
  };
}

function rejectUnknownFields(
  input: Record<string, unknown>,
  allowed: Set<string>,
  code: string,
): void {
  for (const key of Object.keys(input)) {
    if (!allowed.has(key)) invalid(code);
  }
}

function validEventId(value: unknown): string {
  const eventId = stringValue(value, "event_id_invalid");
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(eventId)
  ) {
    invalid("event_id_invalid");
  }
  return eventId;
}

function validApplication(value: unknown): ClientErrorTelemetry["application"] {
  const application = stringValue(value, "application_invalid");
  if (application !== "wellmate" && application !== "caremate") {
    invalid("application_invalid");
  }
  return application;
}

function validReleaseVersion(value: unknown): string {
  const releaseVersion = stringValue(value, "release_version_invalid");
  if (!/^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$/.test(releaseVersion)) {
    invalid("release_version_invalid");
  }
  return releaseVersion;
}

function validPlatform(value: unknown): ClientErrorTelemetry["platform"] {
  const platform = stringValue(value, "platform_invalid");
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
  return platform as ClientErrorTelemetry["platform"];
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
