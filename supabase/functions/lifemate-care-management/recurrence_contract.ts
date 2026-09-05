export type CareRecurrenceRule = {
  version: number;
  enabled: true;
  unit: "hour" | "day" | "week" | "month" | "year";
  interval: number;
  weekdays: number[];
  endAt: string | null;
  maxOccurrences: number | null;
};

type ErrorFactory = (status: number, code: string, message: string) => Error;

export function normalizeCareRecurrence(
  value: unknown,
  error: ErrorFactory,
): CareRecurrenceRule | null {
  if (value == null) return null;
  if (typeof value !== "object" || Array.isArray(value)) {
    throw error(400, "invalid_recurrence", "recurrence must be an object.");
  }
  const record = value as Record<string, unknown>;
  if (record.enabled !== true) return null;
  const unit = String(record.unit ?? "").trim().toLowerCase();
  if (!["hour", "day", "week", "month", "year"].includes(unit)) {
    throw error(400, "invalid_recurrence_unit", "Unsupported recurrence unit.");
  }
  const interval = integer(
    record.interval ?? 1,
    1,
    unit === "hour" ? 8760 : 365,
    "recurrence_interval",
    error,
  );
  const rawWeekdays = record.weekdays ?? [];
  if (!Array.isArray(rawWeekdays)) {
    throw error(
      400,
      "invalid_recurrence_weekdays",
      "weekdays must be an array.",
    );
  }
  const weekdays = [
    ...new Set(
      rawWeekdays.map((day) => integer(day, 1, 7, "recurrence_weekday", error)),
    ),
  ].sort((a, b) => a - b);
  if (unit !== "week" && weekdays.length > 0) {
    throw error(
      400,
      "invalid_recurrence_weekdays",
      "Weekdays are only valid for weekly recurrence.",
    );
  }

  const rawEnd = record.endAt ?? record.endDate;
  let endAt: string | null = null;
  if (rawEnd != null && String(rawEnd).trim() !== "") {
    const text = String(rawEnd).trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(text) && unit !== "hour") {
      validateLocalTimestamp(`${text}T23:59:59`, error);
      endAt = `${text}T23:59:59`;
    } else {
      validateLocalTimestamp(text, error);
      endAt = normalizeTimestamp(text);
    }
  }
  return {
    version: integer(record.version ?? 2, 1, 1000, "recurrence_version", error),
    enabled: true,
    unit: unit as CareRecurrenceRule["unit"],
    interval,
    weekdays,
    endAt,
    maxOccurrences: record.maxOccurrences == null ? null : integer(
      record.maxOccurrences,
      1,
      10000,
      "recurrence_max_occurrences",
      error,
    ),
  };
}

export function normalizeCareRecurrenceStartTime(
  value: unknown,
  error: ErrorFactory,
): string {
  const match = /^(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(
    String(value ?? "").trim(),
  );
  if (
    !match || Number(match[1]) > 23 || Number(match[2]) > 59 ||
    Number(match[3] ?? 0) > 59
  ) {
    throw error(
      400,
      "invalid_recurrenceStartLocalTime",
      "recurrenceStartLocalTime must use HH:mm.",
    );
  }
  return `${match[1]}:${match[2]}`;
}

export function recurrencePublicValue(
  rule: CareRecurrenceRule | null,
): Record<string, unknown> {
  if (rule == null) return { version: 2, enabled: false };
  return {
    version: rule.version,
    enabled: true,
    unit: rule.unit,
    interval: rule.interval,
    weekdays: rule.weekdays,
    endDate: rule.endAt == null
      ? null
      : rule.unit === "hour"
      ? rule.endAt
      : rule.endAt.slice(0, 10),
    maxOccurrences: rule.maxOccurrences,
  };
}

function integer(
  value: unknown,
  min: number,
  max: number,
  field: string,
  error: ErrorFactory,
): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) {
    throw error(
      400,
      `invalid_${field}`,
      `${field} is outside the supported range.`,
    );
  }
  return parsed;
}

function validateLocalTimestamp(value: string, error: ErrorFactory): void {
  const match = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?$/
    .exec(value);
  if (!match) {
    throw error(
      400,
      "invalid_recurrence_end",
      "Invalid recurrence end date/time.",
    );
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4] ?? 0);
  const minute = Number(match[5] ?? 0);
  const second = Number(match[6] ?? 0);
  if (hour > 23 || minute > 59 || second > 59) {
    throw error(
      400,
      "invalid_recurrence_end",
      "Invalid recurrence end date/time.",
    );
  }
  const date = new Date(Date.UTC(year, month - 1, day, hour, minute, second));
  if (
    date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day || date.getUTCHours() !== hour ||
    date.getUTCMinutes() !== minute || date.getUTCSeconds() !== second
  ) {
    throw error(
      400,
      "invalid_recurrence_end",
      "Invalid recurrence end date/time.",
    );
  }
}

function normalizeTimestamp(value: string): string {
  const [date, rawTime = "00:00:00"] = value.replace(" ", "T").split("T");
  const parts = rawTime.split(":");
  return `${date}T${parts[0]}:${parts[1] ?? "00"}:${parts[2] ?? "00"}`;
}
