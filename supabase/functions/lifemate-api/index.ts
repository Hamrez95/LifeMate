import postgres from "postgres";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

const databaseUrl = Deno.env.get("SUPABASE_DB_URL");
const supabaseUrl = Deno.env.get("SUPABASE_URL");
const publishableKeys = readKeyDictionary("SUPABASE_PUBLISHABLE_KEYS");
const secretKeys = readKeyDictionary("SUPABASE_SECRET_KEYS");
const publishableKey = publishableKeys.default ??
  Deno.env.get("SUPABASE_ANON_KEY");
const hashingSecret = secretKeys.default ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!databaseUrl || !supabaseUrl || !publishableKey || !hashingSecret) {
  throw new Error("Required Supabase runtime configuration is missing.");
}

const sql = postgres(databaseUrl, {
  max: 1,
  idle_timeout: 20,
  connect_timeout: 10,
  prepare: false,
});

type AuthUser = {
  id: string;
  email: string | null;
  phone: string | null;
  user_metadata?: Record<string, unknown>;
};

type AppIdentity = {
  auth: AuthUser;
  appUserId: string;
};

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const path = normalizePath(new URL(request.url).pathname);
  if (request.method === "GET" && path === "/health") {
    try {
      await sql`select 1`;
      return json({ status: "ok", database: "ready" });
    } catch (error) {
      console.error("LifeMate health check failed", safeError(error));
      return problem(503, "database_unavailable", "Database is not ready.");
    }
  }

  try {
    const auth = await authenticate(request);
    return await route(request, path, auth);
  } catch (error) {
    if (error instanceof ApiError) {
      return problem(error.status, error.code, error.message);
    }
    console.error("Unhandled LifeMate API error", safeError(error));
    return problem(500, "internal_error", "The request could not be completed.");
  }
});

async function route(
  request: Request,
  path: string,
  auth: AuthUser,
): Promise<Response> {
  if (request.method === "POST" && path === "/api/v1/users/bootstrap") {
    return json(await bootstrapUser(auth, await readBody(request)));
  }

  const identity = await requireIdentity(auth);

  if (request.method === "GET" && path === "/api/v1/me") {
    return json(await currentUser(identity));
  }
  if (request.method === "GET" && path === "/api/v1/medications") {
    return json(await listMedications(identity.appUserId));
  }
  if (request.method === "POST" && path === "/api/v1/medications") {
    return json(
      await createMedication(identity.appUserId, await readBody(request)),
      201,
    );
  }
  if (request.method === "GET" && path === "/api/v1/treatment-plans") {
    return json(await listTreatmentPlans(identity.appUserId));
  }
  if (request.method === "POST" && path === "/api/v1/treatment-plans") {
    return json(
      await createTreatmentPlan(identity.appUserId, await readBody(request)),
      201,
    );
  }
  if (request.method === "GET" && path === "/api/v1/dose-occurrences") {
    const url = new URL(request.url);
    const fromDate = requiredDate(url.searchParams.get("fromDate"), "fromDate");
    const toDate = requiredDate(url.searchParams.get("toDate"), "toDate");
    validateRange(fromDate, toDate);
    await materializeOccurrences(identity.appUserId, fromDate, toDate);
    return json(
      await listDoseOccurrences(identity.appUserId, fromDate, toDate),
    );
  }

  const reportMatch = path.match(
    /^\/api\/v1\/dose-occurrences\/([0-9a-f-]{36})\/report$/i,
  );
  if (request.method === "POST" && reportMatch) {
    return json(
      await reportDose(
        identity.appUserId,
        reportMatch[1],
        await readBody(request),
      ),
    );
  }

  if (request.method === "GET" && path === "/api/v1/care/invitations") {
    return json(await listInvitations(identity.appUserId));
  }
  if (request.method === "POST" && path === "/api/v1/care/invitations") {
    return json(
      await createInvitation(identity, await readBody(request)),
      201,
    );
  }
  if (
    request.method === "POST" &&
    path === "/api/v1/care/invitations/accept"
  ) {
    return json(
      await acceptInvitation(identity, await readBody(request)),
    );
  }
  if (request.method === "GET" && path === "/api/v1/care/relationships") {
    return json(await listRelationships(identity.appUserId));
  }

  const relationshipMatch = path.match(
    /^\/api\/v1\/care\/relationships\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "DELETE" && relationshipMatch) {
    await revokeRelationship(identity.appUserId, relationshipMatch[1]);
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const careDoseMatch = path.match(
    /^\/api\/v1\/care\/patients\/([0-9a-f-]{36})\/dose-occurrences$/i,
  );
  if (request.method === "GET" && careDoseMatch) {
    const url = new URL(request.url);
    const fromDate = requiredDate(url.searchParams.get("fromDate"), "fromDate");
    const toDate = requiredDate(url.searchParams.get("toDate"), "toDate");
    validateRange(fromDate, toDate);
    const patientUserId = careDoseMatch[1];
    await requireCareAccess(identity.appUserId, patientUserId);
    await materializeOccurrences(patientUserId, fromDate, toDate);
    return json(
      await listCareDoseOccurrences(patientUserId, fromDate, toDate),
    );
  }

  throw new ApiError(404, "route_not_found", "API route was not found.");
}

async function authenticate(request: Request): Promise<AuthUser> {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    throw new ApiError(401, "authorization_missing", "Authentication is required.");
  }

  const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      Authorization: authorization,
      apikey: publishableKey!,
    },
  });
  if (!response.ok) {
    throw new ApiError(401, "invalid_session", "Authentication session is invalid.");
  }

  const value = await response.json();
  if (!value?.id) {
    throw new ApiError(401, "invalid_session", "Authentication session is invalid.");
  }
  return {
    id: value.id,
    email: normalizeOptional(value.email)?.toLowerCase() ?? null,
    phone: normalizeOptional(value.phone),
    user_metadata: value.user_metadata ?? {},
  };
}

async function bootstrapUser(
  auth: AuthUser,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const now = new Date();
  const requestedName = normalizeOptional(body.displayName);
  const metadataName = normalizeOptional(auth.user_metadata?.display_name);
  const fallbackName = auth.email?.split("@")[0] ?? "LifeMate User";
  const displayName = (requestedName ?? metadataName ?? fallbackName).slice(0, 120);
  const locale = (normalizeOptional(body.locale) ?? "fa").slice(0, 16);
  const timeZone = (normalizeOptional(body.timeZone) ?? "Asia/Tehran").slice(0, 64);
  const email = auth.email ?? normalizeOptional(body.email)?.toLowerCase() ?? null;

  return await sql.begin(async (tx) => {
    const users = await tx`
      insert into lifemate.app_users
        (id, auth_subject, status, created_at_utc, updated_at_utc)
      values
        (${crypto.randomUUID()}, ${auth.id}, 'Active', ${now}, ${now})
      on conflict (auth_subject) do update
        set updated_at_utc = excluded.updated_at_utc
      returning id, auth_subject, status, created_at_utc, updated_at_utc
    `;
    const user = users[0];

    const profiles = await tx`
      insert into lifemate.user_profiles
        (id, user_id, display_name, phone_number, email, locale, time_zone,
         created_at_utc, updated_at_utc)
      values
        (${crypto.randomUUID()}, ${user.id}, ${displayName}, ${auth.phone},
         ${email}, ${locale}, ${timeZone}, ${now}, ${now})
      on conflict (user_id) do update set
        email = coalesce(excluded.email, lifemate.user_profiles.email),
        phone_number = coalesce(excluded.phone_number, lifemate.user_profiles.phone_number),
        updated_at_utc = excluded.updated_at_utc
      returning id, user_id, display_name, phone_number, email, locale,
                time_zone, created_at_utc, updated_at_utc
    `;
    return mapCurrentUser(user, profiles[0]);
  });
}

async function requireIdentity(auth: AuthUser): Promise<AppIdentity> {
  const rows = await sql`
    select id
    from lifemate.app_users
    where auth_subject = ${auth.id} and status = 'Active'
    limit 1
  `;
  if (!rows[0]) {
    throw new ApiError(404, "not_onboarded", "Bootstrap is required.");
  }
  return { auth, appUserId: rows[0].id };
}

async function currentUser(identity: AppIdentity): Promise<Record<string, unknown>> {
  const rows = await sql`
    select
      u.id, u.auth_subject, u.status, u.created_at_utc, u.updated_at_utc,
      p.id as profile_id, p.display_name, p.phone_number, p.email,
      p.locale, p.time_zone
    from lifemate.app_users u
    join lifemate.user_profiles p on p.user_id = u.id
    where u.id = ${identity.appUserId}
    limit 1
  `;
  if (!rows[0]) {
    throw new ApiError(404, "profile_missing", "User profile was not found.");
  }
  const row = rows[0];
  return mapCurrentUser(row, {
    id: row.profile_id,
    user_id: row.id,
    display_name: row.display_name,
    phone_number: row.phone_number,
    email: row.email,
    locale: row.locale,
    time_zone: row.time_zone,
  });
}

async function createMedication(
  userId: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const name = requiredText(body.name, "name", 120);
  const strength = limitedOptional(body.strengthText, "strengthText", 80);
  const form = limitedOptional(body.form, "form", 50);
  const notes = limitedOptional(body.notes, "notes", 500);
  const now = new Date();
  const rows = await sql`
    insert into lifemate.medications
      (id, owner_user_id, name, strength_text, form, notes, version,
       created_at_utc, updated_at_utc)
    values
      (${crypto.randomUUID()}, ${userId}, ${name}, ${strength}, ${form},
       ${notes}, 1, ${now}, ${now})
    returning *
  `;
  await audit(userId, "medication.created", "medication", rows[0].id);
  return mapMedication(rows[0]);
}

async function listMedications(userId: string): Promise<Record<string, unknown>[]> {
  const rows = await sql`
    select *
    from lifemate.medications
    where owner_user_id = ${userId}
    order by name, id
    limit 100
  `;
  return rows.map(mapMedication);
}

async function createTreatmentPlan(
  userId: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const medicationId = requiredUuid(body.medicationId, "medicationId");
  const doseText = requiredText(body.doseText, "doseText", 80);
  const instructions = limitedOptional(body.instructions, "instructions", 500);
  const startDate = requiredDate(body.startDate, "startDate");
  const endDate = body.endDate == null ? null : requiredDate(body.endDate, "endDate");
  if (endDate && endDate < startDate) {
    throw new ApiError(400, "invalid_treatment_plan", "End date cannot precede start date.");
  }
  const timeZone = requiredText(body.timeZone, "timeZone", 64);
  const schedules = normalizeSchedules(body.schedules);
  const now = new Date();

  return await sql.begin(async (tx) => {
    const medicationRows = await tx`
      select *
      from lifemate.medications
      where id = ${medicationId} and owner_user_id = ${userId}
      limit 1
    `;
    if (!medicationRows[0]) {
      throw new ApiError(400, "invalid_medication", "Medication does not belong to the user.");
    }

    const planId = crypto.randomUUID();
    const planRows = await tx`
      insert into lifemate.treatment_plans
        (id, patient_user_id, medication_id, dose_text, instructions,
         start_date, end_date, time_zone, status, version,
         created_at_utc, updated_at_utc)
      values
        (${planId}, ${userId}, ${medicationId}, ${doseText}, ${instructions},
         ${startDate}, ${endDate}, ${timeZone}, 'Active', 1, ${now}, ${now})
      returning *
    `;

    const createdSchedules: Record<string, unknown>[] = [];
    for (const schedule of schedules) {
      const rows = await tx`
        insert into lifemate.treatment_schedules
          (id, treatment_plan_id, day_of_week, local_time, created_at_utc)
        values
          (${crypto.randomUUID()}, ${planId}, ${schedule.dayOfWeek},
           ${schedule.localTime}, ${now})
        returning *
      `;
      createdSchedules.push(rows[0]);
    }

    await insertAudit(
      tx,
      userId,
      "treatment_plan.created",
      "treatment_plan",
      planId,
    );
    return mapTreatmentPlan(
      planRows[0],
      medicationRows[0],
      createdSchedules,
    );
  });
}

async function listTreatmentPlans(
  userId: string,
): Promise<Record<string, unknown>[]> {
  const plans = await sql`
    select p.*, m.name, m.strength_text, m.form, m.notes,
           m.version as medication_version,
           m.created_at_utc as medication_created_at_utc,
           m.updated_at_utc as medication_updated_at_utc
    from lifemate.treatment_plans p
    join lifemate.medications m on m.id = p.medication_id
    where p.patient_user_id = ${userId} and p.status <> 'Archived'
    order by p.updated_at_utc desc, p.id
    limit 100
  `;
  if (plans.length === 0) return [];
  const planIds = plans.map((row) => row.id);
  const schedules = await sql`
    select *
    from lifemate.treatment_schedules
    where treatment_plan_id in ${sql(planIds)}
    order by day_of_week, local_time
  `;
  return plans.map((row) =>
    mapTreatmentPlan(
      row,
      {
        id: row.medication_id,
        name: row.name,
        strength_text: row.strength_text,
        form: row.form,
        notes: row.notes,
        version: row.medication_version,
        created_at_utc: row.medication_created_at_utc,
        updated_at_utc: row.medication_updated_at_utc,
      },
      schedules.filter((schedule) => schedule.treatment_plan_id === row.id),
    )
  );
}

async function materializeOccurrences(
  patientUserId: string,
  fromDate: string,
  toDate: string,
): Promise<void> {
  await sql.begin(async (tx) => {
    await tx`
      insert into lifemate.dose_occurrences
        (id, patient_user_id, treatment_plan_id, treatment_schedule_id,
         scheduled_at_utc, scheduled_local_date, scheduled_local_time,
         time_zone, status, responded_at_utc, version,
         created_at_utc, updated_at_utc)
      select
        gen_random_uuid(), p.patient_user_id, p.id, s.id,
        ((day_value::date + s.local_time) at time zone p.time_zone),
        day_value::date, s.local_time, p.time_zone, 'Scheduled', null, 1,
        now(), now()
      from lifemate.treatment_plans p
      join lifemate.treatment_schedules s on s.treatment_plan_id = p.id
      cross join generate_series(
        ${fromDate}::date,
        ${toDate}::date,
        interval '1 day'
      ) as day_value
      where p.patient_user_id = ${patientUserId}
        and p.status = 'Active'
        and day_value::date >= p.start_date
        and (p.end_date is null or day_value::date <= p.end_date)
        and lower(trim(to_char(day_value, 'Day'))) = lower(s.day_of_week)
      on conflict (treatment_schedule_id, scheduled_at_utc) do nothing
    `;
    await tx`
      update lifemate.dose_occurrences
      set status = 'Missed', version = version + 1, updated_at_utc = now()
      where patient_user_id = ${patientUserId}
        and scheduled_local_date between ${fromDate}::date and ${toDate}::date
        and status = 'Scheduled'
        and scheduled_at_utc + interval '60 minutes' < now()
    `;
  });
}

async function listDoseOccurrences(
  patientUserId: string,
  fromDate: string,
  toDate: string,
): Promise<Record<string, unknown>[]> {
  const rows = await sql`
    select *
    from lifemate.dose_occurrences
    where patient_user_id = ${patientUserId}
      and scheduled_local_date between ${fromDate}::date and ${toDate}::date
    order by scheduled_at_utc, id
  `;
  return rows.map(mapDoseOccurrence);
}

async function reportDose(
  userId: string,
  occurrenceId: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const clientRequestId = requiredUuid(body.clientRequestId, "clientRequestId");
  const expectedVersion = requiredPositiveInt(body.version, "version");
  const target = normalizeDoseStatus(body.status);
  const occurredAt = requiredTimestamp(body.occurredAtUtc, "occurredAtUtc");

  return await sql.begin(async (tx) => {
    const existingEvent = await tx`
      select occurrence_id
      from lifemate.dose_adherence_events
      where client_request_id = ${clientRequestId}
      limit 1
    `;
    if (existingEvent[0]) {
      const existingOccurrence = await tx`
        select * from lifemate.dose_occurrences
        where id = ${existingEvent[0].occurrence_id}
      `;
      return mapDoseOccurrence(existingOccurrence[0]);
    }

    const rows = await tx`
      select *
      from lifemate.dose_occurrences
      where id = ${occurrenceId} and patient_user_id = ${userId}
      for update
    `;
    const occurrence = rows[0];
    if (!occurrence) {
      throw new ApiError(404, "dose_occurrence_not_found", "Dose was not found.");
    }
    if (occurrence.version !== expectedVersion) {
      throw new ApiError(409, "stale_dose_occurrence", "Dose has changed. Refresh and try again.");
    }
    if (occurrence.status === "Cancelled") {
      throw new ApiError(409, "dose_not_reportable", "Cancelled dose cannot be reported.");
    }
    if (occurrence.status === target) return mapDoseOccurrence(occurrence);

    const previous = occurrence.status;
    const eventType = previous === "Scheduled"
      ? target === "Taken" ? "Taken" : "Skipped"
      : "Corrected";
    const updated = await tx`
      update lifemate.dose_occurrences
      set status = ${target}, responded_at_utc = ${occurredAt},
          version = version + 1, updated_at_utc = now()
      where id = ${occurrenceId}
      returning *
    `;
    await tx`
      insert into lifemate.dose_adherence_events
        (id, occurrence_id, actor_user_id, client_request_id, event_type,
         previous_status, resulting_status, occurred_at_utc, recorded_at_utc)
      values
        (${crypto.randomUUID()}, ${occurrenceId}, ${userId}, ${clientRequestId},
         ${eventType}, ${previous}, ${target}, ${occurredAt}, now())
    `;
    return mapDoseOccurrence(updated[0]);
  });
}

async function createInvitation(
  identity: AppIdentity,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  if (body.confirmConsent !== true ||
      body.consentVersion !== "care-patient-consent-v1") {
    throw new ApiError(400, "patient_consent_required", "Patient consent is required.");
  }
  const email = requiredText(body.contact, "contact", 320).toLowerCase();
  if (!email.includes("@")) {
    throw new ApiError(400, "invalid_contact", "A valid email is required.");
  }
  if (identity.auth.email?.toLowerCase() === email) {
    throw new ApiError(400, "self_invitation_not_allowed", "You cannot invite yourself.");
  }

  const contactHash = await hmac(email);
  const now = new Date();
  const expires = new Date(now.getTime() + 72 * 60 * 60 * 1000);
  const token = createToken();
  const tokenHash = await hmac(token);

  return await sql.begin(async (tx) => {
    await tx`
      update lifemate.care_invitations
      set status = 'Expired'
      where inviter_user_id = ${identity.appUserId}
        and contact_hash = ${contactHash}
        and status = 'Pending'
        and expires_at_utc <= now()
    `;
    const pending = await tx`
      select id
      from lifemate.care_invitations
      where inviter_user_id = ${identity.appUserId}
        and contact_hash = ${contactHash}
        and status = 'Pending'
      limit 1
    `;
    if (pending[0]) {
      throw new ApiError(409, "invitation_already_pending", "An invitation is already pending.");
    }

    const id = crypto.randomUUID();
    const hint = maskEmail(email);
    await tx`
      insert into lifemate.care_invitations
        (id, inviter_user_id, contact_type, contact_hash, contact_hint,
         token_hash, patient_consent_version, status, expires_at_utc,
         responded_by_user_id, responded_at_utc, revoked_at_utc, created_at_utc)
      values
        (${id}, ${identity.appUserId}, 'Email', ${contactHash}, ${hint},
         ${tokenHash}, 'care-patient-consent-v1', 'Pending', ${expires},
         null, null, null, ${now})
    `;
    await insertAudit(
      tx,
      identity.appUserId,
      "care_invitation.created",
      "care_invitation",
      id,
    );
    return {
      id,
      contactType: "email",
      contactHint: hint,
      token,
      expiresAtUtc: expires.toISOString(),
    };
  });
}

async function listInvitations(
  userId: string,
): Promise<Record<string, unknown>[]> {
  const rows = await sql`
    select *
    from lifemate.care_invitations
    where inviter_user_id = ${userId}
    order by created_at_utc desc
    limit 100
  `;
  return rows.map((row) => ({
    id: row.id,
    contactType: String(row.contact_type).toLowerCase(),
    contactHint: row.contact_hint,
    status: row.status === "Pending" && new Date(row.expires_at_utc) <= new Date()
      ? "expired"
      : String(row.status).toLowerCase(),
    expiresAtUtc: iso(row.expires_at_utc),
    createdAtUtc: iso(row.created_at_utc),
  }));
}

async function acceptInvitation(
  identity: AppIdentity,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  if (body.confirmConsent !== true ||
      body.consentVersion !== "care-caregiver-consent-v1") {
    throw new ApiError(400, "caregiver_consent_required", "Caregiver consent is required.");
  }
  const token = requiredText(body.token, "token", 512);
  const tokenHash = await hmac(token);
  if (!identity.auth.email) {
    throw new ApiError(403, "invitation_contact_mismatch", "Signed-in email is required.");
  }
  const contactHash = await hmac(identity.auth.email.toLowerCase());
  const now = new Date();

  return await sql.begin(async (tx) => {
    const invitations = await tx`
      select *
      from lifemate.care_invitations
      where token_hash = ${tokenHash}
      for update
    `;
    const invitation = invitations[0];
    if (!invitation) {
      throw new ApiError(404, "invitation_not_found", "Invitation is invalid.");
    }
    if (invitation.status !== "Pending") {
      throw new ApiError(409, "invitation_not_pending", "Invitation is no longer pending.");
    }
    if (new Date(invitation.expires_at_utc) <= now) {
      await tx`
        update lifemate.care_invitations set status = 'Expired'
        where id = ${invitation.id}
      `;
      throw new ApiError(410, "invitation_expired", "Invitation has expired.");
    }
    if (invitation.contact_hash !== contactHash) {
      throw new ApiError(403, "invitation_contact_mismatch", "Invitation belongs to another account.");
    }
    if (invitation.inviter_user_id === identity.appUserId) {
      throw new ApiError(400, "self_invitation_not_allowed", "You cannot accept your own invitation.");
    }

    const active = await tx`
      select id
      from lifemate.care_relationships
      where patient_user_id = ${invitation.inviter_user_id}
        and caregiver_user_id = ${identity.appUserId}
        and status = 'Active'
      limit 1
    `;
    if (active[0]) {
      throw new ApiError(409, "relationship_already_active", "Care relationship already exists.");
    }

    await tx`
      update lifemate.care_invitations
      set status = 'Accepted', responded_by_user_id = ${identity.appUserId},
          responded_at_utc = ${now}
      where id = ${invitation.id}
    `;
    const relationshipId = crypto.randomUUID();
    const relationshipRows = await tx`
      insert into lifemate.care_relationships
        (id, patient_user_id, caregiver_user_id, status,
         patient_consent_version, patient_consented_at_utc,
         caregiver_consent_version, caregiver_consented_at_utc,
         revoked_by_user_id, revoked_at_utc, created_at_utc, updated_at_utc)
      values
        (${relationshipId}, ${invitation.inviter_user_id}, ${identity.appUserId},
         'Active', ${invitation.patient_consent_version},
         ${invitation.created_at_utc}, 'care-caregiver-consent-v1', ${now},
         null, null, ${now}, ${now})
      returning *
    `;
    await insertAudit(
      tx,
      identity.appUserId,
      "care_relationship.created",
      "care_relationship",
      relationshipId,
    );
    return await mapRelationship(tx, relationshipRows[0]);
  });
}

async function listRelationships(
  userId: string,
): Promise<Record<string, unknown>[]> {
  const rows = await sql`
    select r.*,
      patient.display_name as patient_display_name,
      caregiver.display_name as caregiver_display_name
    from lifemate.care_relationships r
    join lifemate.user_profiles patient on patient.user_id = r.patient_user_id
    join lifemate.user_profiles caregiver on caregiver.user_id = r.caregiver_user_id
    where r.patient_user_id = ${userId} or r.caregiver_user_id = ${userId}
    order by r.created_at_utc desc
    limit 100
  `;
  return rows.map(mapRelationshipRow);
}

async function revokeRelationship(
  userId: string,
  relationshipId: string,
): Promise<void> {
  const rows = await sql`
    update lifemate.care_relationships
    set status = 'Revoked', revoked_by_user_id = ${userId},
        revoked_at_utc = now(), updated_at_utc = now()
    where id = ${relationshipId}
      and (patient_user_id = ${userId} or caregiver_user_id = ${userId})
      and status = 'Active'
    returning id
  `;
  if (!rows[0]) {
    throw new ApiError(404, "relationship_not_found", "Care relationship was not found.");
  }
  await audit(
    userId,
    "care_relationship.revoked",
    "care_relationship",
    relationshipId,
  );
}

async function requireCareAccess(
  caregiverUserId: string,
  patientUserId: string,
): Promise<void> {
  const rows = await sql`
    select id
    from lifemate.care_relationships
    where patient_user_id = ${patientUserId}
      and caregiver_user_id = ${caregiverUserId}
      and status = 'Active'
    limit 1
  `;
  if (!rows[0]) {
    throw new ApiError(403, "care_access_denied", "Care access is not active.");
  }
}

async function listCareDoseOccurrences(
  patientUserId: string,
  fromDate: string,
  toDate: string,
): Promise<Record<string, unknown>[]> {
  const rows = await sql`
    select o.*, m.name as medication_name, p.dose_text
    from lifemate.dose_occurrences o
    join lifemate.treatment_plans p on p.id = o.treatment_plan_id
    join lifemate.medications m on m.id = p.medication_id
    where o.patient_user_id = ${patientUserId}
      and o.scheduled_local_date between ${fromDate}::date and ${toDate}::date
    order by o.scheduled_at_utc, o.id
  `;
  return rows.map((row) => ({
    ...mapDoseOccurrence(row),
    medicationName: row.medication_name,
    doseText: row.dose_text,
  }));
}

async function audit(
  actorUserId: string,
  action: string,
  resourceType: string,
  resourceId: string,
): Promise<void> {
  await insertAudit(sql, actorUserId, action, resourceType, resourceId);
}

async function insertAudit(
  connection: typeof sql,
  actorUserId: string,
  action: string,
  resourceType: string,
  resourceId: string,
): Promise<void> {
  await connection`
    insert into lifemate.audit_logs
      (id, actor_user_id, action, resource_type, resource_id,
       metadata_json, created_at_utc)
    values
      (${crypto.randomUUID()}, ${actorUserId}, ${action}, ${resourceType},
       ${resourceId}, null, now())
  `;
}

async function mapRelationship(
  connection: typeof sql,
  relationship: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const names = await connection`
    select user_id, display_name
    from lifemate.user_profiles
    where user_id in ${sql([
      relationship.patient_user_id,
      relationship.caregiver_user_id,
    ])}
  `;
  const byId = new Map(names.map((row) => [row.user_id, row.display_name]));
  return mapRelationshipRow({
    ...relationship,
    patient_display_name: byId.get(relationship.patient_user_id),
    caregiver_display_name: byId.get(relationship.caregiver_user_id),
  });
}

function mapCurrentUser(
  user: Record<string, unknown>,
  profile: Record<string, unknown>,
): Record<string, unknown> {
  return {
    user: {
      id: user.id,
      authSubject: user.auth_subject,
      status: String(user.status).toLowerCase(),
      createdAtUtc: iso(user.created_at_utc),
      updatedAtUtc: iso(user.updated_at_utc),
    },
    profile: {
      id: profile.id,
      userId: profile.user_id,
      displayName: profile.display_name,
      phoneNumber: profile.phone_number,
      email: profile.email,
      locale: profile.locale,
      timeZone: profile.time_zone,
    },
  };
}

function mapMedication(row: Record<string, unknown>): Record<string, unknown> {
  return {
    id: row.id,
    name: row.name,
    strengthText: row.strength_text,
    form: row.form,
    notes: row.notes,
    version: row.version,
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function mapTreatmentPlan(
  row: Record<string, unknown>,
  medication: Record<string, unknown>,
  schedules: Record<string, unknown>[],
): Record<string, unknown> {
  return {
    id: row.id,
    patientUserId: row.patient_user_id,
    medication: mapMedication(medication),
    doseText: row.dose_text,
    instructions: row.instructions,
    startDate: dateString(row.start_date),
    endDate: row.end_date == null ? null : dateString(row.end_date),
    timeZone: row.time_zone,
    status: String(row.status).toLowerCase(),
    version: row.version,
    schedules: schedules.map((schedule) => ({
      id: schedule.id,
      dayOfWeek: String(schedule.day_of_week).toLowerCase(),
      localTime: timeString(schedule.local_time),
    })),
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function mapDoseOccurrence(row: Record<string, unknown>): Record<string, unknown> {
  return {
    id: row.id,
    treatmentPlanId: row.treatment_plan_id,
    treatmentScheduleId: row.treatment_schedule_id,
    scheduledAtUtc: iso(row.scheduled_at_utc),
    scheduledLocalDate: dateString(row.scheduled_local_date),
    scheduledLocalTime: timeString(row.scheduled_local_time),
    timeZone: row.time_zone,
    status: String(row.status).toLowerCase(),
    respondedAtUtc: row.responded_at_utc == null
      ? null
      : iso(row.responded_at_utc),
    version: row.version,
  };
}

function mapRelationshipRow(
  row: Record<string, unknown>,
): Record<string, unknown> {
  return {
    id: row.id,
    patientUserId: row.patient_user_id,
    patientDisplayName: row.patient_display_name ?? "LifeMate User",
    caregiverUserId: row.caregiver_user_id,
    caregiverDisplayName: row.caregiver_display_name ?? "LifeMate User",
    status: String(row.status).toLowerCase(),
    patientConsentedAtUtc: iso(row.patient_consented_at_utc),
    caregiverConsentedAtUtc: iso(row.caregiver_consented_at_utc),
    revokedAtUtc: row.revoked_at_utc == null ? null : iso(row.revoked_at_utc),
    createdAtUtc: iso(row.created_at_utc),
  };
}

function normalizeSchedules(value: unknown): Array<{
  dayOfWeek: string;
  localTime: string;
}> {
  if (!Array.isArray(value) || value.length === 0 || value.length > 64) {
    throw new ApiError(400, "schedule_required", "At least one schedule is required.");
  }
  const allowedDays = new Set([
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
  ]);
  const unique = new Set<string>();
  return value.map((entry) => {
    if (!entry || typeof entry !== "object") {
      throw new ApiError(400, "invalid_schedule", "Schedule is invalid.");
    }
    const rawDay = String((entry as Record<string, unknown>).dayOfWeek ?? "");
    const day = rawDay.charAt(0).toUpperCase() + rawDay.slice(1).toLowerCase();
    const time = String((entry as Record<string, unknown>).localTime ?? "");
    if (!allowedDays.has(day) || !/^\d{2}:\d{2}(:\d{2})?$/.test(time)) {
      throw new ApiError(400, "invalid_schedule", "Schedule day or time is invalid.");
    }
    const normalizedTime = time.slice(0, 5);
    const key = `${day}:${normalizedTime}`;
    if (unique.has(key)) {
      throw new ApiError(400, "duplicate_schedule", "Schedule is duplicated.");
    }
    unique.add(key);
    return { dayOfWeek: day, localTime: normalizedTime };
  });
}

function normalizeDoseStatus(value: unknown): "Taken" | "Skipped" {
  const status = String(value ?? "").toLowerCase();
  if (status === "taken") return "Taken";
  if (status === "skipped") return "Skipped";
  throw new ApiError(400, "invalid_dose_status", "Status must be taken or skipped.");
}

function normalizePath(pathname: string): string {
  const marker = "/lifemate-api";
  const markerIndex = pathname.indexOf(marker);
  const value = markerIndex >= 0
    ? pathname.substring(markerIndex + marker.length)
    : pathname;
  const normalized = value.startsWith("/") ? value : `/${value}`;
  return normalized.length > 1 && normalized.endsWith("/")
    ? normalized.substring(0, normalized.length - 1)
    : normalized;
}

function readKeyDictionary(name: string): Record<string, string> {
  const raw = Deno.env.get(name);
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

async function readBody(request: Request): Promise<Record<string, unknown>> {
  try {
    const body = await request.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new Error("not an object");
    }
    return body;
  } catch {
    throw new ApiError(400, "invalid_json", "Request body must be valid JSON.");
  }
}

function requiredText(value: unknown, field: string, max: number): string {
  const normalized = normalizeOptional(value);
  if (!normalized || normalized.length > max) {
    throw new ApiError(400, `invalid_${field}`, `${field} is required and must be at most ${max} characters.`);
  }
  return normalized;
}

function limitedOptional(
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

function normalizeOptional(value: unknown): string | null {
  if (value == null) return null;
  const normalized = String(value).trim();
  return normalized.length === 0 ? null : normalized;
}

function requiredUuid(value: unknown, field: string): string {
  const normalized = String(value ?? "");
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(normalized)) {
    throw new ApiError(400, `invalid_${field}`, `${field} must be a UUID.`);
  }
  return normalized;
}

function requiredPositiveInt(value: unknown, field: string): number {
  if (!Number.isInteger(value) || Number(value) < 1) {
    throw new ApiError(400, `invalid_${field}`, `${field} must be positive.`);
  }
  return Number(value);
}

function requiredDate(value: unknown, field: string): string {
  const normalized = String(value ?? "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(normalized) ||
      Number.isNaN(Date.parse(`${normalized}T00:00:00Z`))) {
    throw new ApiError(400, `invalid_${field}`, `${field} must be an ISO date.`);
  }
  return normalized;
}

function requiredTimestamp(value: unknown, field: string): Date {
  const date = new Date(String(value ?? ""));
  if (Number.isNaN(date.getTime())) {
    throw new ApiError(400, `invalid_${field}`, `${field} must be an ISO timestamp.`);
  }
  return date;
}

function validateRange(fromDate: string, toDate: string): void {
  const from = Date.parse(`${fromDate}T00:00:00Z`);
  const to = Date.parse(`${toDate}T00:00:00Z`);
  const days = Math.round((to - from) / 86400000);
  if (days < 0 || days > 31) {
    throw new ApiError(400, "invalid_date_range", "Date range must be between 0 and 31 days.");
  }
}

async function hmac(value: string): Promise<string> {
  const keyMaterial = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${hashingSecret}:lifemate-care-v1`),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    keyMaterial,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function createToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function maskEmail(email: string): string {
  const [name, domain] = email.split("@");
  const visible = name.slice(0, Math.min(2, name.length));
  return `${visible}${"*".repeat(Math.max(2, name.length - visible.length))}@${domain}`;
}

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}

function dateString(value: unknown): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}

function timeString(value: unknown): string {
  return String(value).slice(0, 8);
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: corsHeaders,
  });
}

function problem(status: number, code: string, detail: string): Response {
  return json({ status, title: code, code, detail }, status);
}

function safeError(error: unknown): string {
  return error instanceof Error ? `${error.name}: ${error.message}` : String(error);
}

class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}
