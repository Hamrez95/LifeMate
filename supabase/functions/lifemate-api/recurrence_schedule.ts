import { ApiError } from "./validation.ts";

export type RecurrenceUnit = "hour" | "day" | "week" | "month" | "year";

export type RecurrenceRule = {
  version: number;
  enabled: true;
  unit: RecurrenceUnit;
  interval: number;
  weekdays: number[];
  endAt: string | null;
  maxOccurrences: number | null;
};

function integer(
  value: unknown,
  field: string,
  min: number,
  max: number,
): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} is outside the supported range.`,
    );
  }
  return parsed;
}

export function normalizeRecurrenceStartLocalTime(value: unknown): string {
  const match = /^(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(
    String(value ?? "").trim(),
  );
  if (!match) {
    throw new ApiError(
      400,
      "invalid_recurrenceStartLocalTime",
      "recurrenceStartLocalTime must be a local time.",
    );
  }
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  const second = Number(match[3] ?? "0");
  if (hour > 23 || minute > 59 || second > 59) {
    throw new ApiError(
      400,
      "invalid_recurrenceStartLocalTime",
      "recurrenceStartLocalTime must be a valid local time.",
    );
  }
  return `${match[1]}:${match[2]}`;
}

export function normalizeRecurrenceRule(value: unknown): RecurrenceRule | null {
  if (value == null) return null;
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "invalid_recurrence",
      "recurrence must be an object.",
    );
  }
  const record = value as Record<string, unknown>;
  if (record.enabled !== true) return null;
  const unit = String(record.unit ?? "").toLowerCase();
  if (!["hour", "day", "week", "month", "year"].includes(unit)) {
    throw new ApiError(
      400,
      "invalid_recurrence_unit",
      "Unsupported recurrence unit.",
    );
  }
  const weekdays = Array.isArray(record.weekdays)
    ? [
      ...new Set(
        record.weekdays.map((day) => integer(day, "recurrence_weekday", 1, 7)),
      ),
    ].sort()
    : [];
  if (unit !== "week" && weekdays.length > 0) {
    throw new ApiError(
      400,
      "invalid_recurrence_weekdays",
      "Weekdays are only valid for weekly recurrence.",
    );
  }
  const rawEnd = record.endAt ?? record.endDate;
  let endAt: string | null = null;
  if (rawEnd != null && String(rawEnd).trim() !== "") {
    const normalizedEnd = String(rawEnd).trim();
    const dateOnly = /^\d{4}-\d{2}-\d{2}$/.test(normalizedEnd);
    if (unit === "hour" && dateOnly) {
      throw new ApiError(
        400,
        "invalid_recurrence_end",
        "Hourly recurrence requires an exact local end time.",
      );
    }
    const parsed = parseLocalTimestamp(
      dateOnly ? `${normalizedEnd}T23:59:59` : normalizedEnd,
    );
    endAt = formatLocalTimestamp(parsed);
  }
  return {
    version: integer(record.version ?? 2, "recurrence_version", 1, 1000),
    enabled: true,
    unit: unit as RecurrenceUnit,
    interval: integer(
      record.interval ?? 1,
      "recurrence_interval",
      1,
      unit === "hour" ? 8760 : 365,
    ),
    weekdays,
    endAt,
    maxOccurrences: record.maxOccurrences == null
      ? null
      : integer(record.maxOccurrences, "recurrence_max_occurrences", 1, 10000),
  };
}

/**
 * Expand recurrence in local wall-clock time. The returned strings deliberately
 * carry no UTC offset: PostgreSQL converts each local value with the plan's IANA
 * time zone, so DST rules come from the database time-zone catalogue.
 */
export function expandLocalRecurrence(
  startLocal: string,
  rule: RecurrenceRule,
  fromLocal: string,
  toLocal: string,
  maxReturned = 1000,
): string[] {
  const start = parseLocalTimestamp(startLocal);
  const from = parseLocalTimestamp(fromLocal);
  const requestedTo = parseLocalTimestamp(toLocal);
  const explicitEnd = rule.endAt == null
    ? null
    : parseLocalTimestamp(rule.endAt);
  const to = explicitEnd != null && explicitEnd < requestedTo
    ? explicitEnd
    : requestedTo;
  if (to < from || to < start) return [];

  const result: string[] = [];
  let emitted = 0;
  const limit = rule.maxOccurrences;
  const accept = (cursor: Date): boolean => {
    if (limit != null && emitted >= limit) return false;
    emitted += 1;
    if (cursor >= from && cursor <= to) {
      result.push(formatLocalTimestamp(cursor));
      if (result.length > maxReturned) {
        throw new ApiError(
          400,
          "recurrence_window_too_dense",
          "Recurrence produces too many occurrences in this window.",
        );
      }
    }
    return limit == null || emitted < limit;
  };

  if (rule.unit === "hour" || rule.unit === "day") {
    const milliseconds = rule.interval *
      (rule.unit === "hour" ? 3600000 : 86400000);
    for (
      let cursor = start, guard = 0;
      cursor <= to && guard < 100000;
      guard++
    ) {
      if (!accept(cursor)) break;
      cursor = new Date(cursor.getTime() + milliseconds);
    }
  } else if (rule.unit === "week") {
    const allowed = new Set(
      rule.weekdays.length > 0 ? rule.weekdays : [isoWeekday(start)],
    );
    for (
      let cursor = start, guard = 0;
      cursor <= to && guard < 100000;
      guard++
    ) {
      const dayDistance = calendarDayDistance(start, cursor);
      const weekIndex = Math.floor(dayDistance / 7);
      if (weekIndex % rule.interval === 0 && allowed.has(isoWeekday(cursor))) {
        if (!accept(cursor)) break;
      }
      cursor = addDaysPreservingClock(cursor, 1);
    }
  } else {
    const monthFactor = rule.unit === "year" ? 12 : 1;
    const max = rule.unit === "year" ? 10000 : 24000;
    for (let occurrence = 0; occurrence < max; occurrence++) {
      const cursor = addMonthsClamped(
        start,
        occurrence * rule.interval * monthFactor,
      );
      if (cursor > to) break;
      if (!accept(cursor)) break;
    }
  }
  return result;
}

export function parseLocalTimestamp(value: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?$/
    .exec(value.trim());
  if (!match) {
    throw new ApiError(
      400,
      "invalid_local_timestamp",
      "Invalid local date/time.",
    );
  }
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4] ?? 0);
  const minute = Number(match[5] ?? 0);
  const second = Number(match[6] ?? 0);
  const date = new Date(Date.UTC(year, month - 1, day, hour, minute, second));
  if (
    date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day || date.getUTCHours() !== hour ||
    date.getUTCMinutes() !== minute || date.getUTCSeconds() !== second
  ) {
    throw new ApiError(
      400,
      "invalid_local_timestamp",
      "Invalid local date/time.",
    );
  }
  return date;
}

export function formatLocalTimestamp(value: Date): string {
  const y = value.getUTCFullYear().toString().padStart(4, "0");
  const m = (value.getUTCMonth() + 1).toString().padStart(2, "0");
  const d = value.getUTCDate().toString().padStart(2, "0");
  const h = value.getUTCHours().toString().padStart(2, "0");
  const min = value.getUTCMinutes().toString().padStart(2, "0");
  const s = value.getUTCSeconds().toString().padStart(2, "0");
  return `${y}-${m}-${d}T${h}:${min}:${s}`;
}

function addDaysPreservingClock(value: Date, days: number): Date {
  return new Date(Date.UTC(
    value.getUTCFullYear(),
    value.getUTCMonth(),
    value.getUTCDate() + days,
    value.getUTCHours(),
    value.getUTCMinutes(),
    value.getUTCSeconds(),
  ));
}

function addMonthsClamped(value: Date, months: number): Date {
  const first = new Date(
    Date.UTC(value.getUTCFullYear(), value.getUTCMonth() + months, 1),
  );
  const lastDay = new Date(
    Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0),
  ).getUTCDate();
  return new Date(Date.UTC(
    first.getUTCFullYear(),
    first.getUTCMonth(),
    Math.min(value.getUTCDate(), lastDay),
    value.getUTCHours(),
    value.getUTCMinutes(),
    value.getUTCSeconds(),
  ));
}

function calendarDayDistance(start: Date, cursor: Date): number {
  const left = Date.UTC(
    start.getUTCFullYear(),
    start.getUTCMonth(),
    start.getUTCDate(),
  );
  const right = Date.UTC(
    cursor.getUTCFullYear(),
    cursor.getUTCMonth(),
    cursor.getUTCDate(),
  );
  return Math.floor((right - left) / 86400000);
}

function isoWeekday(value: Date): number {
  const day = value.getUTCDay();
  return day === 0 ? 7 : day;
}
