import type { ResearchDatasetKind } from "./research_dataset_service.ts";
import { ApiError } from "./validation.ts";

type JsonObject = Record<string, unknown>;

const FILTER_KEYS: Record<ResearchDatasetKind, Set<string>> = {
  HealthObservationAggregate: new Set([
    "observationTypes",
    "observedFrom",
    "observedTo",
    "ageMin",
    "ageMax",
    "homeRegions",
  ]),
  DoseAdherenceAggregate: new Set([
    "statuses",
    "scheduledFrom",
    "scheduledTo",
    "ageMin",
    "ageMax",
    "homeRegions",
  ]),
  TreatmentAggregate: new Set([
    "statuses",
    "startedFrom",
    "startedTo",
    "ageMin",
    "ageMax",
    "homeRegions",
  ]),
  WomenCycleAggregate: new Set([
    "loggedFrom",
    "loggedTo",
    "moods",
    "energyMin",
    "energyMax",
    "painMin",
    "painMax",
    "ageMin",
    "ageMax",
    "homeRegions",
  ]),
};

export function parseResearchDatasetFilters(
  kind: ResearchDatasetKind,
  raw: JsonObject,
): JsonObject {
  const allowed = FILTER_KEYS[kind];
  for (const key of Object.keys(raw)) {
    if (!allowed.has(key)) {
      throw new ApiError(
        400,
        "research_filter_field_unsupported",
        `Filter field is not supported for ${kind}.`,
      );
    }
  }

  const result: JsonObject = {};
  for (const [key, value] of Object.entries(raw)) {
    if (key.endsWith("From") || key.endsWith("To")) {
      result[key] = dateOnly(value, key);
    } else if (key.endsWith("Min") || key.endsWith("Max")) {
      result[key] = boundedInteger(value, key);
    } else {
      result[key] = stringSet(value, key);
    }
  }
  validateRanges(result);
  return result;
}

function dateOnly(value: unknown, field: string): string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new ApiError(
      400,
      "research_filter_value_invalid",
      `${field} must be an ISO date.`,
    );
  }
  const [yearText, monthText, dayText] = value.split("-");
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    !Number.isFinite(date.getTime()) ||
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new ApiError(
      400,
      "research_filter_value_invalid",
      `${field} must be an ISO date.`,
    );
  }
  return value;
}

function boundedInteger(value: unknown, field: string): number {
  if (!Number.isInteger(value)) {
    throw new ApiError(
      400,
      "research_filter_value_invalid",
      `${field} must be an integer.`,
    );
  }
  const number = Number(value);
  if (field.startsWith("age") && (number < 0 || number > 130)) {
    throw new ApiError(
      400,
      "research_filter_value_invalid",
      `${field} is outside the supported age range.`,
    );
  }
  if (
    (field.startsWith("energy") || field.startsWith("pain")) &&
    (number < 0 || number > 10)
  ) {
    throw new ApiError(
      400,
      "research_filter_value_invalid",
      `${field} is outside the supported scale.`,
    );
  }
  return number;
}

function stringSet(value: unknown, field: string): string[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 50) {
    throw new ApiError(
      400,
      "research_filter_value_invalid",
      `${field} must contain 1 to 50 values.`,
    );
  }
  const normalized = value.map((item) => {
    if (typeof item !== "string") {
      throw new ApiError(
        400,
        "research_filter_value_invalid",
        `${field} values must be text.`,
      );
    }
    const text = item.trim();
    if (!text || text.length > 80 || /[\u0000-\u001f]/.test(text)) {
      throw new ApiError(
        400,
        "research_filter_value_invalid",
        `${field} contains an invalid value.`,
      );
    }
    return text;
  });
  return Array.from(new Set(normalized)).sort();
}

function validateRanges(filters: JsonObject) {
  const pairs = [
    ["ageMin", "ageMax"],
    ["energyMin", "energyMax"],
    ["painMin", "painMax"],
  ] as const;
  for (const [minimum, maximum] of pairs) {
    const min = filters[minimum];
    const max = filters[maximum];
    if (typeof min === "number" && typeof max === "number" && min > max) {
      throw new ApiError(
        400,
        "research_filter_range_invalid",
        `${minimum} cannot exceed ${maximum}.`,
      );
    }
  }

  const datePairs = [
    ["observedFrom", "observedTo"],
    ["scheduledFrom", "scheduledTo"],
    ["startedFrom", "startedTo"],
    ["loggedFrom", "loggedTo"],
  ] as const;
  for (const [fromKey, toKey] of datePairs) {
    const from = filters[fromKey];
    const to = filters[toKey];
    if (typeof from === "string" && typeof to === "string" && from > to) {
      throw new ApiError(
        400,
        "research_filter_range_invalid",
        `${fromKey} cannot be after ${toKey}.`,
      );
    }
  }
}
