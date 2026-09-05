import { ApiError } from "./validation.ts";

export const periodObservationSchemaVersion = 1;

export const periodFlowValues = ["light", "medium", "heavy"] as const;
export const bloodAppearanceValues = [
  "bright_red",
  "red",
  "dark_red",
  "brown",
] as const;
export const bloodTextureValues = [
  "usual",
  "watery",
  "thick",
  "clot_observed",
] as const;

type PeriodFlow = typeof periodFlowValues[number];
type BloodAppearance = typeof bloodAppearanceValues[number];
type BloodTexture = typeof bloodTextureValues[number];

export type PeriodObservationPatch = {
  periodFlow: PeriodFlow | null;
  bloodAppearance: BloodAppearance | null;
  bloodTexture: BloodTexture | null;
  schemaVersion: number;
};

export function normalizePeriodObservation(
  body: Record<string, unknown>,
): PeriodObservationPatch {
  return {
    periodFlow: optionalCanonical(
      body.periodFlow,
      periodFlowValues,
      "periodFlow",
    ),
    bloodAppearance: optionalCanonical(
      body.bloodAppearance,
      bloodAppearanceValues,
      "bloodAppearance",
    ),
    bloodTexture: optionalCanonical(
      body.bloodTexture,
      bloodTextureValues,
      "bloodTexture",
    ),
    schemaVersion: periodObservationSchemaVersion,
  };
}

export function mapStoredPeriodObservation(row: Record<string, unknown>) {
  return {
    periodFlow: storedCanonical(row.period_flow, periodFlowValues),
    bloodAppearance: storedCanonical(
      row.blood_appearance,
      bloodAppearanceValues,
    ),
    bloodTexture: storedCanonical(row.blood_texture, bloodTextureValues),
    schemaVersion: Number(row.period_observation_schema_version ?? 1),
  };
}

function optionalCanonical<T extends string>(
  value: unknown,
  allowed: readonly T[],
  field: string,
): T | null {
  if (value == null || String(value).trim() === "") return null;
  const normalized = String(value).trim().toLowerCase().replaceAll("-", "_");
  if (!allowed.includes(normalized as T)) {
    throw new ApiError(
      400,
      "invalid_women_period_observation",
      `${field} contains an unsupported observation value.`,
    );
  }
  return normalized as T;
}

function storedCanonical<T extends string>(
  value: unknown,
  allowed: readonly T[],
): T | null {
  if (value == null) return null;
  const normalized = String(value).trim().toLowerCase();
  return allowed.includes(normalized as T) ? normalized as T : null;
}
