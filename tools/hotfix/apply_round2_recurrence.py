from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, found {count}: {old[:90]!r}")
    write(path, text.replace(old, new, 1))


def regex_once(path: str, pattern: str, replacement: str, flags=0) -> None:
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise RuntimeError(f"{path}: regex expected one match, found {count}: {pattern[:100]!r}")
    write(path, updated)


write(
    "packages/lifemate_client/lib/src/recurrence.dart",
    r'''enum RecurrenceUnit { day, week, month, year }

class RecurrenceRule {
  const RecurrenceRule({
    this.enabled = false,
    this.unit = RecurrenceUnit.month,
    this.interval = 1,
    this.weekdays = const <int>{},
    this.endDate,
  }) : assert(interval > 0);

  const RecurrenceRule.none()
      : enabled = false,
        unit = RecurrenceUnit.month,
        interval = 1,
        weekdays = const <int>{},
        endDate = null;

  final bool enabled;
  final RecurrenceUnit unit;
  final int interval;
  final Set<int> weekdays;
  final DateTime? endDate;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (enabled) 'unit': unit.name,
        if (enabled) 'interval': interval,
        if (enabled && weekdays.isNotEmpty)
          'weekdays': weekdays.toList()..sort(),
        if (enabled && endDate != null) 'endDate': _date(endDate!),
      };

  factory RecurrenceRule.fromJson(dynamic value) {
    if (value is! Map || value['enabled'] != true) {
      return const RecurrenceRule.none();
    }
    final record = Map<String, dynamic>.from(value);
    final unit = RecurrenceUnit.values.firstWhere(
      (item) => item.name == record['unit']?.toString().toLowerCase(),
      orElse: () => RecurrenceUnit.month,
    );
    final interval = int.tryParse(record['interval']?.toString() ?? '') ?? 1;
    final weekdays = (record['weekdays'] is List
            ? record['weekdays'] as List
            : const <dynamic>[])
        .map((item) => int.tryParse(item.toString()))
        .whereType<int>()
        .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
        .toSet();
    return RecurrenceRule(
      enabled: true,
      unit: unit,
      interval: interval.clamp(1, 365),
      weekdays: weekdays,
      endDate: DateTime.tryParse(record['endDate']?.toString() ?? ''),
    );
  }

  List<DateTime> occurrencesBetween({
    required DateTime startDate,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final start = _onlyDate(startDate);
    final from = _onlyDate(fromDate);
    final to = _onlyDate(toDate);
    if (to.isBefore(from) || to.isBefore(start)) return const [];
    final upper = endDate == null || _onlyDate(endDate!).isAfter(to)
        ? to
        : _onlyDate(endDate!);
    if (upper.isBefore(start)) return const [];
    if (!enabled) {
      return !start.isBefore(from) && !start.isAfter(upper) ? [start] : const [];
    }

    final values = <DateTime>{};
    switch (unit) {
      case RecurrenceUnit.day:
        for (var cursor = start;
            !cursor.isAfter(upper);
            cursor = cursor.add(Duration(days: interval))) {
          if (!cursor.isBefore(from)) values.add(cursor);
        }
      case RecurrenceUnit.week:
        final allowed = weekdays.isEmpty ? <int>{start.weekday} : weekdays;
        final first = from.isAfter(start) ? from : start;
        for (var cursor = first;
            !cursor.isAfter(upper);
            cursor = cursor.add(const Duration(days: 1))) {
          final daysFromStart = cursor.difference(start).inDays;
          final weekIndex = daysFromStart ~/ 7;
          if (weekIndex % interval == 0 && allowed.contains(cursor.weekday)) {
            values.add(cursor);
          }
        }
      case RecurrenceUnit.month:
        for (var occurrence = 0; occurrence < 2400; occurrence++) {
          final cursor = _addMonthsClamped(start, occurrence * interval);
          if (cursor.isAfter(upper)) break;
          if (!cursor.isBefore(from)) values.add(cursor);
        }
      case RecurrenceUnit.year:
        for (var occurrence = 0; occurrence < 400; occurrence++) {
          final cursor = _addMonthsClamped(start, occurrence * interval * 12);
          if (cursor.isAfter(upper)) break;
          if (!cursor.isBefore(from)) values.add(cursor);
        }
    }
    final sorted = values.toList()..sort();
    return List<DateTime>.unmodifiable(sorted);
  }

  static DateTime _addMonthsClamped(DateTime start, int months) {
    final first = DateTime(start.year, start.month + months, 1);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month, start.day.clamp(1, lastDay));
  }

  static DateTime _onlyDate(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
''',
)
replace_once(
    "packages/lifemate_client/lib/lifemate_client.dart",
    "export 'src/reminder_lead_time.dart';\n",
    "export 'src/reminder_lead_time.dart';\nexport 'src/recurrence.dart';\n",
)

write(
    "supabase/migrations/20260808105500_add_care_event_recurrence.sql",
    r'''-- Additive recurrence metadata for appointments and injections.
-- Existing rows remain non-recurring and no care-event data is rewritten.

alter table lifemate.care_events
  add column if not exists recurrence_unit varchar(16) not null default 'none',
  add column if not exists recurrence_interval integer not null default 1,
  add column if not exists recurrence_weekdays smallint[] not null default '{}',
  add column if not exists recurrence_end_date date null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'care_events_recurrence_unit_check'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      add constraint care_events_recurrence_unit_check
      check (recurrence_unit in ('none', 'day', 'week', 'month', 'year'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'care_events_recurrence_interval_check'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      add constraint care_events_recurrence_interval_check
      check (recurrence_interval between 1 and 365);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'care_events_recurrence_weekdays_check'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      add constraint care_events_recurrence_weekdays_check
      check (
        recurrence_weekdays <@ array[1,2,3,4,5,6,7]::smallint[]
        and cardinality(recurrence_weekdays) <= 7
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'care_events_recurrence_end_check'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      add constraint care_events_recurrence_end_check
      check (recurrence_end_date is null or recurrence_end_date >= scheduled_local_date);
  end if;
end $$;

create index if not exists ix_care_events_patient_recurrence_window
  on lifemate.care_events(patient_user_id, scheduled_local_date, recurrence_end_date)
  where status <> 'Cancelled';
''',
)

write(
    "supabase/functions/lifemate-api/care_events.ts",
    r'''import { getLifeMateSql } from "./database_client.ts";
import {
  ApiError,
  limitedOptional,
  requiredDate,
  requiredText,
  requiredTimeZone,
  requiredUuid,
  validateRange,
} from "./validation.ts";

type CareEventType = "Appointment" | "Injection";
type CareEventRecurrenceUnit = "none" | "day" | "week" | "month" | "year";

export type CareEventRecurrence = {
  enabled: boolean;
  unit: CareEventRecurrenceUnit;
  interval: number;
  weekdays: number[];
  endDate: string | null;
};

type CareEventInput = {
  clientRequestId: string;
  eventType: CareEventType;
  title: string;
  providerName: string | null;
  specialty: string | null;
  medicationName: string | null;
  doseText: string | null;
  administrationRoute: string | null;
  reason: string | null;
  instructions: string | null;
  centerName: string | null;
  addressLine: string | null;
  phoneNumber: string | null;
  scheduledLocalDate: string;
  scheduledLocalTime: string;
  timeZone: string;
  recurrence: CareEventRecurrence;
  patientReminderMinutesBefore: number;
  caregiverReminderMinutesBefore: number;
};

export function createCareEventStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function createCareEvent(
    patientUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const input = normalizeCareEvent(body);
    const now = new Date();
    return await sql.begin(async (tx: any) => {
      const existingRows = await tx`
        select * from lifemate.care_events
        where patient_user_id = ${patientUserId}
          and client_request_id = ${input.clientRequestId}
        limit 1
      `;
      if (existingRows[0]) {
        if (!sameCareEvent(existingRows[0], input)) {
          throw new ApiError(
            409,
            "idempotency_key_reused",
            "clientRequestId was already used for a different care event.",
          );
        }
        return mapCareEvent(existingRows[0]);
      }

      const id = crypto.randomUUID();
      const rows = await tx`
        insert into lifemate.care_events
          (id, patient_user_id, client_request_id, event_type, title,
           provider_name, specialty, medication_name, dose_text,
           administration_route, reason, instructions, center_name,
           address_line, phone_number, scheduled_local_date,
           scheduled_local_time, time_zone, recurrence_unit,
           recurrence_interval, recurrence_weekdays, recurrence_end_date,
           patient_reminder_minutes_before,
           caregiver_reminder_minutes_before, status, version,
           created_at_utc, updated_at_utc)
        values
          (${id}, ${patientUserId}, ${input.clientRequestId},
           ${input.eventType}, ${input.title}, ${input.providerName},
           ${input.specialty}, ${input.medicationName}, ${input.doseText},
           ${input.administrationRoute}, ${input.reason}, ${input.instructions},
           ${input.centerName}, ${input.addressLine}, ${input.phoneNumber},
           ${input.scheduledLocalDate}, ${input.scheduledLocalTime},
           ${input.timeZone}, ${input.recurrence.unit},
           ${input.recurrence.interval}, ${input.recurrence.weekdays},
           ${input.recurrence.endDate}, ${input.patientReminderMinutesBefore},
           ${input.caregiverReminderMinutesBefore}, 'Scheduled', 1,
           ${now}, ${now})
        returning *
      `;
      await insertAudit(
        tx,
        patientUserId,
        "care_event.created",
        "care_event",
        id,
        { eventType: input.eventType },
      );
      return mapCareEvent(rows[0]);
    });
  }

  async function listCareEvents(
    patientUserId: string,
    fromValue: unknown,
    toValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const { fromDate, toDate } = normalizeRange(fromValue, toValue);
    return await selectCareEvents(patientUserId, fromDate, toDate);
  }

  async function listCareRecipientEvents(
    caregiverUserId: string,
    patientUserIdValue: unknown,
    fromValue: unknown,
    toValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const patientUserId = requiredUuid(patientUserIdValue, "patientUserId");
    const relationship = await sql`
      select id from lifemate.care_relationships
      where patient_user_id = ${patientUserId}
        and caregiver_user_id = ${caregiverUserId}
        and status = 'Active'
      limit 1
    `;
    if (!relationship[0]) {
      throw new ApiError(
        403,
        "care_access_denied",
        "An active care relationship is required.",
      );
    }
    const { fromDate, toDate } = normalizeRange(fromValue, toValue);
    return await selectCareEvents(patientUserId, fromDate, toDate);
  }

  async function selectCareEvents(
    patientUserId: string,
    fromDate: string,
    toDate: string,
  ): Promise<Record<string, unknown>[]> {
    // Select series whose base/recurrence window can intersect the requested
    // range, then deterministically expand only the bounded range in memory.
    const rows = await sql`
      select *
      from lifemate.care_events
      where patient_user_id = ${patientUserId}
        and status <> 'Cancelled'
        and scheduled_local_date <= ${toDate}::date
        and (
          recurrence_unit = 'none'
          or recurrence_end_date is null
          or recurrence_end_date >= ${fromDate}::date
        )
      order by scheduled_local_date, scheduled_local_time, id
      limit 200
    `;
    const expanded: Record<string, unknown>[] = [];
    for (const row of rows) {
      const recurrence = recurrenceFromRow(row);
      const dates = generateCareEventOccurrenceDates(
        dateString(row.scheduled_local_date),
        recurrence,
        fromDate,
        toDate,
      );
      for (const occurrenceDate of dates) {
        expanded.push(mapCareEvent(row, occurrenceDate));
      }
    }
    expanded.sort((left, right) => {
      const l = `${left.scheduledLocalDate} ${left.scheduledLocalTime} ${left.id}`;
      const r = `${right.scheduledLocalDate} ${right.scheduledLocalTime} ${right.id}`;
      return l.localeCompare(r);
    });
    return expanded.slice(0, 500);
  }

  return { createCareEvent, listCareEvents, listCareRecipientEvents };
}

export function generateCareEventOccurrenceDates(
  startDate: string,
  recurrence: CareEventRecurrence,
  fromDate: string,
  toDate: string,
): string[] {
  const start = parseDate(startDate);
  const from = parseDate(fromDate);
  const to = parseDate(toDate);
  const recurrenceEnd = recurrence.endDate == null
    ? to
    : minDate(parseDate(recurrence.endDate), to);
  if (to < from || recurrenceEnd < start || to < start) return [];
  if (!recurrence.enabled || recurrence.unit === "none") {
    return start >= from && start <= recurrenceEnd ? [formatDate(start)] : [];
  }

  const values = new Set<string>();
  if (recurrence.unit === "day") {
    for (
      let cursor = start, guard = 0;
      cursor <= recurrenceEnd && guard < 5000;
      cursor = addDays(cursor, recurrence.interval), guard++
    ) {
      if (cursor >= from) values.add(formatDate(cursor));
    }
  } else if (recurrence.unit === "week") {
    const allowed = new Set(
      recurrence.weekdays.length > 0
        ? recurrence.weekdays
        : [isoWeekday(start)],
    );
    let cursor = maxDate(start, from);
    for (let guard = 0; cursor <= recurrenceEnd && guard < 5000; guard++) {
      const daysFromStart = Math.floor((cursor.getTime() - start.getTime()) / 86400000);
      const weekIndex = Math.floor(daysFromStart / 7);
      if (
        weekIndex % recurrence.interval === 0 &&
        allowed.has(isoWeekday(cursor))
      ) {
        values.add(formatDate(cursor));
      }
      cursor = addDays(cursor, 1);
    }
  } else {
    const monthFactor = recurrence.unit === "year" ? 12 : 1;
    const maximum = recurrence.unit === "year" ? 400 : 2400;
    for (let occurrence = 0; occurrence < maximum; occurrence++) {
      const cursor = addMonthsClamped(
        start,
        occurrence * recurrence.interval * monthFactor,
      );
      if (cursor > recurrenceEnd) break;
      if (cursor >= from) values.add(formatDate(cursor));
    }
  }
  return [...values].sort();
}

function normalizeRange(
  fromValue: unknown,
  toValue: unknown,
): { fromDate: string; toDate: string } {
  const fromDate = requiredDate(fromValue, "fromDate");
  const toDate = requiredDate(toValue, "toDate");
  validateRange(fromDate, toDate, 31);
  return { fromDate, toDate };
}

function normalizeCareEvent(body: Record<string, unknown>): CareEventInput {
  const eventType = normalizeEventType(body.eventType);
  const title = requiredText(body.title, "title", 160);
  const scheduledLocalDate = requiredDate(
    body.scheduledLocalDate,
    "scheduledLocalDate",
  );
  const scheduledLocalTime = requiredLocalTime(
    body.scheduledLocalTime,
    "scheduledLocalTime",
  );
  const timeZone = requiredTimeZone(body.timeZone);
  const medicationName = limitedOptional(
    body.medicationName,
    "medicationName",
    160,
  );
  if (eventType === "Injection" && !medicationName) {
    throw new ApiError(
      400,
      "invalid_medicationName",
      "medicationName is required for injection events.",
    );
  }
  return {
    clientRequestId: requiredUuid(body.clientRequestId, "clientRequestId"),
    eventType,
    title,
    providerName: limitedOptional(body.providerName, "providerName", 160),
    specialty: limitedOptional(body.specialty, "specialty", 120),
    medicationName,
    doseText: limitedOptional(body.doseText, "doseText", 120),
    administrationRoute: normalizeAdministrationRoute(body.administrationRoute),
    reason: limitedOptional(body.reason, "reason", 500),
    instructions: limitedOptional(body.instructions, "instructions", 1000),
    centerName: limitedOptional(body.centerName, "centerName", 200),
    addressLine: limitedOptional(body.addressLine, "addressLine", 500),
    phoneNumber: limitedOptional(body.phoneNumber, "phoneNumber", 40),
    scheduledLocalDate,
    scheduledLocalTime,
    timeZone,
    recurrence: normalizeRecurrence(body.recurrence, scheduledLocalDate),
    patientReminderMinutesBefore: normalizeReminderLeadTime(
      body.patientReminderMinutesBefore,
      "patientReminderMinutesBefore",
      30,
    ),
    caregiverReminderMinutesBefore: normalizeReminderLeadTime(
      body.caregiverReminderMinutesBefore,
      "caregiverReminderMinutesBefore",
      60,
    ),
  };
}

function normalizeRecurrence(
  value: unknown,
  startDate: string,
): CareEventRecurrence {
  if (value == null) return noRecurrence();
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(400, "invalid_recurrence", "recurrence must be an object.");
  }
  const record = value as Record<string, unknown>;
  if (record.enabled !== true) return noRecurrence();
  const unitAliases: Record<string, CareEventRecurrenceUnit> = {
    day: "day",
    days: "day",
    week: "week",
    weeks: "week",
    month: "month",
    months: "month",
    year: "year",
    years: "year",
  };
  const unit = unitAliases[String(record.unit ?? "").trim().toLowerCase()];
  if (!unit) {
    throw new ApiError(400, "invalid_recurrence_unit", "Unsupported recurrence unit.");
  }
  const interval = Number(record.interval ?? 1);
  if (!Number.isInteger(interval) || interval < 1 || interval > 365) {
    throw new ApiError(
      400,
      "invalid_recurrence_interval",
      "recurrence interval must be between 1 and 365.",
    );
  }
  const rawWeekdays = record.weekdays ?? [];
  if (!Array.isArray(rawWeekdays)) {
    throw new ApiError(400, "invalid_recurrence_weekdays", "weekdays must be an array.");
  }
  const weekdays = [...new Set(rawWeekdays.map(Number))].sort((a, b) => a - b);
  if (weekdays.some((day) => !Number.isInteger(day) || day < 1 || day > 7)) {
    throw new ApiError(400, "invalid_recurrence_weekdays", "weekdays must use ISO values 1..7.");
  }
  const endDate = record.endDate == null
    ? null
    : requiredDate(record.endDate, "recurrence.endDate");
  if (endDate != null && endDate < startDate) {
    throw new ApiError(
      400,
      "invalid_recurrence_end",
      "recurrence end date cannot precede the start date.",
    );
  }
  return {
    enabled: true,
    unit,
    interval,
    weekdays: unit === "week" ? weekdays : [],
    endDate,
  };
}

function noRecurrence(): CareEventRecurrence {
  return { enabled: false, unit: "none", interval: 1, weekdays: [], endDate: null };
}

function recurrenceFromRow(row: Record<string, any>): CareEventRecurrence {
  const unit = String(row.recurrence_unit ?? "none") as CareEventRecurrenceUnit;
  const weekdays = Array.isArray(row.recurrence_weekdays)
    ? row.recurrence_weekdays.map(Number).filter(Number.isInteger)
    : [];
  return {
    enabled: unit !== "none",
    unit,
    interval: Number(row.recurrence_interval ?? 1),
    weekdays,
    endDate: row.recurrence_end_date == null
      ? null
      : dateString(row.recurrence_end_date),
  };
}

function normalizeEventType(value: unknown): CareEventType {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (normalized === "appointment" || normalized === "visit") {
    return "Appointment";
  }
  if (normalized === "injection") return "Injection";
  throw new ApiError(
    400,
    "invalid_eventType",
    "eventType must be appointment or injection.",
  );
}

function normalizeAdministrationRoute(value: unknown): string | null {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (!normalized) return null;
  const routes: Record<string, string> = {
    intramuscular: "Intramuscular",
    subcutaneous: "Subcutaneous",
    intravenous: "Intravenous",
    other: "Other",
  };
  const route = routes[normalized];
  if (!route) {
    throw new ApiError(
      400,
      "invalid_administrationRoute",
      "Unsupported administration route.",
    );
  }
  return route;
}

function requiredLocalTime(value: unknown, field: string): string {
  const match = /^(\d{2}):(\d{2})(?::\d{2})?$/.exec(String(value ?? "").trim());
  if (!match || Number(match[1]) > 23 || Number(match[2]) > 59) {
    throw new ApiError(400, `invalid_${field}`, `${field} must be a valid HH:mm value.`);
  }
  return `${match[1]}:${match[2]}`;
}

function normalizeReminderLeadTime(
  value: unknown,
  field: string,
  fallback: number,
): number {
  if (value == null || value === "") return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 10080) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} must be an integer between 0 and 10080 minutes.`,
    );
  }
  return parsed;
}

function sameCareEvent(row: Record<string, any>, input: CareEventInput): boolean {
  const recurrence = recurrenceFromRow(row);
  return String(row.event_type) === input.eventType &&
    String(row.title) === input.title &&
    nullable(row.provider_name) === input.providerName &&
    nullable(row.specialty) === input.specialty &&
    nullable(row.medication_name) === input.medicationName &&
    nullable(row.dose_text) === input.doseText &&
    nullable(row.administration_route) === input.administrationRoute &&
    nullable(row.reason) === input.reason &&
    nullable(row.instructions) === input.instructions &&
    nullable(row.center_name) === input.centerName &&
    nullable(row.address_line) === input.addressLine &&
    nullable(row.phone_number) === input.phoneNumber &&
    dateString(row.scheduled_local_date) === input.scheduledLocalDate &&
    timeString(row.scheduled_local_time) === input.scheduledLocalTime &&
    String(row.time_zone) === input.timeZone &&
    recurrence.unit === input.recurrence.unit &&
    recurrence.interval === input.recurrence.interval &&
    JSON.stringify(recurrence.weekdays) === JSON.stringify(input.recurrence.weekdays) &&
    recurrence.endDate === input.recurrence.endDate &&
    Number(row.patient_reminder_minutes_before ?? 30) ===
      input.patientReminderMinutesBefore &&
    Number(row.caregiver_reminder_minutes_before ?? 60) ===
      input.caregiverReminderMinutesBefore;
}

function mapCareEvent(
  row: Record<string, any>,
  occurrenceDateValue?: string,
): Record<string, unknown> {
  const recurrence = recurrenceFromRow(row);
  const baseId = String(row.id);
  const occurrenceDate = occurrenceDateValue ?? dateString(row.scheduled_local_date);
  const recurringOccurrence = recurrence.enabled && occurrenceDateValue != null;
  const scheduledAtUtc = localDateTimeToUtc(
    occurrenceDate,
    timeString(row.scheduled_local_time),
    String(row.time_zone),
  );
  const storedStatus = String(row.status).toLowerCase();
  const status = storedStatus === "scheduled" && new Date(scheduledAtUtc) < new Date()
    ? "missed"
    : storedStatus;
  return {
    id: recurringOccurrence ? `${baseId}:${occurrenceDate}` : baseId,
    seriesId: baseId,
    occurrenceId: `${baseId}:${occurrenceDate}`,
    patientUserId: row.patient_user_id,
    eventType: String(row.event_type).toLowerCase(),
    title: row.title,
    providerName: row.provider_name,
    specialty: row.specialty,
    medicationName: row.medication_name,
    doseText: row.dose_text,
    administrationRoute: row.administration_route == null
      ? null
      : String(row.administration_route).toLowerCase(),
    reason: row.reason,
    instructions: row.instructions,
    centerName: row.center_name,
    addressLine: row.address_line,
    phoneNumber: row.phone_number,
    scheduledLocalDate: occurrenceDate,
    scheduledLocalTime: timeString(row.scheduled_local_time),
    scheduledAtUtc,
    timeZone: row.time_zone,
    recurrence,
    patientReminderMinutesBefore: Number(row.patient_reminder_minutes_before ?? 30),
    caregiverReminderMinutesBefore: Number(row.caregiver_reminder_minutes_before ?? 60),
    status,
    version: row.version,
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function localDateTimeToUtc(date: string, time: string, timeZone: string): string {
  const [year, month, day] = date.split("-").map(Number);
  const [hour, minute] = time.split(":").map(Number);
  const targetAsUtc = Date.UTC(year, month - 1, day, hour, minute);
  let guess = targetAsUtc;
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
  for (let attempt = 0; attempt < 3; attempt++) {
    const parts = Object.fromEntries(
      formatter.formatToParts(new Date(guess)).map((part) => [part.type, part.value]),
    );
    const represented = Date.UTC(
      Number(parts.year),
      Number(parts.month) - 1,
      Number(parts.day),
      Number(parts.hour),
      Number(parts.minute),
    );
    const delta = targetAsUtc - represented;
    guess += delta;
    if (Math.abs(delta) < 60_000) break;
  }
  return new Date(guess).toISOString();
}

function parseDate(value: string): Date {
  return new Date(`${value}T00:00:00.000Z`);
}

function formatDate(value: Date): string {
  return value.toISOString().slice(0, 10);
}

function addDays(value: Date, days: number): Date {
  return new Date(value.getTime() + days * 86400000);
}

function addMonthsClamped(value: Date, months: number): Date {
  const year = value.getUTCFullYear();
  const month = value.getUTCMonth();
  const day = value.getUTCDate();
  const first = new Date(Date.UTC(year, month + months, 1));
  const lastDay = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0))
    .getUTCDate();
  return new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth(), Math.min(day, lastDay)));
}

function isoWeekday(value: Date): number {
  const day = value.getUTCDay();
  return day === 0 ? 7 : day;
}

function minDate(left: Date, right: Date): Date {
  return left <= right ? left : right;
}

function maxDate(left: Date, right: Date): Date {
  return left >= right ? left : right;
}

function nullable(value: unknown): string | null {
  return value == null ? null : String(value);
}

function dateString(value: unknown): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}

function timeString(value: unknown): string {
  return String(value).slice(0, 5);
}

function iso(value: unknown): string | null {
  if (value == null) return null;
  if (value instanceof Date) return value.toISOString();
  return new Date(String(value)).toISOString();
}

async function insertAudit(
  sql: any,
  actorUserId: string,
  action: string,
  entityType: string,
  entityId: string,
  metadata: Record<string, unknown>,
): Promise<void> {
  const metadataJson = JSON.stringify(metadata);
  await sql`
    insert into lifemate.audit_logs
      (id, actor_user_id, action, entity_type, entity_id, metadata_json,
       occurred_at_utc)
    values
      (${crypto.randomUUID()}, ${actorUserId}, ${action}, ${entityType},
       ${entityId}, ${metadataJson}, now())
  `;
}
''',
)

# Shared API: recurrence is optional/backward-compatible and only sent as
# presentation-neutral machine values.
replace_once(
    "packages/lifemate_client/lib/src/lifemate_api_client.dart",
    "import 'reminder_lead_time.dart';\n",
    "import 'reminder_lead_time.dart';\nimport 'recurrence.dart';\n",
)
replace_once(
    "packages/lifemate_client/lib/src/lifemate_api_client.dart",
    "    String? phoneNumber,\n    int patientReminderMinutesBefore =\n        LifeMateReminderLeadTimes.defaultPatientMinutes,",
    "    String? phoneNumber,\n    RecurrenceRule recurrence = const RecurrenceRule.none(),\n    int patientReminderMinutesBefore =\n        LifeMateReminderLeadTimes.defaultPatientMinutes,",
)
replace_once(
    "packages/lifemate_client/lib/src/lifemate_api_client.dart",
    "        'phoneNumber': _emptyToNull(phoneNumber),\n        'scheduledLocalDate': _date(scheduledLocalDate),",
    "        'phoneNumber': _emptyToNull(phoneNumber),\n        'scheduledLocalDate': _date(scheduledLocalDate),\n        'recurrence': recurrence.toJson(),",
)

# Schedule items need occurrence identity for reminders and series identity for
# whole-series editing.
replace_once(
    "wellmate/lib/models/schedule_item_model.dart",
    "  final String id;\n  final String title;",
    "  final String id;\n  final String? seriesId;\n  final String title;",
)
replace_once(
    "wellmate/lib/models/schedule_item_model.dart",
    "    required this.id,\n    required this.title,",
    "    required this.id,\n    this.seriesId,\n    required this.title,",
)
replace_once(
    "wellmate/lib/models/schedule_item_model.dart",
    "      id: json['id']?.toString() ?? '',\n      title:",
    "      id: json['id']?.toString() ?? '',\n      seriesId: json['seriesId']?.toString(),\n      title:",
)
replace_once(
    "wellmate/lib/models/schedule_item_model.dart",
    "      'id': id,\n      'title': title,",
    "      'id': id,\n      'seriesId': seriesId,\n      'title': title,",
)
replace_once(
    "wellmate/lib/models/schedule_item_model.dart",
    "    String? id,\n    String? title,",
    "    String? id,\n    String? seriesId,\n    String? title,",
)
replace_once(
    "wellmate/lib/models/schedule_item_model.dart",
    "      id: id ?? this.id,\n      title: title ?? this.title,",
    "      id: id ?? this.id,\n      seriesId: seriesId ?? this.seriesId,\n      title: title ?? this.title,",
)

# Home and calendar use occurrence id for rendering/reminders, series id for edits.
for path in [
    "wellmate/lib/screens/home/home_screen_content.dart",
    "wellmate/lib/screens/calendar/calendar_screen.dart",
]:
    replace_once(
        path,
        "            id: event['id']?.toString() ?? '',\n            type: type,",
        "            id: event['id']?.toString() ?? '',\n            seriesId: event['seriesId']?.toString(),\n            type: type,",
    ) if path.endswith("home_screen_content.dart") else replace_once(
        path,
        "      id: event['id']?.toString() ?? '',\n      title:",
        "      id: event['id']?.toString() ?? '',\n      seriesId: event['seriesId']?.toString(),\n      title:",
    )
replace_once(
    "wellmate/lib/screens/calendar/calendar_screen.dart",
    "        builder: (_) => EditCareEventScreen(eventId: item.id),",
    "        builder: (_) => EditCareEventScreen(eventId: item.seriesId ?? item.id),",
)

# Recurrence controls for appointment/injection creation.
replace_once(
    "wellmate/lib/screens/treatments/care_event_form.dart",
    "  final _instructions = TextEditingController();\n\n  DateTime _date = DateTime.now();",
    "  final _instructions = TextEditingController();\n  final _repeatInterval = TextEditingController(text: '1');\n\n  DateTime _date = DateTime.now();",
)
replace_once(
    "wellmate/lib/screens/treatments/care_event_form.dart",
    "  String _administrationRoute = 'intramuscular';\n",
    "  String _administrationRoute = 'intramuscular';\n  bool _repeatEnabled = false;\n  RecurrenceUnit _repeatUnit = RecurrenceUnit.month;\n  DateTime? _repeatEndDate;\n  final Set<int> _repeatWeekdays = <int>{};\n",
)
replace_once(
    "wellmate/lib/screens/treatments/care_event_form.dart",
    "    _instructions.dispose();\n    super.dispose();",
    "    _instructions.dispose();\n    _repeatInterval.dispose();\n    super.dispose();",
)
replace_once(
    "wellmate/lib/screens/treatments/care_event_form.dart",
    "  String get _timeValue =>\n      '${_time.hour.toString().padLeft(2, '0')}:'\n      '${_time.minute.toString().padLeft(2, '0')}';\n\n  Future<void> _submit() async {",
    "  String get _timeValue =>\n      '${_time.hour.toString().padLeft(2, '0')}:'\n      '${_time.minute.toString().padLeft(2, '0')}';\n\n  RecurrenceRule? _recurrenceRule() {\n    if (!_repeatEnabled) return const RecurrenceRule.none();\n    final interval = LifeMateNumbers.tryParseInt(_repeatInterval.text);\n    if (interval == null || interval < 1 || interval > 365) {\n      setState(() => _error = 'فاصله تکرار باید یک عدد بین ۱ تا ۳۶۵ باشد.');\n      return null;\n    }\n    final weekdays = _repeatUnit == RecurrenceUnit.week\n        ? (_repeatWeekdays.isEmpty ? <int>{_date.weekday} : _repeatWeekdays)\n        : const <int>{};\n    return RecurrenceRule(\n      enabled: true,\n      unit: _repeatUnit,\n      interval: interval,\n      weekdays: weekdays,\n      endDate: _repeatEndDate,\n    );\n  }\n\n  Future<void> _pickRepeatEndDate() async {\n    final value = await showAppDatePicker(\n      context: context,\n      initialDate: _repeatEndDate ?? _date.add(const Duration(days: 180)),\n      firstDate: _date,\n      lastDate: _date.add(const Duration(days: 3650)),\n      title: 'پایان تکرار',\n    );\n    if (mounted && value != null) setState(() => _repeatEndDate = value);\n  }\n\n  Future<void> _submit() async {",
)
replace_once(
    "wellmate/lib/screens/treatments/care_event_form.dart",
    "    if (!_formKey.currentState!.validate()) return;\n\n    setState(() {",
    "    if (!_formKey.currentState!.validate()) return;\n    final recurrence = _recurrenceRule();\n    if (recurrence == null) return;\n\n    setState(() {",
)
replace_once(
    "wellmate/lib/screens/treatments/care_event_form.dart",
    "        timeZone: _timeZone,\n        patientReminderMinutesBefore:",
    "        timeZone: _timeZone,\n        recurrence: recurrence,\n        patientReminderMinutesBefore:",
)
replace_once(
    "wellmate/lib/screens/treatments/care_event_form.dart",
    "      _administrationRoute = 'intramuscular';\n      _patientReminderMinutesBefore =",
    "      _administrationRoute = 'intramuscular';\n      _repeatEnabled = false;\n      _repeatUnit = RecurrenceUnit.month;\n      _repeatInterval.text = '1';\n      _repeatEndDate = null;\n      _repeatWeekdays.clear();\n      _patientReminderMinutesBefore =",
)

recurrence_ui = r'''              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                key: const ValueKey('care-event-repeat-enabled'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'تکرار برنامه',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: const Text('برای چکاپ یا تزریق دوره‌ای، مثل هر ۶ ماه'),
                value: _repeatEnabled,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _repeatEnabled = value),
              ),
              if (_repeatEnabled) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('care-event-repeat-interval'),
                        controller: _repeatInterval,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        decoration: wellMateFieldDecoration(hint: 'مثلاً ۶'),
                        validator: (value) {
                          final parsed = LifeMateNumbers.tryParseInt(value);
                          return parsed != null && parsed >= 1 && parsed <= 365
                              ? null
                              : '۱ تا ۳۶۵';
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<RecurrenceUnit>(
                        key: const ValueKey('care-event-repeat-unit'),
                        initialValue: _repeatUnit,
                        decoration: wellMateFieldDecoration(),
                        items: const [
                          DropdownMenuItem(value: RecurrenceUnit.day, child: Text('روز')),
                          DropdownMenuItem(value: RecurrenceUnit.week, child: Text('هفته')),
                          DropdownMenuItem(value: RecurrenceUnit.month, child: Text('ماه')),
                          DropdownMenuItem(value: RecurrenceUnit.year, child: Text('سال')),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _repeatUnit = value ?? _repeatUnit),
                      ),
                    ),
                  ],
                ),
                if (_repeatUnit == RecurrenceUnit.week) ...[
                  const SizedBox(height: 12),
                  const Text('روزهای هفته', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final day in const <(int, String)>[
                        (DateTime.saturday, 'ش'),
                        (DateTime.sunday, 'ی'),
                        (DateTime.monday, 'د'),
                        (DateTime.tuesday, 'س'),
                        (DateTime.wednesday, 'چ'),
                        (DateTime.thursday, 'پ'),
                        (DateTime.friday, 'ج'),
                      ])
                        FilterChip(
                          label: Text(day.$2),
                          selected: _repeatWeekdays.contains(day.$1),
                          onSelected: _busy
                              ? null
                              : (selected) => setState(() {
                                    if (selected) {
                                      _repeatWeekdays.add(day.$1);
                                    } else {
                                      _repeatWeekdays.remove(day.$1);
                                    }
                                  }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _PickerTile(
                  key: const ValueKey('care-event-repeat-end'),
                  label: 'پایان تکرار',
                  value: _repeatEndDate == null
                      ? 'بدون تاریخ پایان'
                      : formatAppDate(context, _repeatEndDate!),
                  icon: Icons.event_repeat_rounded,
                  onTap: _busy ? null : _pickRepeatEndDate,
                ),
                if (_repeatEndDate != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _busy ? null : () => setState(() => _repeatEndDate = null),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('بدون تاریخ پایان'),
                    ),
                  ),
              ],
'''
replace_once(
    "wellmate/lib/screens/treatments/care_event_form.dart",
    "              const SizedBox(height: 16),\n              WellMateLabeledField(\n                label: 'یادآوری برای خودم',",
    recurrence_ui + "              const SizedBox(height: 16),\n              WellMateLabeledField(\n                label: 'یادآوری برای خودم',",
)
# Persian digits for reminder preset labels.
replace_once(
    "wellmate/lib/screens/treatments/care_event_form.dart",
    "                        child: Text(LifeMateReminderLeadTimes.label(minutes)),",
    "                        child: Text(localizeDigits(context, LifeMateReminderLeadTimes.label(minutes))),",
)
replace_once(
    "wellmate/lib/screens/treatments/care_event_form.dart",
    "                        child: Text(LifeMateReminderLeadTimes.label(minutes)),",
    "                        child: Text(localizeDigits(context, LifeMateReminderLeadTimes.label(minutes))),",
)

# Dart recurrence tests.
write(
    "packages/lifemate_client/test/recurrence_test.dart",
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('visit recurrence every N months is deterministic and clamps month end', () {
    const rule = RecurrenceRule(enabled: true, unit: RecurrenceUnit.month, interval: 1);
    final dates = rule.occurrencesBetween(
      startDate: DateTime(2026, 1, 31),
      fromDate: DateTime(2026, 1, 1),
      toDate: DateTime(2026, 4, 30),
    );
    expect(dates, [
      DateTime(2026, 1, 31),
      DateTime(2026, 2, 28),
      DateTime(2026, 3, 31),
      DateTime(2026, 4, 30),
    ]);
  });

  test('injection recurrence supports every N months', () {
    const rule = RecurrenceRule(enabled: true, unit: RecurrenceUnit.month, interval: 6);
    final dates = rule.occurrencesBetween(
      startDate: DateTime(2026, 8, 17),
      fromDate: DateTime(2026, 8, 1),
      toDate: DateTime(2027, 9, 1),
    );
    expect(dates, [DateTime(2026, 8, 17), DateTime(2027, 2, 17), DateTime(2027, 8, 17)]);
  });

  test('weekly recurrence emits no duplicate dates', () {
    const rule = RecurrenceRule(
      enabled: true,
      unit: RecurrenceUnit.week,
      interval: 2,
      weekdays: {DateTime.monday, DateTime.wednesday},
    );
    final dates = rule.occurrencesBetween(
      startDate: DateTime(2026, 8, 3),
      fromDate: DateTime(2026, 8, 1),
      toDate: DateTime(2026, 9, 30),
    );
    expect(dates.toSet().length, dates.length);
    expect(dates.where((date) => date.weekday == DateTime.monday), isNotEmpty);
    expect(dates.where((date) => date.weekday == DateTime.wednesday), isNotEmpty);
  });
}
''',
)

# Deno pure recurrence tests: no database needed.
write(
    "supabase/functions/lifemate-api/care_events_recurrence_test.ts",
    r'''import { assertEquals } from "jsr:@std/assert@1.0.14";
import { generateCareEventOccurrenceDates } from "./care_events.ts";

Deno.test("appointment every six months expands deterministically", () => {
  assertEquals(
    generateCareEventOccurrenceDates(
      "2026-08-17",
      { enabled: true, unit: "month", interval: 6, weekdays: [], endDate: null },
      "2026-08-01",
      "2027-08-31",
    ),
    ["2026-08-17", "2027-02-17", "2027-08-17"],
  );
});

Deno.test("month end recurrence clamps without duplicate dates", () => {
  const dates = generateCareEventOccurrenceDates(
    "2026-01-31",
    { enabled: true, unit: "month", interval: 1, weekdays: [], endDate: null },
    "2026-01-01",
    "2026-04-30",
  );
  assertEquals(dates, ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"]);
  assertEquals(new Set(dates).size, dates.length);
});

Deno.test("weekly recurrence uses selected weekdays and interval", () => {
  const dates = generateCareEventOccurrenceDates(
    "2026-08-03",
    { enabled: true, unit: "week", interval: 2, weekdays: [1, 3], endDate: "2026-08-31" },
    "2026-08-01",
    "2026-08-31",
  );
  assertEquals(dates, ["2026-08-03", "2026-08-05", "2026-08-17", "2026-08-19", "2026-08-31"]);
  assertEquals(new Set(dates).size, dates.length);
});
''',
)

# Integration regression: a real injection created in the DB appears in the
# owner's aggregate care-event list. Add recurrence payload to legacy fixture is
# unnecessary because absent recurrence remains backwards compatible.
replace_once(
    "supabase/functions/lifemate-api/database_integration_test.ts",
    "      assertEquals(\n        patientEvents[0]?.addressLine,\n        appointmentPayload.addressLine,\n      );",
    "      assertEquals(\n        patientEvents[0]?.addressLine,\n        appointmentPayload.addressLine,\n      );\n\n      const injection = await careEvents.createCareEvent(patient.appUserId, {\n        clientRequestId: crypto.randomUUID(),\n        eventType: 'injection',\n        title: 'B12',\n        medicationName: 'B12',\n        doseText: '1 ampoule',\n        administrationRoute: 'intramuscular',\n        scheduledLocalDate: target.date,\n        scheduledLocalTime: target.localTime,\n        timeZone: 'Asia/Tehran',\n        recurrence: { enabled: true, unit: 'month', interval: 6, weekdays: [] },\n      });\n      const eventsAfterInjection = await careEvents.listCareEvents(\n        patient.appUserId,\n        target.date,\n        target.date,\n      );\n      assert(eventsAfterInjection.some((event) => event.seriesId === injection.id));\n      assert(eventsAfterInjection.some((event) => event.eventType === 'injection'));",
)

Path(__file__).unlink()
workflow = ROOT / ".github/workflows/round2-recurrence-one-shot.yml"
if workflow.exists():
    workflow.unlink()
print("round2 recurrence applied")
