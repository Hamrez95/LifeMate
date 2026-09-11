import { createCocoonIdentityResolver } from "./cocoon_identity.ts";
import { json } from "./http.ts";
import { createPregnancyAuthorization } from "./pregnancy_authorization.ts";
import { createPregnancyCalendarRouteHandler } from "./pregnancy_calendar.ts";
import { createPregnancyCaptureRouteHandler } from "./pregnancy_capture.ts";
import { createPregnancyMeasurementRouteHandler } from "./pregnancy_measurements.ts";
import {
  createPregnancyStore,
  type PregnancyEpisode,
} from "./pregnancy_store.ts";
import { createPregnancyTreatmentRouteHandler } from "./pregnancy_treatments.ts";
import { ApiError, requiredDate, validateRange } from "./validation.ts";

type Row = Record<string, unknown>;

type RecordCategory =
  | "pregnancy"
  | "check_ins"
  | "symptoms"
  | "moods"
  | "measurements"
  | "appointments"
  | "medications";

export type PregnancyRecordItem = {
  id: string;
  sourceKind: string;
  sourceId: string;
  category: RecordCategory;
  occurredAtUtc: string;
  localDate: string;
  type: string;
  summary: Row;
  deepLink?: string;
  sourceVersion?: number;
};

const allCategories = new Set<RecordCategory>([
  "pregnancy",
  "check_ins",
  "symptoms",
  "moods",
  "measurements",
  "appointments",
  "medications",
]);

function asRows(value: unknown): Row[] {
  return Array.isArray(value)
    ? value.filter((item): item is Row =>
      item != null && typeof item === "object" && !Array.isArray(item)
    )
    : [];
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function recordTimestamp(row: Row): string {
  for (
    const key of [
      "observedAtUtc",
      "scheduledAtUtc",
      "startAtUtc",
      "startsAtUtc",
      "occurrenceStartAtUtc",
      "createdAtUtc",
      "updatedAtUtc",
    ]
  ) {
    const value = stringValue(row[key]);
    if (value) return new Date(value).toISOString();
  }
  for (
    const key of [
      "localDate",
      "scheduledLocalDate",
      "occurrenceLocalDate",
      "startDate",
    ]
  ) {
    const value = stringValue(row[key]);
    if (value) return `${value.slice(0, 10)}T00:00:00.000Z`;
  }
  return "1970-01-01T00:00:00.000Z";
}

function recordLocalDate(row: Row, timestamp: string): string {
  for (
    const key of [
      "localDate",
      "scheduledLocalDate",
      "occurrenceLocalDate",
      "startDate",
    ]
  ) {
    const value = stringValue(row[key]);
    if (value) return value.slice(0, 10);
  }
  return timestamp.slice(0, 10);
}

function sourceId(row: Row, ...keys: string[]): string | null {
  for (const key of keys) {
    const value = stringValue(row[key]);
    if (value) return value;
  }
  return null;
}

function version(row: Row): number | undefined {
  return typeof row.version === "number" ? row.version : undefined;
}

function item(
  row: Row,
  args: {
    sourceKind: string;
    sourceId: string;
    category: RecordCategory;
    type: string;
    summary: Row;
    deepLink?: string;
  },
): PregnancyRecordItem {
  const occurredAtUtc = recordTimestamp(row);
  return {
    id: `${args.sourceKind}:${args.sourceId}`,
    sourceKind: args.sourceKind,
    sourceId: args.sourceId,
    category: args.category,
    occurredAtUtc,
    localDate: recordLocalDate(row, occurredAtUtc),
    type: args.type,
    summary: args.summary,
    deepLink: args.deepLink,
    sourceVersion: version(row),
  };
}

function compareRecords(
  a: PregnancyRecordItem,
  b: PregnancyRecordItem,
): number {
  const timestamp = b.occurredAtUtc.localeCompare(a.occurredAtUtc);
  return timestamp !== 0 ? timestamp : b.id.localeCompare(a.id);
}

type Cursor = { occurredAtUtc: string; id: string };

export function encodePregnancyRecordsCursor(
  item: PregnancyRecordItem,
): string {
  return btoa(
    JSON.stringify({ occurredAtUtc: item.occurredAtUtc, id: item.id }),
  );
}

export function decodePregnancyRecordsCursor(
  value: string | null,
): Cursor | null {
  if (!value) return null;
  try {
    const decoded = JSON.parse(atob(value)) as Row;
    const occurredAtUtc = stringValue(decoded.occurredAtUtc);
    const id = stringValue(decoded.id);
    if (!occurredAtUtc || !id) return null;
    return { occurredAtUtc, id };
  } catch {
    return null;
  }
}

export function paginatePregnancyRecords(
  values: PregnancyRecordItem[],
  limit: number,
  cursor: Cursor | null,
): { items: PregnancyRecordItem[]; nextCursor: string | null } {
  const sorted = [...values].sort(compareRecords);
  const afterCursor = cursor == null
    ? sorted
    : sorted.filter((value) =>
      value.occurredAtUtc < cursor.occurredAtUtc ||
      (value.occurredAtUtc === cursor.occurredAtUtc && value.id < cursor.id)
    );
  const page = afterCursor.slice(0, limit);
  return {
    items: page,
    nextCursor: afterCursor.length > limit && page.length > 0
      ? encodePregnancyRecordsCursor(page[page.length - 1])
      : null,
  };
}

function requestedCategories(value: string | null): Set<RecordCategory> {
  if (!value || value.trim().length === 0) return new Set(allCategories);
  const result = new Set<RecordCategory>();
  for (const candidate of value.split(",")) {
    const normalized = candidate.trim().toLowerCase() as RecordCategory;
    if (!allCategories.has(normalized)) {
      throw new ApiError(
        400,
        "pregnancy_records_category_invalid",
        "Pregnancy records category is invalid.",
      );
    }
    result.add(normalized);
  }
  return result;
}

function boundedLimit(value: string | null): number {
  if (value == null || value.trim().length === 0) return 30;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 100) {
    throw new ApiError(
      400,
      "pregnancy_records_limit_invalid",
      "Pregnancy records limit must be between 1 and 100.",
    );
  }
  return parsed;
}

async function responseBody(
  response: Promise<Response | null>,
): Promise<Row | null> {
  try {
    const resolved = await response;
    if (!resolved) return null;
    const body = await resolved.json();
    return body != null && typeof body === "object" && !Array.isArray(body)
      ? body as Row
      : null;
  } catch (error) {
    if (error instanceof ApiError && error.status === 403) return null;
    throw error;
  }
}

function lifecycleItems(
  episode: PregnancyEpisode,
  categories: Set<RecordCategory>,
): PregnancyRecordItem[] {
  if (!categories.has("pregnancy")) return [];
  const values: PregnancyRecordItem[] = [];
  if (episode.activatedAtUtc) {
    values.push({
      id: `pregnancy_activation:${episode.id}`,
      sourceKind: "pregnancy_activation",
      sourceId: episode.id,
      category: "pregnancy",
      occurredAtUtc: episode.activatedAtUtc,
      localDate: episode.activatedAtUtc.slice(0, 10),
      type: "pregnancy_activation",
      summary: { status: "active", datingMethod: episode.datingMethod },
      deepLink: "/cocoon/pregnancy",
      sourceVersion: episode.version,
    });
  }
  return values;
}

function captureItems(body: Row | null, categories: Set<RecordCategory>) {
  const values: PregnancyRecordItem[] = [];
  if (categories.has("check_ins")) {
    for (const row of asRows(body?.checkIns)) {
      const id = sourceId(row, "id");
      if (!id) continue;
      values.push(item(row, {
        sourceKind: "pregnancy_check_in",
        sourceId: id,
        category: "check_ins",
        type: "check_in",
        summary: { feeling: row.feeling, energy: row.energy },
        deepLink: "/cocoon/pregnancy/daily",
      }));
    }
  }
  if (categories.has("symptoms")) {
    for (const row of asRows(body?.symptoms)) {
      const id = sourceId(row, "id");
      if (!id) continue;
      values.push(item(row, {
        sourceKind: "pregnancy_symptom",
        sourceId: id,
        category: "symptoms",
        type: "symptom",
        summary: { symptomCode: row.symptomCode, intensity: row.intensity },
        deepLink: "/cocoon/pregnancy/daily",
      }));
    }
  }
  if (categories.has("moods")) {
    for (const row of asRows(body?.moods)) {
      const id = sourceId(row, "id");
      if (!id) continue;
      values.push(item(row, {
        sourceKind: "pregnancy_mood",
        sourceId: id,
        category: "moods",
        type: "mood",
        summary: { moodCode: row.moodCode },
        deepLink: "/cocoon/pregnancy/daily",
      }));
    }
  }
  return values;
}

function measurementItems(body: Row | null, categories: Set<RecordCategory>) {
  if (!categories.has("measurements")) return [];
  return asRows(body?.items).flatMap((row) => {
    const id = sourceId(row, "id");
    return id == null ? [] : [item(row, {
      sourceKind: "health_observation",
      sourceId: id,
      category: "measurements",
      type: String(row.observationType ?? "measurement"),
      summary: { observationType: row.observationType },
      deepLink: `/health/observations/${id}`,
    })];
  });
}

function appointmentItems(body: Row | null, categories: Set<RecordCategory>) {
  if (!categories.has("appointments")) return [];
  return asRows(body?.items).flatMap((row) => {
    const id = sourceId(row, "id", "seriesId");
    const canonicalId = sourceId(row, "seriesId", "id");
    return id == null ? [] : [item(row, {
      sourceKind: "care_event",
      sourceId: id,
      category: "appointments",
      type: String(
        row.pregnancyClassification ?? row.eventType ?? "appointment",
      ),
      summary: {
        eventType: row.eventType,
        status: row.status,
        pregnancyClassification: row.pregnancyClassification,
      },
      deepLink: canonicalId == null ? undefined : `/care-events/${canonicalId}`,
    })];
  });
}

function treatmentItems(body: Row | null, categories: Set<RecordCategory>) {
  if (!categories.has("medications")) return [];
  const values: PregnancyRecordItem[] = [];
  for (const row of asRows(body?.treatmentPlans)) {
    const id = sourceId(row, "id");
    if (!id) continue;
    values.push(item(row, {
      sourceKind: "treatment_plan",
      sourceId: id,
      category: "medications",
      type: "treatment_plan",
      summary: { status: row.status },
      deepLink: `/treatments/${id}`,
    }));
  }
  for (const row of asRows(body?.doseOccurrences)) {
    const id = sourceId(row, "id");
    const planId = sourceId(row, "treatmentPlanId");
    if (!id) continue;
    values.push(item(row, {
      sourceKind: "dose_occurrence",
      sourceId: id,
      category: "medications",
      type: "dose_occurrence",
      summary: {
        status: row.status,
        scheduledLocalTime: row.scheduledLocalTime,
      },
      deepLink: planId == null ? undefined : `/treatments/${planId}`,
    }));
  }
  return values;
}

export function createPregnancyRecordsRouteHandler(databaseUrl: string) {
  const identity = createCocoonIdentityResolver(databaseUrl);
  const pregnancy = createPregnancyStore(databaseUrl);
  const authorization = createPregnancyAuthorization(databaseUrl);
  const captures = createPregnancyCaptureRouteHandler(databaseUrl);
  const measurements = createPregnancyMeasurementRouteHandler(databaseUrl);
  const calendar = createPregnancyCalendarRouteHandler(databaseUrl);
  const treatments = createPregnancyTreatmentRouteHandler(databaseUrl);

  return async ({
    request,
    path,
    appUserId,
  }: {
    request: Request;
    path: string;
    appUserId: string;
  }): Promise<Response | null> => {
    if (
      request.method !== "GET" || path !== "/api/v1/cocoon/pregnancy/records"
    ) {
      return null;
    }

    const url = new URL(request.url);
    const fromDate = requiredDate(url.searchParams.get("fromDate"), "fromDate");
    const toDate = requiredDate(url.searchParams.get("toDate"), "toDate");
    validateRange(fromDate, toDate, 31);
    const categories = requestedCategories(url.searchParams.get("categories"));
    const limit = boundedLimit(url.searchParams.get("limit"));
    const cursorValue = url.searchParams.get("cursor");
    const cursor = decodePregnancyRecordsCursor(cursorValue);
    if (cursorValue && !cursor) {
      throw new ApiError(
        400,
        "pregnancy_records_cursor_invalid",
        "Pregnancy records cursor is invalid.",
      );
    }

    const { accountId, personId } = await identity.resolve(appUserId);
    const episode = await pregnancy.getCurrentEpisode(personId);
    if (!episode || episode.status !== "active") {
      throw new ApiError(
        409,
        "active_pregnancy_required",
        "An active pregnancy is required.",
      );
    }
    await authorization.requireAccess({
      callerAccountId: accountId,
      subjectPersonId: personId,
      episodeId: episode.id,
      scope: "pregnancy.summary.read",
    });

    const query = `fromDate=${encodeURIComponent(fromDate)}&toDate=${
      encodeURIComponent(toDate)
    }`;
    const sourceRequest = (sourcePath: string) =>
      new Request(`${url.origin}${sourcePath}?${query}`);

    const [captureBody, measurementBody, calendarBody, treatmentBody] =
      await Promise.all([
        categories.has("check_ins") || categories.has("symptoms") ||
          categories.has("moods")
          ? responseBody(captures({
            request: sourceRequest("/api/v1/cocoon/pregnancy/daily-captures"),
            path: "/api/v1/cocoon/pregnancy/daily-captures",
            appUserId,
          }))
          : Promise.resolve(null),
        categories.has("measurements")
          ? responseBody(measurements({
            request: sourceRequest("/api/v1/cocoon/pregnancy/measurements"),
            path: "/api/v1/cocoon/pregnancy/measurements",
            appUserId,
          }))
          : Promise.resolve(null),
        categories.has("appointments")
          ? responseBody(calendar({
            request: sourceRequest("/api/v1/cocoon/pregnancy/calendar"),
            path: "/api/v1/cocoon/pregnancy/calendar",
            appUserId,
          }))
          : Promise.resolve(null),
        categories.has("medications")
          ? responseBody(treatments({
            request: sourceRequest("/api/v1/cocoon/pregnancy/treatments"),
            path: "/api/v1/cocoon/pregnancy/treatments",
            appUserId,
          }))
          : Promise.resolve(null),
      ]);

    const values = [
      ...lifecycleItems(episode, categories),
      ...captureItems(captureBody, categories),
      ...measurementItems(measurementBody, categories),
      ...appointmentItems(calendarBody, categories),
      ...treatmentItems(treatmentBody, categories),
    ].filter((value) =>
      value.localDate >= fromDate && value.localDate <= toDate
    );
    const page = paginatePregnancyRecords(values, limit, cursor);

    return json({
      contractVersion: 1,
      episodeId: episode.id,
      fromDate,
      toDate,
      categories: [...categories],
      items: page.items,
      nextCursor: page.nextCursor,
      sourceOfTruth: "composed_canonical_domains",
    });
  };
}
