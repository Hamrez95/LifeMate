import { ApiError } from "./validation.ts";

export type CanonicalHealthMeasurementType =
  | "sleep_duration"
  | "resting_heart_rate"
  | "heart_rate"
  | "heart_rate_variability"
  | "body_temperature";

export type WearableMeasurementInput = {
  platform: "android_health_connect" | "ios_healthkit";
  provider: string;
  externalId: string;
  measurementType: CanonicalHealthMeasurementType;
  value: number;
  unit: string;
  measuredAtUtc: string;
  confidence?: "unknown" | "low" | "medium" | "high";
};

export type CanonicalHealthObservationDraft = {
  observationType: string;
  valuePrimary: number;
  unitPrimary: string;
  observedAtUtc: string;
  sourceCategory: "Measured";
  sourceProvider: string;
  sourceExternalId: string;
  metadata: {
    platform: "android_health_connect" | "ios_healthkit";
    provenanceKind: "measured";
    confidence: "unknown" | "low" | "medium" | "high";
  };
  idempotencyKey: string;
};

export function normalizeWearableMeasurement(
  input: WearableMeasurementInput,
): CanonicalHealthObservationDraft {
  const provider = input.provider.trim().toLowerCase();
  const externalId = input.externalId.trim();
  if (provider.length < 1 || provider.length > 64) throw invalidMeasurement();
  if (externalId.length < 1 || externalId.length > 160) {
    throw invalidMeasurement();
  }
  if (!Number.isFinite(input.value)) throw invalidMeasurement();
  const observed = new Date(input.measuredAtUtc);
  if (!Number.isFinite(observed.getTime())) throw invalidMeasurement();

  const canonical = canonicalUnit(
    input.measurementType,
    input.value,
    input.unit,
  );
  return {
    observationType: observationType(input.measurementType),
    valuePrimary: canonical.value,
    unitPrimary: canonical.unit,
    observedAtUtc: observed.toISOString(),
    sourceCategory: "Measured",
    sourceProvider: provider,
    sourceExternalId: externalId,
    metadata: {
      platform: input.platform,
      provenanceKind: "measured",
      confidence: input.confidence ?? "unknown",
    },
    idempotencyKey: `${input.platform}:${provider}:${externalId}`,
  };
}

export function wearableCollectionAllowed(connection: {
  connectionStatus: string;
  permissionState: string;
  enabledMeasurements: unknown;
}, measurementType: CanonicalHealthMeasurementType): boolean {
  if (connection.connectionStatus !== "connected") return false;
  if (connection.permissionState !== "granted") return false;
  if (!Array.isArray(connection.enabledMeasurements)) return false;
  return connection.enabledMeasurements.includes(measurementType);
}

export function wearableDerivedOutputAllowed(connection: {
  connectionStatus: string;
  permissionState: string;
}): boolean {
  return connection.connectionStatus === "connected" &&
    connection.permissionState === "granted";
}

function observationType(type: CanonicalHealthMeasurementType): string {
  return ({
    sleep_duration: "SleepDuration",
    resting_heart_rate: "RestingHeartRate",
    heart_rate: "HeartRate",
    heart_rate_variability: "HeartRateVariability",
    body_temperature: "BodyTemperature",
  } as const)[type];
}

function canonicalUnit(
  type: CanonicalHealthMeasurementType,
  value: number,
  unitValue: string,
): { value: number; unit: string } {
  const unit = unitValue.trim().toLowerCase();
  if (type === "sleep_duration") {
    if (unit === "min" || unit === "minute" || unit === "minutes") {
      return { value: round(value), unit: "min" };
    }
    if (unit === "h" || unit === "hr" || unit === "hour" || unit === "hours") {
      return { value: round(value * 60), unit: "min" };
    }
  }
  if (type === "heart_rate" || type === "resting_heart_rate") {
    if (unit === "bpm") return { value: round(value), unit: "bpm" };
  }
  if (type === "heart_rate_variability") {
    if (unit === "ms") return { value: round(value), unit: "ms" };
  }
  if (type === "body_temperature") {
    if (unit === "c" || unit === "°c" || unit === "celsius") {
      return { value: round(value), unit: "Cel" };
    }
    if (unit === "f" || unit === "°f" || unit === "fahrenheit") {
      return { value: round((value - 32) * 5 / 9), unit: "Cel" };
    }
  }
  throw invalidMeasurement();
}

function round(value: number): number {
  return Math.round(value * 1000) / 1000;
}

function invalidMeasurement(): ApiError {
  return new ApiError(
    400,
    "invalid_wearable_health_measurement",
    "Unsupported or malformed wearable health measurement.",
  );
}
