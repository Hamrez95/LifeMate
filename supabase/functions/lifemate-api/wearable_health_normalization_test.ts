import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  normalizeWearableMeasurement,
  wearableCollectionAllowed,
  wearableDerivedOutputAllowed,
} from "./wearable_health_normalization.ts";

Deno.test("Health Connect measurement normalizes with measured provenance", () => {
  assertEquals(
    normalizeWearableMeasurement({
      platform: "android_health_connect",
      provider: "Samsung Health",
      externalId: "sample-123",
      measurementType: "resting_heart_rate",
      value: 62,
      unit: "bpm",
      measuredAtUtc: "2026-08-30T08:00:00Z",
      confidence: "high",
    }),
    {
      observationType: "RestingHeartRate",
      valuePrimary: 62,
      unitPrimary: "bpm",
      observedAtUtc: "2026-08-30T08:00:00.000Z",
      sourceCategory: "Measured",
      sourceProvider: "samsung health",
      sourceExternalId: "sample-123",
      metadata: {
        platform: "android_health_connect",
        provenanceKind: "measured",
        confidence: "high",
      },
      idempotencyKey: "android_health_connect:samsung health:sample-123",
    },
  );
});

Deno.test("units normalize without vendor-specific schema", () => {
  assertEquals(
    normalizeWearableMeasurement({
      platform: "ios_healthkit",
      provider: "healthkit",
      externalId: "sleep-1",
      measurementType: "sleep_duration",
      value: 7.5,
      unit: "hours",
      measuredAtUtc: "2026-08-30T05:00:00Z",
    }).valuePrimary,
    450,
  );
  assertEquals(
    normalizeWearableMeasurement({
      platform: "ios_healthkit",
      provider: "healthkit",
      externalId: "temp-1",
      measurementType: "body_temperature",
      value: 98.6,
      unit: "fahrenheit",
      measuredAtUtc: "2026-08-30T05:00:00Z",
    }).unitPrimary,
    "Cel",
  );
});

Deno.test("malformed or unsupported units fail closed", () => {
  assertThrows(() =>
    normalizeWearableMeasurement({
      platform: "android_health_connect",
      provider: "health-connect",
      externalId: "bad-1",
      measurementType: "heart_rate_variability",
      value: 40,
      unit: "bpm",
      measuredAtUtc: "2026-08-30T08:00:00Z",
    })
  );
});

Deno.test("collection requires connected, granted and exact measurement permission", () => {
  const base = {
    connectionStatus: "connected",
    permissionState: "granted",
    enabledMeasurements: ["sleep_duration", "resting_heart_rate"],
  };
  assertEquals(wearableCollectionAllowed(base, "sleep_duration"), true);
  assertEquals(wearableCollectionAllowed(base, "body_temperature"), false);
  assertEquals(
    wearableCollectionAllowed(
      { ...base, permissionState: "revoked" },
      "sleep_duration",
    ),
    false,
  );
  assertEquals(
    wearableCollectionAllowed(
      { ...base, connectionStatus: "disconnected" },
      "sleep_duration",
    ),
    false,
  );
});

Deno.test("revoke/disconnect stops future derived personalized output", () => {
  assertEquals(
    wearableDerivedOutputAllowed({
      connectionStatus: "connected",
      permissionState: "granted",
    }),
    true,
  );
  assertEquals(
    wearableDerivedOutputAllowed({
      connectionStatus: "connected",
      permissionState: "revoked",
    }),
    false,
  );
  assertEquals(
    wearableDerivedOutputAllowed({
      connectionStatus: "disconnected",
      permissionState: "granted",
    }),
    false,
  );
});
