import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import postgres from "postgres";
import { normalizeCareManagementPath } from "./path_utils.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_URL");
const supabaseUrl = Deno.env.get("SUPABASE_URL");
const publishableKey = resolvePublishableKey();

if (!databaseUrl || !supabaseUrl || !publishableKey) {
  throw new Error("Required Supabase runtime configuration is missing.");
}

const sql = postgres(databaseUrl, {
  max: 1,
  idle_timeout: 5,
  connect_timeout: 10,
  prepare: false,
});

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, apikey, content-type",
  "access-control-allow-methods": "GET, POST, PATCH, DELETE, OPTIONS",
  "content-type": "application/json; charset=utf-8",
};

class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

type Row = Record<string, any>;

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const correlationId = crypto.randomUUID();
  try {
    const appUserId = await authenticate(request);
    const path = normalizeCareManagementPath(new URL(request.url).pathname);
    return await route(request, path, appUserId);
  } catch (error) {
    if (error instanceof ApiError) {
      return problem(error.status, error.code, error.message, correlationId);
    }
    console.error("LifeMate care management error", {
      correlationId,
      message: error instanceof Error ? error.message : String(error),
    });
    return problem(
      500,
      "internal_error",
      "The care management request could not be completed.",
      correlationId,
    );
  }
});

async function route(
  request: Request,
  path: string,
  appUserId: string,
): Promise<Response> {
  const permissionMatch = path.match(
    /^\/api\/v1\/relationships\/([0-9a-f-]{36})\/health-record-permission$/i,
  );
  if (permissionMatch && request.method === "GET") {
    return json(await getHealthRecordPermission(appUserId, permissionMatch[1]));
  }
  if (permissionMatch && request.method === "PATCH") {
    return json(
      await updateHealthRecordPermission(
        appUserId,
        permissionMatch[1],
        await readObject(request),
      ),
    );
  }

  const plansMatch = path.match(
    /^\/api\/v1\/patients\/([0-9a-f-]{36})\/treatment-plans$/i,
  );
  if (plansMatch && request.method === "GET") {
    await requireManagementAccess(appUserId, plansMatch[1]);
    return json(await listTreatmentPlans(plansMatch[1]));
  }
  if (plansMatch && request.method === "POST") {
    await requireManagementAccess(appUserId, plansMatch[1]);
    return json(
      await createTreatmentPlan(
        appUserId,
        plansMatch[1],
        await readObject(request),
      ),
      201,
    );
  }

  const planMatch = path.match(
    /^\/api\/v1\/patients\/([0-9a-f-]{36})\/treatment-plans\/([0-9a-f-]{36})$/i,
  );
  if (planMatch && request.method === "PATCH") {
    await requireManagementAccess(appUserId, planMatch[1]);
    return json(
      await updateTreatmentPlan(
        appUserId,
        planMatch[1],
        planMatch[2],
        await readObject(request),
      ),
    );
  }
  if (planMatch && request.method === "DELETE") {
    await requireManagementAccess(appUserId, planMatch[1]);
    await archiveTreatmentPlan(
      appUserId,
      planMatch[1],
      planMatch[2],
      await readObject(request),
    );
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const eventsMatch = path.match(
    /^\/api\/v1\/patients\/([0-9a-f-]{36})\/care-events$/i,
  );
  if (eventsMatch && request.method === "GET") {
    await requireManagementAccess(appUserId, eventsMatch[1]);
    return json(await listCareEvents(eventsMatch[1]));
  }
  if (eventsMatch && request.method === "POST") {
    await requireManagementAccess(appUserId, eventsMatch[1]);
    return json(
      await createCareEvent(
        appUserId,
        eventsMatch[1],
        await readObject(request),
      ),
      201,
    );
  }

  const eventMatch = path.match(
    /^\/api\/v1\/patients\/([0-9a-f-]{36})\/care-events\/([0-9a-f-]{36})$/i,
  );
  if (eventMatch && request.method === "PATCH") {
    await requireManagementAccess(appUserId, eventMatch[1]);
    return json(
      await updateCareEvent(
        appUserId,
        eventMatch[1],
        eventMatch[2],
        await readObject(request),
      ),
    );
  }
  if (eventMatch && request.method === "DELETE") {
    await requireManagementAccess(appUserId, eventMatch[1]);
    await cancelCareEvent(
      appUserId,
      eventMatch[1],
      eventMatch[2],
      await readObject(request),
    );
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  throw new ApiError(404, "route_not_found", "API route was not found.");
}

async function authenticate(request: Request): Promise<string> {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ") || authorization.length > 4096) {
    throw new ApiError(
      401,
      "authorization_missing",
      "Authentication is required.",
    );
  }

  let response: Response;
  try {
    response = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        Authorization: authorization,
        apikey: publishableKey!,
      },
      signal: AbortSignal.timeout(10_000),
    });
  } catch {
    throw new ApiError(
      503,
      "identity_provider_unavailable",
      "Authentication service is temporarily unavailable.",
    );
  }
  if (!response.ok) {
    throw new ApiError(
      401,
      "invalid_session",
      "Authentication session is invalid.",
    );
  }
  const user = await response.json() as Record<string, unknown>;
  const authSubject = String(user.id ?? "");
  if (!isUuid(authSubject)) {
    throw new ApiError(
      401,
      "invalid_session",
      "Authentication session is invalid.",
    );
  }
  const rows = await sql`
    select id
    from lifemate.app_users
    where auth_subject = ${authSubject} and status = 'Active'
    limit 1
  `;
  if (!rows[0]) {
    throw new ApiError(404, "not_onboarded", "Bootstrap is required.");
  }
  return String(rows[0].id);
}

async function getHealthRecordPermission(
  requesterUserId: string,
  relationshipId: string,
): Promise<Record<string, unknown>> {
  const rows = await sql`
    select id, patient_user_id, caregiver_user_id, status,
           can_manage_health_record,
           health_record_management_consent_version,
           health_record_management_consented_at_utc,
           health_record_management_revoked_at_utc
    from lifemate.care_relationships
    where id = ${relationshipId}::uuid
      and (
        patient_user_id = ${requesterUserId}::uuid
        or caregiver_user_id = ${requesterUserId}::uuid
      )
    limit 1
  `;
  const row = rows[0];
  if (!row) {
    throw new ApiError(
      404,
      "relationship_not_found",
      "Care relationship was not found.",
    );
  }
  return mapPermission(row);
}

async function updateHealthRecordPermission(
  patientUserId: string,
  relationshipId: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  if (typeof body.canManageHealthRecord !== "boolean") {
    throw new ApiError(
      400,
      "invalid_care_permission",
      "canManageHealthRecord must be a boolean.",
    );
  }
  const enabling = body.canManageHealthRecord === true;
  if (
    enabling &&
    (body.confirmConsent !== true ||
      body.consentVersion !== "health-record-management-consent-v1")
  ) {
    throw new ApiError(
      400,
      "health_record_consent_required",
      "Explicit patient consent is required.",
    );
  }

  return await sql.begin(async (tx) => {
    const existingRows = await tx`
      select *
      from lifemate.care_relationships
      where id = ${relationshipId}::uuid
        and patient_user_id = ${patientUserId}::uuid
        and status = 'Active'
      for update
    `;
    const existing = existingRows[0];
    if (!existing) {
      throw new ApiError(
        404,
        "relationship_not_found",
        "Active owner relationship was not found.",
      );
    }

    const rows = enabling
      ? await tx`
          update lifemate.care_relationships
          set can_manage_health_record = true,
              health_record_management_consent_version =
                'health-record-management-consent-v1',
              health_record_management_consented_at_utc = now(),
              health_record_management_revoked_at_utc = null,
              updated_at_utc = now()
          where id = ${relationshipId}::uuid
          returning *
        `
      : await tx`
          update lifemate.care_relationships
          set can_manage_health_record = false,
              health_record_management_revoked_at_utc = now(),
              updated_at_utc = now()
          where id = ${relationshipId}::uuid
          returning *
        `;

    await insertAudit(
      tx,
      patientUserId,
      enabling
        ? "care_relationship.health_record_management_granted"
        : "care_relationship.health_record_management_revoked",
      "care_relationship",
      relationshipId,
      {
        caregiverUserId: existing.caregiver_user_id,
        consentVersion: enabling ? "health-record-management-consent-v1" : null,
      },
    );
    return mapPermission(rows[0]);
  });
}

async function requireManagementAccess(
  caregiverUserId: string,
  patientUserId: string,
): Promise<Row> {
  if (!isUuid(patientUserId)) {
    throw new ApiError(400, "invalid_patient_id", "patientUserId is invalid.");
  }
  const rows = await sql`
    select *
    from lifemate.care_relationships
    where patient_user_id = ${patientUserId}::uuid
      and caregiver_user_id = ${caregiverUserId}::uuid
      and status = 'Active'
      and can_manage_health_record = true
    limit 1
  `;
  if (!rows[0]) {
    throw new ApiError(
      403,
      "health_record_management_denied",
      "Explicit health record management permission is required.",
    );
  }
  return rows[0];
}

async function listTreatmentPlans(
  patientUserId: string,
): Promise<Record<string, unknown>[]> {
  const plans = await sql`
    select p.*, m.name as medication_name, m.strength_text, m.form,
           m.notes as medication_notes, m.version as medication_version
    from lifemate.treatment_plans p
    join lifemate.medications m on m.id = p.medication_id
    where p.patient_user_id = ${patientUserId}::uuid
      and p.status <> 'Archived'
    order by p.updated_at_utc desc, p.id
    limit 100
  `;
  if (plans.length === 0) return [];
  const ids = plans.map((row) => row.id);
  const schedules = await sql`
    select *
    from lifemate.treatment_schedules
    where treatment_plan_id in ${sql(ids)}
    order by day_of_week, local_time
  `;
  return plans.map((plan) =>
    mapTreatmentPlan(
      plan,
      schedules.filter((schedule) => schedule.treatment_plan_id === plan.id),
    )
  );
}

async function createTreatmentPlan(
  caregiverUserId: string,
  patientUserId: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const input = normalizeTreatment(body, false);
  return await sql.begin(async (tx) => {
    const medicationId = crypto.randomUUID();
    const planId = crypto.randomUUID();
    const now = new Date();

    const medicationRows = await tx`
      insert into lifemate.medications
        (id, owner_user_id, name, strength_text, form, notes, version,
         provenance_source, provenance_restricted,
         created_at_utc, updated_at_utc)
      values
        (${medicationId}::uuid, ${patientUserId}::uuid, ${input.medicationName},
         ${input.strengthText}, ${input.form}, null, 1,
         'CaregiverInput', false, ${now}, ${now})
      returning *
    `;

    const planRows = await tx`
      insert into lifemate.treatment_plans
        (id, patient_user_id, medication_id, dose_text, instructions,
         start_date, end_date, time_zone,
         patient_reminder_minutes_before, caregiver_reminder_minutes_before,
         status, version, provenance_source, provenance_restricted,
         created_at_utc, updated_at_utc)
      values
        (${planId}::uuid, ${patientUserId}::uuid, ${medicationId}::uuid,
         ${input.doseText}, ${input.instructions}, ${input.startDate}::date,
         ${input.endDate}::date, ${input.timeZone},
         ${input.patientReminderMinutesBefore},
         ${input.caregiverReminderMinutesBefore},
         'Active', 1, 'CaregiverInput', false, ${now}, ${now})
      returning *
    `;

    const schedules = [];
    for (const schedule of input.schedules) {
      const rows = await tx`
        insert into lifemate.treatment_schedules
          (id, treatment_plan_id, day_of_week, local_time, created_at_utc)
        values
          (${crypto.randomUUID()}::uuid, ${planId}::uuid,
           ${schedule.dayOfWeek}, ${schedule.localTime}::time, ${now})
        returning *
      `;
      schedules.push(rows[0]);
    }

    await insertAudit(
      tx,
      caregiverUserId,
      "caregiver.treatment_plan.created",
      "treatment_plan",
      planId,
      { patientUserId },
    );
    return mapTreatmentPlan(
      {
        ...planRows[0],
        medication_name: medicationRows[0].name,
        strength_text: medicationRows[0].strength_text,
        form: medicationRows[0].form,
        medication_notes: medicationRows[0].notes,
        medication_version: medicationRows[0].version,
      },
      schedules,
    );
  });
}

async function updateTreatmentPlan(
  caregiverUserId: string,
  patientUserId: string,
  treatmentPlanId: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const input = normalizeTreatment(body, true);
  return await sql.begin(async (tx) => {
    const existingRows = await tx`
      select p.*, m.name as medication_name, m.strength_text, m.form,
             m.version as medication_version
      from lifemate.treatment_plans p
      join lifemate.medications m on m.id = p.medication_id
      where p.id = ${treatmentPlanId}::uuid
        and p.patient_user_id = ${patientUserId}::uuid
      for update of p, m
    `;
    const existing = existingRows[0];
    if (!existing) {
      throw new ApiError(
        404,
        "treatment_plan_not_found",
        "Treatment plan was not found.",
      );
    }
    if (Number(existing.version) !== input.version) {
      throw new ApiError(
        409,
        "stale_treatment_plan",
        "Treatment plan has changed. Refresh and try again.",
      );
    }
    if (Number(existing.medication_version) !== input.medicationVersion) {
      throw new ApiError(
        409,
        "stale_medication",
        "Medication has changed. Refresh and try again.",
      );
    }

    const medicationRows = await tx`
      update lifemate.medications
      set name = ${input.medicationName},
          strength_text = ${input.strengthText},
          form = ${input.form},
          provenance_source = 'CaregiverInput',
          version = version + 1,
          updated_at_utc = now()
      where id = ${existing.medication_id}::uuid
        and owner_user_id = ${patientUserId}::uuid
      returning *
    `;
    const planRows = await tx`
      update lifemate.treatment_plans
      set dose_text = ${input.doseText},
          instructions = ${input.instructions},
          start_date = ${input.startDate}::date,
          end_date = ${input.endDate}::date,
          time_zone = ${input.timeZone},
          patient_reminder_minutes_before = ${input.patientReminderMinutesBefore},
          caregiver_reminder_minutes_before = ${input.caregiverReminderMinutesBefore},
          status = ${input.status},
          provenance_source = 'CaregiverInput',
          version = version + 1,
          updated_at_utc = now()
      where id = ${treatmentPlanId}::uuid
      returning *
    `;

    await tx`
      delete from lifemate.dose_occurrences
      where treatment_plan_id = ${treatmentPlanId}::uuid
        and status in ('Scheduled', 'Missed')
        and scheduled_at_utc >= now()
    `;
    await tx`
      delete from lifemate.treatment_schedules
      where treatment_plan_id = ${treatmentPlanId}::uuid
    `;

    const schedules = [];
    for (const schedule of input.schedules) {
      const rows = await tx`
        insert into lifemate.treatment_schedules
          (id, treatment_plan_id, day_of_week, local_time, created_at_utc)
        values
          (${crypto.randomUUID()}::uuid, ${treatmentPlanId}::uuid,
           ${schedule.dayOfWeek}, ${schedule.localTime}::time, now())
        returning *
      `;
      schedules.push(rows[0]);
    }

    await insertAudit(
      tx,
      caregiverUserId,
      "caregiver.treatment_plan.updated",
      "treatment_plan",
      treatmentPlanId,
      { patientUserId },
    );
    return mapTreatmentPlan(
      {
        ...planRows[0],
        medication_name: medicationRows[0].name,
        strength_text: medicationRows[0].strength_text,
        form: medicationRows[0].form,
        medication_notes: medicationRows[0].notes,
        medication_version: medicationRows[0].version,
      },
      schedules,
    );
  });
}

async function archiveTreatmentPlan(
  caregiverUserId: string,
  patientUserId: string,
  treatmentPlanId: string,
  body: Record<string, unknown>,
): Promise<void> {
  const expectedVersion = requiredPositiveInt(body.version, "version");
  await sql.begin(async (tx) => {
    const rows = await tx`
      select *
      from lifemate.treatment_plans
      where id = ${treatmentPlanId}::uuid
        and patient_user_id = ${patientUserId}::uuid
      for update
    `;
    const plan = rows[0];
    if (!plan) {
      throw new ApiError(
        404,
        "treatment_plan_not_found",
        "Treatment plan was not found.",
      );
    }
    if (Number(plan.version) !== expectedVersion) {
      throw new ApiError(
        409,
        "stale_treatment_plan",
        "Treatment plan has changed. Refresh and try again.",
      );
    }
    await tx`
      update lifemate.treatment_plans
      set status = 'Archived', version = version + 1,
          provenance_source = 'CaregiverInput', updated_at_utc = now()
      where id = ${treatmentPlanId}::uuid
    `;
    await tx`
      delete from lifemate.dose_occurrences
      where treatment_plan_id = ${treatmentPlanId}::uuid
        and status in ('Scheduled', 'Missed')
        and scheduled_at_utc >= now()
    `;
    await insertAudit(
      tx,
      caregiverUserId,
      "caregiver.treatment_plan.archived",
      "treatment_plan",
      treatmentPlanId,
      { patientUserId },
    );
  });
}

async function listCareEvents(
  patientUserId: string,
): Promise<Record<string, unknown>[]> {
  const rows = await sql`
    select *
    from lifemate.care_events
    where patient_user_id = ${patientUserId}::uuid
      and status <> 'Cancelled'
    order by scheduled_local_date, scheduled_local_time, id
    limit 200
  `;
  return rows.map((row) => mapCareEvent(row));
}

async function createCareEvent(
  caregiverUserId: string,
  patientUserId: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const input = normalizeCareEvent(body, false);
  return await sql.begin(async (tx) => {
    const existing = await tx`
      select *
      from lifemate.care_events
      where patient_user_id = ${patientUserId}::uuid
        and client_request_id = ${input.clientRequestId}::uuid
      limit 1
    `;
    if (existing[0]) return mapCareEvent(existing[0]);

    const id = crypto.randomUUID();
    const rows = await tx`
      insert into lifemate.care_events
        (id, patient_user_id, created_by_user_id, client_request_id,
         event_type, title, provider_name, specialty, medication_name,
         dose_text, administration_route, reason, instructions, center_name,
         address_line, phone_number, scheduled_local_date, scheduled_local_time,
         time_zone, recurrence_unit, recurrence_interval, recurrence_weekdays,
         recurrence_end_date, patient_reminder_minutes_before,
         caregiver_reminder_minutes_before, status, version,
         provenance_source, provenance_restricted,
         created_at_utc, updated_at_utc)
      values
        (${id}::uuid, ${patientUserId}::uuid, ${caregiverUserId}::uuid,
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
      caregiverUserId,
      "caregiver.care_event.created",
      "care_event",
      id,
      { patientUserId, eventType: input.eventType },
    );
    return mapCareEvent(rows[0]);
  });
}

async function updateCareEvent(
  caregiverUserId: string,
  patientUserId: string,
  eventId: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const input = normalizeCareEvent(body, true);
  return await sql.begin(async (tx) => {
    const existingRows = await tx`
      select *
      from lifemate.care_events
      where id = ${eventId}::uuid
        and patient_user_id = ${patientUserId}::uuid
      for update
    `;
    const existing = existingRows[0];
    if (!existing) {
      throw new ApiError(
        404,
        "care_event_not_found",
        "Care event was not found.",
      );
    }
    if (Number(existing.version) !== input.version) {
      throw new ApiError(
        409,
        "stale_care_event",
        "Care event has changed. Refresh and try again.",
      );
    }
    if (String(existing.status) === "Cancelled") {
      throw new ApiError(
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
          patient_reminder_minutes_before = ${input.patientReminderMinutesBefore},
          caregiver_reminder_minutes_before = ${input.caregiverReminderMinutesBefore},
          provenance_source = 'CaregiverInput',
          version = version + 1,
          updated_at_utc = now()
      where id = ${eventId}::uuid
      returning *
    `;
    await insertAudit(
      tx,
      caregiverUserId,
      "caregiver.care_event.updated",
      "care_event",
      eventId,
      { patientUserId, eventType: input.eventType },
    );
    return mapCareEvent(rows[0]);
  });
}

async function cancelCareEvent(
  caregiverUserId: string,
  patientUserId: string,
  eventId: string,
  body: Record<string, unknown>,
): Promise<void> {
  const expectedVersion = requiredPositiveInt(body.version, "version");
  await sql.begin(async (tx) => {
    const rows = await tx`
      select *
      from lifemate.care_events
      where id = ${eventId}::uuid
        and patient_user_id = ${patientUserId}::uuid
      for update
    `;
    const event = rows[0];
    if (!event) {
      throw new ApiError(
        404,
        "care_event_not_found",
        "Care event was not found.",
      );
    }
    if (Number(event.version) !== expectedVersion) {
      throw new ApiError(
        409,
        "stale_care_event",
        "Care event has changed. Refresh and try again.",
      );
    }
    if (String(event.status) !== "Cancelled") {
      await tx`
        update lifemate.care_events
        set status = 'Cancelled', completed_at_utc = null,
            provenance_source = 'CaregiverInput',
            version = version + 1, updated_at_utc = now()
        where id = ${eventId}::uuid
      `;
    }
    await insertAudit(
      tx,
      caregiverUserId,
      "caregiver.care_event.cancelled",
      "care_event",
      eventId,
      { patientUserId },
    );
  });
}

type TreatmentInput = {
  version: number;
  medicationVersion: number;
  medicationName: string;
  strengthText: string | null;
  form: string | null;
  doseText: string;
  instructions: string | null;
  startDate: string;
  endDate: string | null;
  timeZone: string;
  schedules: Array<{ dayOfWeek: string; localTime: string }>;
  patientReminderMinutesBefore: number;
  caregiverReminderMinutesBefore: number;
  status: "Active" | "Stopped";
};

function normalizeTreatment(
  body: Record<string, unknown>,
  editing: boolean,
): TreatmentInput {
  const startDate = requiredDate(body.startDate, "startDate");
  const endDate = body.endDate == null || body.endDate === ""
    ? null
    : requiredDate(body.endDate, "endDate");
  if (endDate && endDate < startDate) {
    throw new ApiError(
      400,
      "invalid_treatment_plan",
      "End date cannot precede start date.",
    );
  }
  const schedules = normalizeSchedules(body.schedules);
  return {
    version: editing ? requiredPositiveInt(body.version, "version") : 1,
    medicationVersion: editing
      ? requiredPositiveInt(body.medicationVersion, "medicationVersion")
      : 1,
    medicationName: requiredText(body.medicationName, "medicationName", 120),
    strengthText: optionalText(body.strengthText, 80),
    form: optionalText(body.form, 50),
    doseText: requiredText(body.doseText, "doseText", 80),
    instructions: optionalText(body.instructions, 500),
    startDate,
    endDate,
    timeZone: requiredText(body.timeZone, "timeZone", 80),
    schedules,
    patientReminderMinutesBefore: reminderMinutes(
      body.patientReminderMinutesBefore,
      30,
    ),
    caregiverReminderMinutesBefore: reminderMinutes(
      body.caregiverReminderMinutesBefore,
      60,
    ),
    status: treatmentStatus(body.status),
  };
}

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

function normalizeCareEvent(
  body: Record<string, unknown>,
  editing: boolean,
): CareEventInput {
  const eventType = normalizeEventType(body.eventType);
  const title = requiredText(body.title, "title", 160);
  const medicationName = optionalText(body.medicationName, 160);
  if (eventType === "Injection" && !medicationName) {
    throw new ApiError(
      400,
      "invalid_medicationName",
      "medicationName is required for injection events.",
    );
  }
  return {
    version: editing ? requiredPositiveInt(body.version, "version") : 1,
    clientRequestId: editing
      ? crypto.randomUUID()
      : requiredUuid(body.clientRequestId, "clientRequestId"),
    eventType,
    title,
    providerName: optionalText(body.providerName, 160),
    specialty: optionalText(body.specialty, 120),
    medicationName,
    doseText: optionalText(body.doseText, 120),
    administrationRoute: normalizeAdministrationRoute(body.administrationRoute),
    reason: optionalText(body.reason, 500),
    instructions: optionalText(body.instructions, 1000),
    centerName: optionalText(body.centerName, 200),
    addressLine: optionalText(body.addressLine, 500),
    phoneNumber: optionalText(body.phoneNumber, 40),
    scheduledLocalDate: requiredDate(
      body.scheduledLocalDate,
      "scheduledLocalDate",
    ),
    scheduledLocalTime: requiredLocalTime(
      body.scheduledLocalTime,
      "scheduledLocalTime",
    ),
    timeZone: requiredText(body.timeZone, "timeZone", 80),
    patientReminderMinutesBefore: reminderMinutes(
      body.patientReminderMinutesBefore,
      30,
    ),
    caregiverReminderMinutesBefore: reminderMinutes(
      body.caregiverReminderMinutesBefore,
      60,
    ),
  };
}

function mapPermission(row: Row): Record<string, unknown> {
  return {
    relationshipId: row.id,
    patientUserId: row.patient_user_id,
    caregiverUserId: row.caregiver_user_id,
    status: String(row.status).toLowerCase(),
    canManageHealthRecord: row.can_manage_health_record === true,
    consentVersion: row.health_record_management_consent_version ?? null,
    consentedAtUtc: row.health_record_management_consented_at_utc == null
      ? null
      : iso(row.health_record_management_consented_at_utc),
    revokedAtUtc: row.health_record_management_revoked_at_utc == null
      ? null
      : iso(row.health_record_management_revoked_at_utc),
  };
}

function mapTreatmentPlan(
  row: Row,
  schedules: Row[],
): Record<string, unknown> {
  return {
    id: row.id,
    patientUserId: row.patient_user_id,
    medication: {
      id: row.medication_id,
      name: row.medication_name,
      strengthText: row.strength_text,
      form: row.form,
      notes: row.medication_notes,
      version: Number(row.medication_version ?? 1),
    },
    doseText: row.dose_text,
    instructions: row.instructions,
    startDate: dateValue(row.start_date),
    endDate: row.end_date == null ? null : dateValue(row.end_date),
    timeZone: row.time_zone,
    schedules: schedules.map((schedule) => ({
      id: schedule.id,
      dayOfWeek: schedule.day_of_week,
      localTime: timeValue(schedule.local_time),
    })),
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

function mapCareEvent(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    seriesId: row.id,
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

function normalizeSchedules(
  value: unknown,
): Array<{ dayOfWeek: string; localTime: string }> {
  if (!Array.isArray(value) || value.length === 0 || value.length > 28) {
    throw new ApiError(
      400,
      "invalid_schedules",
      "At least one treatment schedule is required.",
    );
  }
  const allowedDays = new Set([
    "sunday",
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
  ]);
  const seen = new Set<string>();
  return value.map((raw) => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      throw new ApiError(400, "invalid_schedules", "Schedule is invalid.");
    }
    const record = raw as Record<string, unknown>;
    const dayOfWeek = String(record.dayOfWeek ?? "").trim().toLowerCase();
    if (!allowedDays.has(dayOfWeek)) {
      throw new ApiError(400, "invalid_schedules", "Schedule day is invalid.");
    }
    const localTime = requiredLocalTime(record.localTime, "localTime");
    const key = `${dayOfWeek}:${localTime}`;
    if (seen.has(key)) {
      throw new ApiError(400, "invalid_schedules", "Duplicate schedule.");
    }
    seen.add(key);
    return { dayOfWeek, localTime };
  });
}

function normalizeEventType(value: unknown): "Appointment" | "Injection" {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (normalized === "appointment" || normalized === "visit") {
    return "Appointment";
  }
  if (normalized === "injection") return "Injection";
  throw new ApiError(400, "invalid_eventType", "Unsupported care event type.");
}

function normalizeAdministrationRoute(value: unknown): string | null {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (!normalized) return null;
  const aliases: Record<string, string> = {
    intramuscular: "Intramuscular",
    subcutaneous: "Subcutaneous",
    intravenous: "Intravenous",
    other: "Other",
  };
  const result = aliases[normalized];
  if (!result) {
    throw new ApiError(
      400,
      "invalid_administrationRoute",
      "Unsupported administration route.",
    );
  }
  return result;
}

function treatmentStatus(value: unknown): "Active" | "Stopped" {
  const normalized = String(value ?? "active").trim().toLowerCase();
  if (normalized === "active") return "Active";
  if (normalized === "stopped" || normalized === "paused") return "Stopped";
  throw new ApiError(
    400,
    "invalid_treatment_status",
    "Treatment status is invalid.",
  );
}

function reminderMinutes(value: unknown, fallback: number): number {
  if (value == null || value === "") return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 10080) {
    throw new ApiError(
      400,
      "invalid_reminder",
      "Reminder lead time must be between 0 and 10080 minutes.",
    );
  }
  return parsed;
}

function requiredUuid(value: unknown, field: string): string {
  const normalized = String(value ?? "").trim();
  if (!isUuid(normalized)) {
    throw new ApiError(400, `invalid_${field}`, `${field} must be a UUID.`);
  }
  return normalized;
}

function requiredPositiveInt(value: unknown, field: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) {
    throw new ApiError(400, `invalid_${field}`, `${field} must be positive.`);
  }
  return parsed;
}

function requiredText(value: unknown, field: string, maximum: number): string {
  const normalized = String(value ?? "").trim();
  if (!normalized || normalized.length > maximum) {
    throw new ApiError(400, `invalid_${field}`, `${field} is invalid.`);
  }
  return normalized;
}

function optionalText(value: unknown, maximum: number): string | null {
  if (value == null) return null;
  const normalized = String(value).trim();
  if (!normalized) return null;
  if (normalized.length > maximum) {
    throw new ApiError(400, "invalid_text", "Text value is too long.");
  }
  return normalized;
}

function requiredDate(value: unknown, field: string): string {
  const normalized = String(value ?? "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(normalized)) {
    throw new ApiError(400, `invalid_${field}`, `${field} must be YYYY-MM-DD.`);
  }
  const date = new Date(`${normalized}T00:00:00.000Z`);
  if (
    Number.isNaN(date.getTime()) ||
    date.toISOString().slice(0, 10) !== normalized
  ) {
    throw new ApiError(400, `invalid_${field}`, `${field} is invalid.`);
  }
  return normalized;
}

function requiredLocalTime(value: unknown, field: string): string {
  const match = /^(\d{2}):(\d{2})(?::\d{2})?$/.exec(
    String(value ?? "").trim(),
  );
  if (!match || Number(match[1]) > 23 || Number(match[2]) > 59) {
    throw new ApiError(400, `invalid_${field}`, `${field} must be HH:mm.`);
  }
  return `${match[1]}:${match[2]}`;
}

async function readObject(request: Request): Promise<Record<string, unknown>> {
  if (!request.body) return {};
  let value: unknown;
  try {
    value = await request.json();
  } catch {
    throw new ApiError(400, "invalid_json", "Request body must be valid JSON.");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(400, "invalid_json", "Request body must be an object.");
  }
  return value as Record<string, unknown>;
}

async function insertAudit(
  connection: any,
  actorUserId: string,
  action: string,
  resourceType: string,
  resourceId: string,
  metadata: Record<string, unknown>,
): Promise<void> {
  await connection`
    insert into lifemate.audit_logs
      (id, actor_user_id, action, resource_type, resource_id,
       metadata_json, created_at_utc)
    values
      (${crypto.randomUUID()}::uuid, ${actorUserId}::uuid, ${action},
       ${resourceType}, ${resourceId}::uuid, ${JSON.stringify(metadata)}::jsonb,
       now())
  `;
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: corsHeaders });
}

function problem(
  status: number,
  code: string,
  message: string,
  correlationId: string,
): Response {
  return json({ code, message, correlationId }, status);
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
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

function resolvePublishableKey(): string | null {
  const raw = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      if (typeof parsed.default === "string" && parsed.default.length > 0) {
        return parsed.default;
      }
    } catch {
      // Fall through to the legacy anon key.
    }
  }
  return Deno.env.get("SUPABASE_ANON_KEY") ?? null;
}
