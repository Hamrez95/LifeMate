export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export async function readJsonObject(
  request: Request,
  maxBytes = 32 * 1024,
): Promise<Record<string, unknown>> {
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    throw new ApiError(413, "request_too_large", "Request body is too large.");
  }

  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > maxBytes) {
    throw new ApiError(413, "request_too_large", "Request body is too large.");
  }

  try {
    const value = JSON.parse(text);
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("not an object");
    }
    return value as Record<string, unknown>;
  } catch {
    throw new ApiError(400, "invalid_json", "Request body must be valid JSON.");
  }
}

export function normalizeOptional(value: unknown): string | null {
  if (value == null) return null;
  const normalized = String(value).trim();
  return normalized.length === 0 ? null : normalized;
}

export function requiredText(
  value: unknown,
  field: string,
  max: number,
): string {
  const normalized = normalizeOptional(value);
  if (!normalized || normalized.length > max) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} is required and must be at most ${max} characters.`,
    );
  }
  return normalized;
}

export function limitedOptional(
  value: unknown,
  field: string,
  max: number,
): string | null {
  const normalized = normalizeOptional(value);
  if (normalized && normalized.length > max) {
    throw new ApiError(400, `invalid_${field}`, `${field} is too long.`);
  }
  return normalized;
}

export function requiredUuid(value: unknown, field: string): string {
  const normalized = String(value ?? "");
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(normalized)
  ) {
    throw new ApiError(400, `invalid_${field}`, `${field} must be a UUID.`);
  }
  return normalized;
}

export function requiredPositiveInt(value: unknown, field: string): number {
  if (!Number.isInteger(value) || Number(value) < 1) {
    throw new ApiError(400, `invalid_${field}`, `${field} must be positive.`);
  }
  return Number(value);
}

export function requiredDate(value: unknown, field: string): string {
  const normalized = String(value ?? "");
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(normalized);
  if (!match) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} must be an ISO date.`,
    );
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} must be a valid date.`,
    );
  }
  return normalized;
}

export function requiredTimestamp(value: unknown, field: string): Date {
  const date = new Date(String(value ?? ""));
  if (Number.isNaN(date.getTime())) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} must be an ISO timestamp.`,
    );
  }
  return date;
}

export function validateReportedAt(
  value: Date,
  now = new Date(),
): void {
  const futureLimit = now.getTime() + 5 * 60 * 1000;
  const pastLimit = now.getTime() - 31 * 24 * 60 * 60 * 1000;
  if (value.getTime() > futureLimit || value.getTime() < pastLimit) {
    throw new ApiError(
      400,
      "invalid_occurredAtUtc",
      "Reported time must be within the last 31 days and not in the future.",
    );
  }
}

export function validateRange(fromDate: string, toDate: string): void {
  const from = Date.parse(`${fromDate}T00:00:00Z`);
  const to = Date.parse(`${toDate}T00:00:00Z`);
  const days = Math.round((to - from) / 86400000);
  if (days < 0 || days > 31) {
    throw new ApiError(
      400,
      "invalid_date_range",
      "Date range must be between 0 and 31 days.",
    );
  }
}

export function requiredTimeZone(value: unknown): string {
  const timeZone = requiredText(value, "timeZone", 64);
  try {
    new Intl.DateTimeFormat("en-US", { timeZone }).format(new Date());
  } catch {
    throw new ApiError(
      400,
      "invalid_timeZone",
      "timeZone must be a valid IANA time zone.",
    );
  }
  return timeZone;
}

export function normalizeSchedules(value: unknown): Array<{
  dayOfWeek: string;
  localTime: string;
}> {
  if (!Array.isArray(value) || value.length === 0 || value.length > 64) {
    throw new ApiError(
      400,
      "schedule_required",
      "At least one schedule is required.",
    );
  }

  const canonicalDays = new Map<string, string>([
    ["sunday", "Sunday"],
    ["monday", "Monday"],
    ["tuesday", "Tuesday"],
    ["wednesday", "Wednesday"],
    ["thursday", "Thursday"],
    ["friday", "Friday"],
    ["saturday", "Saturday"],
  ]);
  const unique = new Set<string>();

  return value.map((entry) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      throw new ApiError(400, "invalid_schedule", "Schedule is invalid.");
    }
    const record = entry as Record<string, unknown>;
    const day = canonicalDays.get(
      String(record.dayOfWeek ?? "").trim().toLowerCase(),
    );
    const match = /^(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(
      String(record.localTime ?? "").trim(),
    );
    if (!day || !match) {
      throw new ApiError(
        400,
        "invalid_schedule",
        "Schedule day or time is invalid.",
      );
    }
    const hour = Number(match[1]);
    const minute = Number(match[2]);
    const second = Number(match[3] ?? "0");
    if (hour > 23 || minute > 59 || second > 59) {
      throw new ApiError(
        400,
        "invalid_schedule",
        "Schedule day or time is invalid.",
      );
    }
    const localTime = `${match[1]}:${match[2]}`;
    const key = `${day}:${localTime}`;
    if (unique.has(key)) {
      throw new ApiError(400, "duplicate_schedule", "Schedule is duplicated.");
    }
    unique.add(key);
    return { dayOfWeek: day, localTime };
  });
}

export function normalizeDoseStatus(value: unknown): "Taken" | "Skipped" {
  const status = String(value ?? "").toLowerCase();
  if (status === "taken") return "Taken";
  if (status === "skipped") return "Skipped";
  throw new ApiError(
    400,
    "invalid_dose_status",
    "Status must be taken or skipped.",
  );
}

export function normalizePath(pathname: string): string {
  // Supabase may expose the same reviewed source under the production slug or
  // the isolated candidate slug. Strip only a leading function prefix so a
  // nested value containing "lifemate-api" is never altered accidentally.
  const value = pathname.replace(
    /^\/(?:functions\/v1\/)?lifemate-api(?:-candidate)?(?=\/|$)/,
    "",
  );
  const normalized = value.startsWith("/") ? value : `/${value}`;
  return normalized.length > 1 && normalized.endsWith("/")
    ? normalized.substring(0, normalized.length - 1)
    : normalized;
}
