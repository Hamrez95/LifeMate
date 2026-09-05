import { ApiError } from "./validation.ts";

export const womenSymptomCatalogVersion = 1;

export const womenSymptomIds = [
  "cramps",
  "headache",
  "migraine",
  "lower_back_pain",
  "bloating",
  "fatigue",
  "nausea",
  "breast_tenderness",
  "mood_changes",
  "sleep_changes",
  "appetite_changes",
  "no_symptom",
  "other",
] as const;

export type WomenSymptomId = typeof womenSymptomIds[number];
export type WomenSymptomSeverity = 1 | 2 | 3 | 4 | 5;

export type WomenSymptomObservation = {
  id: WomenSymptomId;
  severity: WomenSymptomSeverity | null;
};

const legacyToCanonical: Record<string, WomenSymptomId> = {
  Cramps: "cramps",
  Headache: "headache",
  Bloating: "bloating",
  Fatigue: "fatigue",
  BreastTenderness: "breast_tenderness",
  BackPain: "lower_back_pain",
  SleepChange: "sleep_changes",
  AppetiteChange: "appetite_changes",
  NoSymptom: "no_symptom",
};

const canonicalToLegacy = new Map<WomenSymptomId, string>(
  Object.entries(legacyToCanonical).map(([legacy, canonical]) => [
    canonical,
    legacy,
  ]),
);

const canonicalSet = new Set<string>(womenSymptomIds);

export function canonicalizeLegacySymptoms(value: unknown): WomenSymptomId[] {
  if (!Array.isArray(value)) return [];
  const result = new Set<WomenSymptomId>();
  for (const raw of value) {
    const text = String(raw ?? "").trim();
    if (!text) continue;
    const direct = text.toLowerCase().replaceAll("-", "_");
    const mapped = canonicalSet.has(direct)
      ? direct as WomenSymptomId
      : legacyToCanonical[text];
    if (mapped) result.add(mapped);
  }
  if (result.has("no_symptom") && result.size > 1) result.delete("no_symptom");
  return [...result];
}

/**
 * Projects canonical symptom ids into the historical `symptoms` column.
 *
 * That column has an intentionally narrow database check constraint using the
 * original PascalCase values. Canonical-only symptoms stay in the structured
 * `symptom_observations` JSON and are omitted here instead of weakening the
 * legacy constraint or losing structured data.
 */
export function projectCanonicalSymptomsToLegacyStorage(
  symptoms: readonly WomenSymptomId[],
): string[] {
  const result: string[] = [];
  for (const symptom of symptoms) {
    const legacy = canonicalToLegacy.get(symptom);
    if (legacy != null) result.push(legacy);
  }
  return result;
}

export function normalizeWomenSymptomObservations(
  value: unknown,
): WomenSymptomObservation[] {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > 16) {
    throw invalidSymptoms();
  }

  const byId = new Map<WomenSymptomId, WomenSymptomObservation>();
  for (const raw of value) {
    if (raw == null || typeof raw !== "object" || Array.isArray(raw)) {
      throw invalidSymptoms();
    }
    const row = raw as Record<string, unknown>;
    const idText = String(row.id ?? "").trim().toLowerCase().replaceAll(
      "-",
      "_",
    );
    if (!canonicalSet.has(idText)) throw invalidSymptoms();
    const id = idText as WomenSymptomId;
    const severity = normalizeSeverity(row.severity);
    byId.set(id, { id, severity });
  }

  if (byId.has("no_symptom") && byId.size > 1) {
    throw new ApiError(
      400,
      "invalid_women_calendar_symptoms",
      "no_symptom cannot be combined with other symptom observations.",
    );
  }
  return [...byId.values()];
}

export function mergeLegacySymptomsIntoObservations(
  legacySymptoms: unknown,
  structuredValue: unknown,
): WomenSymptomObservation[] {
  const structured = normalizeStoredWomenSymptomObservations(structuredValue);
  if (structured.length > 0) return structured;
  return canonicalizeLegacySymptoms(legacySymptoms).map((id) => ({
    id,
    severity: null,
  }));
}

export function normalizeStoredWomenSymptomObservations(
  value: unknown,
): WomenSymptomObservation[] {
  if (!Array.isArray(value)) return [];
  const result: WomenSymptomObservation[] = [];
  for (const raw of value) {
    if (raw == null || typeof raw !== "object" || Array.isArray(raw)) continue;
    const row = raw as Record<string, unknown>;
    const idText = String(row.id ?? "").trim().toLowerCase().replaceAll(
      "-",
      "_",
    );
    if (!canonicalSet.has(idText)) continue;
    const severityNumber = Number(row.severity);
    const severity = Number.isInteger(severityNumber) && severityNumber >= 1 &&
        severityNumber <= 5
      ? severityNumber as WomenSymptomSeverity
      : null;
    result.push({ id: idText as WomenSymptomId, severity });
  }
  if (result.some((row) => row.id === "no_symptom") && result.length > 1) {
    return result.filter((row) => row.id !== "no_symptom");
  }
  return result;
}

function normalizeSeverity(value: unknown): WomenSymptomSeverity | null {
  if (value == null || value === "") return null;
  const number = Number(value);
  if (!Number.isInteger(number) || number < 1 || number > 5) {
    throw invalidSymptoms();
  }
  return number as WomenSymptomSeverity;
}

function invalidSymptoms(): ApiError {
  return new ApiError(
    400,
    "invalid_women_calendar_symptoms",
    "Unsupported Women Health symptom observation payload.",
  );
}
