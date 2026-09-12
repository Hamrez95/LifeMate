import { ApiError } from "./validation.ts";

export const supportedCommandCenterLocales = ["fa-IR", "en-US"] as const;

export type ConfigureCommandCenterPreferencesPayload = {
  locale: string;
  timeZone: string;
  displayName: string;
  expectedVersion: number;
  reason: string;
};

async function requestObject(
  request: Request,
): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("invalid");
    }
    return value as Record<string, unknown>;
  } catch {
    throw new ApiError(
      400,
      "settings_request_invalid",
      "Request body must be a valid JSON object.",
    );
  }
}

function requireExactKeys(body: Record<string, unknown>): void {
  const allowed = new Set([
    "locale",
    "timeZone",
    "displayName",
    "expectedVersion",
    "reason",
  ]);
  const unsupported = Object.keys(body).filter((key) => !allowed.has(key));
  if (unsupported.length > 0) {
    throw new ApiError(
      400,
      "settings_field_unsupported",
      "One or more settings fields are not mutable.",
    );
  }
}

function locale(value: unknown): string {
  if (
    typeof value !== "string" ||
    !supportedCommandCenterLocales.includes(
      value as (typeof supportedCommandCenterLocales)[number],
    )
  ) {
    throw new ApiError(
      400,
      "settings_locale_invalid",
      "Locale is not supported by Command Center.",
    );
  }
  return value;
}

function timeZone(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "settings_timezone_invalid",
      "Time zone is invalid.",
    );
  }
  const normalized = value.trim();
  if (
    normalized.length < 1 || normalized.length > 64 ||
    !/^[A-Za-z_+\-/]+$/.test(normalized)
  ) {
    throw new ApiError(
      400,
      "settings_timezone_invalid",
      "Time zone is invalid.",
    );
  }
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: normalized }).format(0);
  } catch {
    throw new ApiError(
      400,
      "settings_timezone_invalid",
      "Time zone must be a supported IANA time zone.",
    );
  }
  return normalized;
}

function displayName(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "settings_display_name_invalid",
      "Display name is invalid.",
    );
  }
  const normalized = value.trim();
  if (normalized.length < 1 || normalized.length > 120) {
    throw new ApiError(
      400,
      "settings_display_name_invalid",
      "Display name is invalid.",
    );
  }
  return normalized;
}

function expectedVersion(value: unknown): number {
  if (
    !Number.isInteger(value) || Number(value) < 1 ||
    Number(value) > 1_000_000_000
  ) {
    throw new ApiError(
      400,
      "settings_version_invalid",
      "Settings version is invalid.",
    );
  }
  return Number(value);
}

function reason(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "settings_reason_invalid",
      "A meaningful reason is required.",
    );
  }
  const normalized = value.trim();
  if (normalized.length < 10 || normalized.length > 1000) {
    throw new ApiError(
      400,
      "settings_reason_invalid",
      "A meaningful reason is required.",
    );
  }
  return normalized;
}

export async function parseConfigureCommandCenterPreferencesPayload(
  request: Request,
): Promise<ConfigureCommandCenterPreferencesPayload> {
  const body = await requestObject(request);
  requireExactKeys(body);
  return {
    locale: locale(body.locale),
    timeZone: timeZone(body.timeZone),
    displayName: displayName(body.displayName),
    expectedVersion: expectedVersion(body.expectedVersion),
    reason: reason(body.reason),
  };
}

export async function hashConfigureCommandCenterPreferencesRequest(
  payload: ConfigureCommandCenterPreferencesPayload,
): Promise<string> {
  const canonical = [
    "v1",
    "settings.preferences.configure",
    payload.locale,
    payload.timeZone,
    payload.displayName,
    payload.expectedVersion,
    payload.reason,
  ].join("\n");
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return [...new Uint8Array(digest)].map((value) =>
    value.toString(16).padStart(2, "0")
  ).join("");
}
