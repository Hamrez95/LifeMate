type Row = Record<string, any>;

type CareEventInput = {
  version: number;
  clientRequestId: string;
  eventType: "Appointment" | "Injection";
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
  patientReminderMinutesBefore: number;
  caregiverReminderMinutesBefore: number;
};

type StoreDependencies = {
  sql: any;
  normalizeCareEvent: (
    body: Record<string, unknown>,
    editing: boolean,
  ) => CareEventInput;
  apiError: (status: number, code: string, message: string) => Error;
};

async function requireSelfPerson(
  sql: any,
  patientAppUserId: string,
  apiError: StoreDependencies["apiError"],
): Promise<string> {
  const rows = await sql`
    select core.self_person_id_for_legacy_app_user(
      ${patientAppUserId}::uuid
    )::text as person_id
  `;
  const personId = rows[0]?.person_id;
  if (typeof personId !== "string" || personId.length === 0) {
    throw apiError(
      409,
      "identity_person_mapping_missing",
      "The patient Person mapping is unavailable.",
    );
  }
  return personId;
}

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}

function dateValue(value: unknown): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}

function timeValue(value: unknown): string {
  return String(value).slice(0, 5);
}

function mapCareEvent(
  row: Row,
  patientAppUserId: string,
): Record<string, unknown> {
  return {
    id: row.id,
    seriesId: row.id,
    // API compatibility projection only; ownership is patient_person_id.
    patientUserId: patientAppUserId,
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
    scheduledLocalDate: dateValue(row.scheduled_local_date),
    scheduledLocalTime: timeValue(row.scheduled_local_time),
    timeZone: row.time_zone,
    patientReminderMinutesBefore: Number(
      row.patient_reminder_minutes_before ?? 30,
    ),
    caregiverReminderMinutesBefore: Number(
      row.caregiver_reminder_minutes_before ?? 60,
    ),
    status: String(row.status).toLowerCase(),
    version: Number(row.version),
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

async function insertAudit(
  sql: any,
  caregiverAppUserId: string,
  action: string,
  eventId: string,
  eventType?: string,
): Promise<void> {
  const metadata = eventType == null ? null : { eventType };
  await sql`
    insert into lifemate.audit_logs
      (id, actor_user_id, action, resource_type, resource_id,
       metadata_json, created_at_utc)
    values
      (${crypto.randomUUID()}::uuid, ${caregiverAppUserId}::uuid, ${action},
       'care_event', ${eventId}::uuid, ${
    metadata == null ? null : JSON.stringify(metadata)
  }::jsonb,
       now())
  `;
}

/**
 * Caregiver-managed Care Event boundary.
 *
 * Relationship consent/permission remains in the existing Care Management
 * route guard for this staged slice. Once authorized, event idempotency,
 * selection and mutation are canonical Person-only. created_by_user_id remains
 * deliberate caregiver provenance; patient AppUser remains only a response
 * projection and resolver input.
 */
export function createPersonCareEventManagementStore(
  dependencies: StoreDependencies,
) {
  const { sql, normalizeCareEvent, apiError } = dependencies;

  async function listCareEvents(
    patientAppUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const patientPersonId = await requireSelfPerson(
      sql,
      patientAppUserId,
      apiError,
    );
    const rows = await sql`
      select *
      from lifemate.care_events
      where patient_person_id = ${patientPersonId}::uuid
        and status <> 'Cancelled'
      order by scheduled_local_date, scheduled_local_time, id
      limit 200
    `;
    return rows.map((row: Row) => mapCareEvent(row, patientAppUserId));
  }

  async function createCareEvent(
    caregiverAppUserId: string,
    patientAppUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const input = normalizeCareEvent(body, false);
    return await sql.begin(async (tx: any) => {
      const patientPersonId = await requireSelfPerson(
        tx,
        patientAppUserId,
        apiError,
      );
      const existing = await tx`
        select *
        from lifemate.care_events
        where patient_person_id = ${patientPersonId}::uuid
          and client_request_id = ${input.clientRequestId}::uuid
        limit 1
      `;
      if (existing[0]) {
        return mapCareEvent(existing[0], patientAppUserId);
      }

      const id = crypto.randomUUID();
      const rows = await tx`
        insert into lifemate.care_events
          (id, patient_person_id, created_by_user_id, client_request_id,
           event_type, title, provider_name, specialty, medication_name,
           dose_text, administration_route, reason, instructions, center_name,
           address_line, phone_number, scheduled_local_date, scheduled_local_time,
           time_zone, recurrence_unit, recurrence_interval, recurrence_weekdays,
           recurrence_end_date, patient_reminder_minutes_before,
           caregiver_reminder_minutes_before, status, version,
           provenance_source, provenance_restricted,
           created_at_utc, updated_at_utc)
        values
          (${id}::uuid, ${patientPersonId}::uuid, ${caregiverAppUserId}::uuid,
           ${input.clientRequestId}::uuid, ${input.eventType}, ${input.title},
           ${input.providerName}, ${input.specialty}, ${input.medicationName},
           ${input.doseText}, ${input.administrationRoute}, ${input.reason},
           ${input.instructions}, ${input.centerName}, ${input.addressLine},
           ${input.phoneNumber}, ${input.scheduledLocalDate}::date,
           ${input.scheduledLocalTime}::time, ${input.timeZone},
           'none', 1, array[]::smallint[], null,
           ${input.patientReminderMinutesBefore},
           ${input.caregiverReminderMinutesBefore},
           'Scheduled', 1, 'CaregiverInput', false, now(), now())
        returning *
      `;
      await insertAudit(
        tx,
        caregiverAppUserId,
        "caregiver.care_event.created",
        id,
        input.eventType,
      );
      return mapCareEvent(rows[0], patientAppUserId);
    });
  }

  async function updateCareEvent(
    caregiverAppUserId: string,
    patientAppUserId: string,
    eventId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const input = normalizeCareEvent(body, true);
    return await sql.begin(async (tx: any) => {
      const patientPersonId = await requireSelfPerson(
        tx,
        patientAppUserId,
        apiError,
      );
      const existingRows = await tx`
        select *
        from lifemate.care_events
        where id = ${eventId}::uuid
          and patient_person_id = ${patientPersonId}::uuid
        for update
      `;
      const existing = existingRows[0];
      if (!existing) {
        throw apiError(
          404,
          "care_event_not_found",
          "Care event was not found.",
        );
      }
      if (Number(existing.version) !== input.version) {
        throw apiError(
          409,
          "stale_care_event",
          "Care event has changed. Refresh and try again.",
        );
      }
      if (String(existing.status) === "Cancelled") {
        throw apiError(
          409,
          "care_event_cancelled",
          "Cancelled event cannot be edited.",
        );
      }

      const rows = await tx`
        update lifemate.care_events
        set event_type = ${input.eventType},
            title = ${input.title},
            provider_name = ${input.providerName},
            specialty = ${input.specialty},
            medication_name = ${input.medicationName},
            dose_text = ${input.doseText},
            administration_route = ${input.administrationRoute},
            reason = ${input.reason},
            instructions = ${input.instructions},
            center_name = ${input.centerName},
            address_line = ${input.addressLine},
            phone_number = ${input.phoneNumber},
            scheduled_local_date = ${input.scheduledLocalDate}::date,
            scheduled_local_time = ${input.scheduledLocalTime}::time,
            time_zone = ${input.timeZone},
            patient_reminder_minutes_before =
              ${input.patientReminderMinutesBefore},
            caregiver_reminder_minutes_before =
              ${input.caregiverReminderMinutesBefore},
            provenance_source = 'CaregiverInput',
            version = version + 1,
            updated_at_utc = now()
        where id = ${eventId}::uuid
          and patient_person_id = ${patientPersonId}::uuid
        returning *
      `;
      if (!rows[0]) {
        throw apiError(
          409,
          "identity_person_mapping_conflict",
          "Care Event ownership changed during the update.",
        );
      }
      await insertAudit(
        tx,
        caregiverAppUserId,
        "caregiver.care_event.updated",
        eventId,
        input.eventType,
      );
      return mapCareEvent(rows[0], patientAppUserId);
    });
  }

  async function cancelCareEvent(
    caregiverAppUserId: string,
    patientAppUserId: string,
    eventId: string,
    expectedVersion: number,
  ): Promise<void> {
    await sql.begin(async (tx: any) => {
      const patientPersonId = await requireSelfPerson(
        tx,
        patientAppUserId,
        apiError,
      );
      const rows = await tx`
        select *
        from lifemate.care_events
        where id = ${eventId}::uuid
          and patient_person_id = ${patientPersonId}::uuid
        for update
      `;
      const event = rows[0];
      if (!event) {
        throw apiError(
          404,
          "care_event_not_found",
          "Care event was not found.",
        );
      }
      if (Number(event.version) !== expectedVersion) {
        throw apiError(
          409,
          "stale_care_event",
          "Care event has changed. Refresh and try again.",
        );
      }
      if (String(event.status) !== "Cancelled") {
        const updated = await tx`
          update lifemate.care_events
          set status = 'Cancelled', completed_at_utc = null,
              provenance_source = 'CaregiverInput',
              version = version + 1, updated_at_utc = now()
          where id = ${eventId}::uuid
            and patient_person_id = ${patientPersonId}::uuid
          returning id
        `;
        if (!updated[0]) {
          throw apiError(
            409,
            "identity_person_mapping_conflict",
            "Care Event ownership changed during cancellation.",
          );
        }
      }
      await insertAudit(
        tx,
        caregiverAppUserId,
        "caregiver.care_event.cancelled",
        eventId,
      );
    });
  }

  return {
    listCareEvents,
    createCareEvent,
    updateCareEvent,
    cancelCareEvent,
  };
}
