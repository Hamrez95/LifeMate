import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import postgres from "postgres";
import {
  type CareManagementIdentity,
  createCareManagementIdempotencyStore,
  requireCareManagementIdempotencyKey,
  resolveCareManagementIdempotencySecret,
  shouldProtectCareManagementMutation,
} from "./idempotency.ts";
import { normalizeCareManagementPath } from "./path_utils.ts";
import { createPersonCareEventManagementStore } from "./person_care_event_management.ts";
import { createPersonTreatmentManagementStore } from "./person_treatment_management.ts";

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
  "access-control-allow-headers":
    "authorization, apikey, content-type, idempotency-key",
  "access-control-allow-methods": "GET, POST, PATCH, DELETE, OPTIONS",
  "access-control-expose-headers": "Retry-After, X-Idempotency-Replayed",
  "content-type": "application/json; charset=utf-8",
};

const idempotencySecret = await resolveCareManagementIdempotencySecret(sql);
const mutationIdempotency = createCareManagementIdempotencyStore(
  sql,
  idempotencySecret,
  corsHeaders,
);

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

const storeDependencies = {
  sql,
  apiError: (status: number, code: string, message: string) =>
    new ApiError(status, code, message),
};
const personTreatmentManagement = createPersonTreatmentManagementStore({
  ...storeDependencies,
  normalizeTreatment,
});
const personCareEventManagement = createPersonCareEventManagementStore({
  ...storeDependencies,
  normalizeCareEvent,
});

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const correlationId = crypto.randomUUID();
  try {
    const identity = await authenticate(request);
    const path = normalizeCareManagementPath(new URL(request.url).pathname);
    return await routeWithIdempotency(request, path, identity);
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

async function routeWithIdempotency(
  request: Request,
  path: string,
  identity: CareManagementIdentity,
): Promise<Response> {
  if (!shouldProtectCareManagementMutation(request.method, path)) {
    return await route(request, path, identity.appUserId);
  }

  let idempotencyKey: string;
  try {
    idempotencyKey = requireCareManagementIdempotencyKey(request);
  } catch (error) {
    throw mapIdempotencyError(error);
  }
  const body = await request.text();
  const replayableRequest = new Request(request.url, {
    method: request.method,
    headers: request.headers,
    body: body.length === 0 ? undefined : body,
  });

  try {
    return await mutationIdempotency.execute(
      identity.authSubject,
      `care-management:${request.method} ${path}`,
      idempotencyKey,
      body,
      () => route(replayableRequest, path, identity.appUserId),
    );
  } catch (error) {
    throw mapIdempotencyError(error);
  }
}

function mapIdempotencyError(error: unknown): Error {
  const code = error instanceof Error ? error.message : "";
  switch (code) {
    case "idempotency_key_required":
      return new ApiError(
        400,
        code,
        "A valid Idempotency-Key header is required for this mutation.",
      );
    case "idempotency_key_reused":
      return new ApiError(
        409,
        code,
        "Idempotency-Key was already used with a different request payload.",
      );
    case "idempotency_in_progress":
      return new ApiError(
        409,
        code,
        "A matching mutation is already being processed. Retry shortly.",
      );
    case "idempotency_state_unavailable":
      return new ApiError(
        503,
        code,
        "Mutation retry state is temporarily unavailable.",
      );
    case "idempotency_response_too_large":
      return new ApiError(
        500,
        code,
        "Mutation response exceeded the replay safety limit.",
      );
    default:
      return error instanceof Error ? error : new Error("idempotency_error");
  }
}

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
    return json(
      await personTreatmentManagement.listTreatmentPlans(plansMatch[1]),
    );
  }
  if (plansMatch && request.method === "POST") {
    await requireManagementAccess(appUserId, plansMatch[1]);
    return json(
      await personTreatmentManagement.createTreatmentPlan(
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
      await personTreatmentManagement.updateTreatmentPlan(
        appUserId,
        planMatch[1],
        planMatch[2],
        await readObject(request),
      ),
    );
  }
  if (planMatch && request.method === "DELETE") {
    await requireManagementAccess(appUserId, planMatch[1]);
    const body = await readObject(request);
    await personTreatmentManagement.archiveTreatmentPlan(
      appUserId,
      planMatch[1],
      planMatch[2],
      requiredPositiveInt(body.version, "version"),
    );
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const eventsMatch = path.match(
    /^\/api\/v1\/patients\/([0-9a-f-]{36})\/care-events$/i,
  );
  if (eventsMatch && request.method === "GET") {
    await requireManagementAccess(appUserId, eventsMatch[1]);
    return json(
      await personCareEventManagement.listCareEvents(eventsMatch[1]),
    );
  }
  if (eventsMatch && request.method === "POST") {
    await requireManagementAccess(appUserId, eventsMatch[1]);
    return json(
      await personCareEventManagement.createCareEvent(
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
      await personCareEventManagement.updateCareEvent(
        appUserId,
        eventMatch[1],
        eventMatch[2],
        await readObject(request),
      ),
    );
  }
  if (eventMatch && request.method === "DELETE") {
    await requireManagementAccess(appUserId, eventMatch[1]);
    const body = await readObject(request);
    await personCareEventManagement.cancelCareEvent(
      appUserId,
      eventMatch[1],
      eventMatch[2],
      requiredPositiveInt(body.version, "version"),
    );
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  throw new ApiError(404, "route_not_found", "API route was not found.");
}

async function authenticate(
  request: Request,
): Promise<CareManagementIdentity> {
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
  return { authSubject, appUserId: String(rows[0].id) };
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
