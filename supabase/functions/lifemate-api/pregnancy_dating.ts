export type PregnancyDatingMethod =
  | "lmp"
  | "edd"
  | "clinician_ultrasound"
  | "manual_correction"
  | "imported";

export type PregnancyDatingInput = {
  method: PregnancyDatingMethod | null;
  lmpDate: string | null;
  estimatedDueDate: string | null;
  referenceDate: string | null;
  gestationalAgeAtReferenceDays: number | null;
};

export type GestationalAge = {
  totalDays: number;
  week: number;
  day: number;
  basis: "lmp" | "edd" | "reference";
};

const DAY_MS = 86_400_000;
const TERM_DAYS = 280;
const MAX_REFERENCE_GESTATIONAL_DAYS = 308;

export class PregnancyDatingError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PregnancyDatingError";
  }
}

function parseIsoDate(value: string, field: string): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new PregnancyDatingError(`${field}_invalid`);
  }
  const [year, month, day] = value.split("-").map(Number);
  const timestamp = Date.UTC(year, month - 1, day);
  const date = new Date(timestamp);
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new PregnancyDatingError(`${field}_invalid`);
  }
  return Math.floor(timestamp / DAY_MS);
}

function requireReferenceDays(value: number | null): number {
  if (
    value == null ||
    !Number.isInteger(value) ||
    value < 0 ||
    value > MAX_REFERENCE_GESTATIONAL_DAYS
  ) {
    throw new PregnancyDatingError("gestational_age_at_reference_invalid");
  }
  return value;
}

function deriveFromReference(
  input: PregnancyDatingInput,
  asOfOrdinal: number,
): GestationalAge | null {
  if (input.referenceDate == null) return null;
  const referenceOrdinal = parseIsoDate(input.referenceDate, "reference_date");
  const referenceDays = requireReferenceDays(
    input.gestationalAgeAtReferenceDays,
  );
  return normalizeGestationalDays(
    referenceDays + (asOfOrdinal - referenceOrdinal),
    "reference",
  );
}

function deriveFromEdd(
  input: PregnancyDatingInput,
  asOfOrdinal: number,
): GestationalAge | null {
  if (input.estimatedDueDate == null) return null;
  const eddOrdinal = parseIsoDate(input.estimatedDueDate, "estimated_due_date");
  return normalizeGestationalDays(
    TERM_DAYS - (eddOrdinal - asOfOrdinal),
    "edd",
  );
}

function deriveFromLmp(
  input: PregnancyDatingInput,
  asOfOrdinal: number,
): GestationalAge | null {
  if (input.lmpDate == null) return null;
  const lmpOrdinal = parseIsoDate(input.lmpDate, "lmp_date");
  return normalizeGestationalDays(asOfOrdinal - lmpOrdinal, "lmp");
}

function normalizeGestationalDays(
  totalDays: number,
  basis: GestationalAge["basis"],
): GestationalAge | null {
  if (totalDays < 0) return null;
  return {
    totalDays,
    week: Math.floor(totalDays / 7),
    day: totalDays % 7,
    basis,
  };
}

/// Derives gestational age from a *local calendar date* supplied by the caller.
/// The caller is responsible for resolving the user's IANA timezone and turning
/// the current instant into YYYY-MM-DD. This keeps timezone boundaries explicit
/// and makes the calculation deterministic on server and client fixtures.
///
/// Precedence is method-driven:
/// - lmp -> LMP date
/// - edd -> EDD (280-day term convention)
/// - clinician_ultrasound -> clinician reference date + GA-at-reference
/// - manual_correction/imported -> reference, then EDD, then LMP
///
/// Missing/partial dating is valid and returns null; no LMP/EDD is invented.
export function deriveGestationalAge(
  input: PregnancyDatingInput,
  asOfLocalDate: string,
): GestationalAge | null {
  const asOfOrdinal = parseIsoDate(asOfLocalDate, "as_of_date");
  if (input.method == null) return null;

  switch (input.method) {
    case "lmp":
      if (input.lmpDate == null) {
        throw new PregnancyDatingError("lmp_date_required");
      }
      return deriveFromLmp(input, asOfOrdinal);
    case "edd":
      if (input.estimatedDueDate == null) {
        throw new PregnancyDatingError("estimated_due_date_required");
      }
      return deriveFromEdd(input, asOfOrdinal);
    case "clinician_ultrasound":
      if (
        input.referenceDate == null ||
        input.gestationalAgeAtReferenceDays == null
      ) {
        throw new PregnancyDatingError("clinician_reference_required");
      }
      return deriveFromReference(input, asOfOrdinal);
    case "manual_correction":
    case "imported":
      return deriveFromReference(input, asOfOrdinal) ??
        deriveFromEdd(input, asOfOrdinal) ??
        deriveFromLmp(input, asOfOrdinal);
  }
}
