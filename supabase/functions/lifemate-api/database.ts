import postgres from "postgres";
import {
  ApiError,
  limitedOptional,
  normalizeDoseStatus,
  normalizeOptional,
  normalizeSchedules,
  requiredDate,
  requiredPositiveInt,
  requiredText,
  requiredTimestamp,
  requiredTimeZone,
  requiredUuid,
  validateRange,
  validateReportedAt,
} from "./validation.ts";
import {
  createHmac,
  createToken,
  maskEmail,
  timingSafeEqual,
} from "./security.ts";

export type AuthUser = {
  id: string;
  email: string | null;
  phone: string | null;
  userMetadata: Record<string, unknown>;
};

export type AppIdentity = {
  auth: AuthUser;
  appUserId: string;
};

type Row = Record<string, any>;
type Sql = ReturnType<typeof postgres>;

export function createLifeMateDatabase(
  databaseUrl: string,
  contactHashingSecret: string,
) {
  const sql = postgres(databaseUrl, {
    max: 2,
    idle_timeout: 20,
    connect_timeout: 10,
    prepare: false,
  });
  const hmac = createHmac(contactHashingSecret);

  async function health(): Promise<void> {
    await sql`select 1`;
  }

  async function bootstrapUser(
    auth: AuthUser,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const now = new Date();
    const requestedName = normalizeOptional(body.displayName);
    const metadataName = normalizeOptional(auth.userMetadata?.display_name) ??
      normalizeOptional(auth.userMetadata?.full_name) ??
      normalizeOptional(auth.userMetadata?.name);
    const fallbackName = auth.email?.split("@")[0] ?? "LifeMate User";
    const displayName = (requestedName ?? metadataName ?? fallbackName).slice(
      0,
      120,
    );
    const locale = (normalizeOptional(body.locale) ?? "fa").slice(0, 16);
    if (!/^[a-z]{2,3}(?:-[A-Z]{2})?$/.test(locale)) {
      throw new ApiError(400, "invalid_locale", "locale is invalid.");
    }
    const timeZone = requiredTimeZone(body.timeZone ?? "Asia/Tehran");

    return await sql.begin(async (tx: any) => {
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
           ${auth.email}, ${locale}, ${timeZone}, ${now}, ${now})
        on conflict (user_id) do update set
          display_name = coalesce(
            nullif(lifemate.user_profiles.display_name, ''),
            excluded.display_name
          ),
          email = coalesce(excluded.email, lifemate.user_profiles.email),
          phone_number = coalesce(excluded.phone_number, lifemate.user_profiles.phone_number),
          locale = excluded.locale,
          time_zone = excluded.time_zone,
          updated_at_utc = excluded.updated_at_utc
        returning id, user_id, display_name, phone_number, email, locale,
                  time_zone, created_at_utc, updated_at_utc
      `;
      await insertAudit(tx, user.id, "user.bootstrap", "app_user", user.id);
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

  async function currentUser(
    identity: AppIdentity,
  ): Promise<Record<string, unknown>> {
    const rows = await sql`
      select
        u.id, u.auth_subject, u.status, u.created_at_utc, u.updated_at_utc,
        p.id as profile_id, p.display_name, p.phone_number, p.email,
        p.locale, p.time_zone, p.created_at_utc as profile_created_at_utc,
        p.updated_at_utc as profile_updated_at_utc
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
      created_at_utc: row.profile_created_at_utc,
      updated_at_utc: row.profile_updated_at_utc,
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

    return await sql.begin(async (tx: any) => {
      const rows = await tx`
        insert into lifemate.medications
          (id, owner_user_id, name, strength_text, form, notes, version,
           created_at_utc, updated_at_utc)
        values
          (${crypto.randomUUID()}, ${userId}, ${name}, ${strength}, ${form},
           ${notes}, 1, ${now}, ${now})
        returning *
      `;
      await insertAudit(
        tx,
        userId,
        "medication.created",
        "medication",
        rows[0].id,
      );
      return mapMedication(rows[0]);
    });
  }

  async function listMedications(
    userId: string,
  ): Promise<Record<string, unknown>[]> {
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
    const instructions = limitedOptional(
      body.instructions,
      "instructions",
      500,
    );
    const startDate = requiredDate(body.startDate, "startDate");
    const endDate = body.endDate == null
      ? null
      : requiredDate(body.endDate, "endDate");
    if (endDate && endDate < startDate) {
      throw new ApiError(
        400,
        "invalid_treatment_plan",
        "End date cannot precede start date.",
      );
    }
    const timeZone = requiredTimeZone(body.timeZone);
    const schedules = normalizeSchedules(body.schedules);
    const now = new Date();

    return await sql.begin(async (tx: any) => {
      const medicationRows = await tx`
        select *
        from lifemate.medications
        where id = ${medicationId} and owner_user_id = ${userId}
        limit 1
      `;
      if (!medicationRows[0]) {
        throw new ApiError(
          400,
          "invalid_medication",
          "Medication does not belong to the user.",
        );
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

      const createdSchedules: Row[] = [];
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
      return mapTreatmentPlan(planRows[0], medicationRows[0], createdSchedules);
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

    const planIds = plans.map((row: Row) => row.id);
    const schedules = await sql`
      select *
      from lifemate.treatment_schedules
      where treatment_plan_id in ${sql(planIds)}
      order by day_of_week, local_time
    `;
    return plans.map((row: Row) =>
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
        schedules.filter((schedule: Row) =>
          schedule.treatment_plan_id === row.id
        ),
      )
    );
  }

  async function listDoseOccurrences(
    patientUserId: string,
    fromValue: unknown,
    toValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const fromDate = requiredDate(fromValue, "fromDate");
    const toDate = requiredDate(toValue, "toDate");
    validateRange(fromDate, toDate);
    await materializeOccurrences(patientUserId, fromDate, toDate);

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
    occurrenceIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const occurrenceId = requiredUuid(occurrenceIdValue, "occurrenceId");
    const clientRequestId = requiredUuid(
      body.clientRequestId,
      "clientRequestId",
    );
    const expectedVersion = requiredPositiveInt(body.version, "version");
    const target = normalizeDoseStatus(body.status);
    const occurredAt = requiredTimestamp(body.occurredAtUtc, "occurredAtUtc");
    validateReportedAt(occurredAt);

    return await sql.begin(async (tx: any) => {
      const rows = await tx`
        select *
        from lifemate.dose_occurrences
        where id = ${occurrenceId} and patient_user_id = ${userId}
        for update
      `;
      const occurrence = rows[0];
      if (!occurrence) {
        throw new ApiError(
          404,
          "dose_occurrence_not_found",
          "Dose was not found.",
        );
      }

      const existingEvents = await tx`
        select occurrence_id
        from lifemate.dose_adherence_events
        where actor_user_id = ${userId}
          and client_request_id = ${clientRequestId}
        limit 1
      `;
      if (existingEvents[0]) {
        if (existingEvents[0].occurrence_id !== occurrenceId) {
          throw new ApiError(
            409,
            "idempotency_key_reused",
            "clientRequestId was already used for another dose.",
          );
        }
        return mapDoseOccurrence(occurrence);
      }

      if (occurrence.version !== expectedVersion) {
        throw new ApiError(
          409,
          "stale_dose_occurrence",
          "Dose has changed. Refresh and try again.",
        );
      }
      if (occurrence.status === "Cancelled") {
        throw new ApiError(
          409,
          "dose_not_reportable",
          "Cancelled dose cannot be reported.",
        );
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
    if (
      body.confirmConsent !== true ||
      body.consentVersion !== "care-patient-consent-v1"
    ) {
      throw new ApiError(
        400,
        "patient_consent_required",
        "Patient consent is required.",
      );
    }
    const email = requiredText(body.contact, "contact", 320).toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new ApiError(400, "invalid_contact", "A valid email is required.");
    }
    if (identity.auth.email?.toLowerCase() === email) {
      throw new ApiError(
        400,
        "self_invitation_not_allowed",
        "You cannot invite yourself.",
      );
    }

    const contactHash = await hmac(`contact:${email}`);
    const now = new Date();
    const expires = new Date(now.getTime() + 72 * 60 * 60 * 1000);
    const token = createToken();
    const tokenHash = await hmac(`token:${token}`);

    return await sql.begin(async (tx: any) => {
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
        throw new ApiError(
          409,
          "invitation_already_pending",
          "An invitation is already pending.",
        );
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

  async function createQrInvitation(
    identity: AppIdentity,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    if (
      body.confirmConsent !== true ||
      body.consentVersion !== "care-patient-consent-v1"
    ) {
      throw new ApiError(
        400,
        "patient_consent_required",
        "Patient consent is required.",
      );
    }

    const now = new Date();
    const expires = new Date(now.getTime() + 10 * 60 * 1000);
    const token = createToken();
    const tokenHash = await hmac(`token:${token}`);
    const id = crypto.randomUUID();
    const contactHash = await hmac(`qr:${id}`);

    return await sql.begin(async (tx: any) => {
      await tx`
        update lifemate.care_invitations
        set status = 'Revoked', revoked_at_utc = ${now}
        where inviter_user_id = ${identity.appUserId}
          and contact_type = 'Qr'
          and status = 'Pending'
      `;
      await tx`
        insert into lifemate.care_invitations
          (id, inviter_user_id, contact_type, contact_hash, contact_hint,
           token_hash, patient_consent_version, status, expires_at_utc,
           responded_by_user_id, responded_at_utc, revoked_at_utc, created_at_utc)
        values
          (${id}, ${identity.appUserId}, 'Qr', ${contactHash}, 'اسکن حضوری',
           ${tokenHash}, 'care-patient-consent-v1', 'Pending', ${expires},
           null, null, null, ${now})
      `;
      await insertAudit(
        tx,
        identity.appUserId,
        "care_invitation.qr_created",
        "care_invitation",
        id,
      );
      return {
        id,
        contactType: "qr",
        contactHint: "اسکن حضوری",
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
    return rows.map((row: Row) => ({
      id: row.id,
      contactType: String(row.contact_type).toLowerCase(),
      contactHint: row.contact_hint,
      status:
        row.status === "Pending" && new Date(row.expires_at_utc) <= new Date()
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
    if (
      body.confirmConsent !== true ||
      body.consentVersion !== "care-caregiver-consent-v1"
    ) {
      throw new ApiError(
        400,
        "caregiver_consent_required",
        "Caregiver consent is required.",
      );
    }
    const token = requiredText(body.token, "token", 512);
    const tokenHash = await hmac(`token:${token}`);
    const now = new Date();

    return await sql.begin(async (tx: any) => {
      const invitations = await tx`
        select *
        from lifemate.care_invitations
        where token_hash = ${tokenHash}
        for update
      `;
      const invitation = invitations[0];
      if (!invitation) {
        throw new ApiError(
          404,
          "invitation_not_found",
          "Invitation is invalid.",
        );
      }

      if (
        invitation.status === "Accepted" &&
        invitation.responded_by_user_id === identity.appUserId
      ) {
        const existing = await tx`
          select *
          from lifemate.care_relationships
          where patient_user_id = ${invitation.inviter_user_id}
            and caregiver_user_id = ${identity.appUserId}
          order by created_at_utc desc
          limit 1
        `;
        if (existing[0]?.status === "Active") {
          return await mapRelationship(tx, existing[0]);
        }
      }
      if (invitation.status !== "Pending") {
        throw new ApiError(
          409,
          "invitation_not_pending",
          "Invitation is no longer pending.",
        );
      }
      if (new Date(invitation.expires_at_utc) <= now) {
        await tx`
          update lifemate.care_invitations
          set status = 'Expired'
          where id = ${invitation.id}
        `;
        throw new ApiError(
          410,
          "invitation_expired",
          "Invitation has expired.",
        );
      }
      if (invitation.contact_type !== "Qr") {
        if (!identity.auth.email) {
          throw new ApiError(
            403,
            "invitation_contact_mismatch",
            "Signed-in email is required.",
          );
        }
        const contactHash = await hmac(
          `contact:${identity.auth.email.toLowerCase()}`,
        );
        if (!timingSafeEqual(invitation.contact_hash, contactHash)) {
          throw new ApiError(
            403,
            "invitation_contact_mismatch",
            "Invitation belongs to another account.",
          );
        }
      }
      if (invitation.inviter_user_id === identity.appUserId) {
        throw new ApiError(
          400,
          "self_invitation_not_allowed",
          "You cannot accept your own invitation.",
        );
      }

      const active = await tx`
        select *
        from lifemate.care_relationships
        where patient_user_id = ${invitation.inviter_user_id}
          and caregiver_user_id = ${identity.appUserId}
          and status = 'Active'
        limit 1
      `;
      if (active[0]) {
        return await mapRelationship(tx, active[0]);
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
        "care_invitation.accepted",
        "care_invitation",
        invitation.id,
      );
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

  async function updateRelationshipPermissions(
    userId: string,
    relationshipIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    if (typeof body.canViewWomenCalendar !== "boolean") {
      throw new ApiError(
        400,
        "invalid_care_permission",
        "canViewWomenCalendar must be a boolean.",
      );
    }
    return await sql.begin(async (tx: any) => {
      const existingRows = await tx`
        select * from lifemate.care_relationships
        where id = ${relationshipId}
          and patient_user_id = ${userId}
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
      const rows = await tx`
        update lifemate.care_relationships
        set can_view_women_calendar = ${body.canViewWomenCalendar},
            updated_at_utc = now()
        where id = ${relationshipId}
        returning *
      `;
      await insertAudit(
        tx,
        userId,
        "care_relationship.permissions_updated",
        "care_relationship",
        relationshipId,
      );
      return await mapRelationship(tx, rows[0]);
    });
  }

  async function revokeRelationship(
    userId: string,
    relationshipIdValue: unknown,
  ): Promise<void> {
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    await sql.begin(async (tx: any) => {
      const relationships = await tx`
        select *
        from lifemate.care_relationships
        where id = ${relationshipId}
          and (patient_user_id = ${userId} or caregiver_user_id = ${userId})
        for update
      `;
      const relationship = relationships[0];
      if (!relationship) {
        throw new ApiError(
          404,
          "relationship_not_found",
          "Care relationship was not found.",
        );
      }
      if (relationship.status === "Revoked") return;

      await tx`
        update lifemate.care_relationships
        set status = 'Revoked', revoked_by_user_id = ${userId},
            revoked_at_utc = now(), updated_at_utc = now()
        where id = ${relationshipId}
      `;
      await insertAudit(
        tx,
        userId,
        "care_relationship.revoked",
        "care_relationship",
        relationshipId,
      );
    });
  }

  async function listCareDoseOccurrences(
    caregiverUserId: string,
    patientUserIdValue: unknown,
    fromValue: unknown,
    toValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const patientUserId = requiredUuid(patientUserIdValue, "patientUserId");
    const fromDate = requiredDate(fromValue, "fromDate");
    const toDate = requiredDate(toValue, "toDate");
    validateRange(fromDate, toDate);

    const relationships = await sql`
      select id
      from lifemate.care_relationships
      where patient_user_id = ${patientUserId}
        and caregiver_user_id = ${caregiverUserId}
        and status = 'Active'
      limit 1
    `;
    if (!relationships[0]) {
      throw new ApiError(
        403,
        "care_access_denied",
        "Care access is not active.",
      );
    }

    await materializeOccurrences(patientUserId, fromDate, toDate);
    const rows = await sql`
      select o.*, m.name as medication_name, p.dose_text
      from lifemate.dose_occurrences o
      join lifemate.treatment_plans p on p.id = o.treatment_plan_id
      join lifemate.medications m on m.id = p.medication_id
      where o.patient_user_id = ${patientUserId}
        and o.scheduled_local_date between ${fromDate}::date and ${toDate}::date
      order by o.scheduled_at_utc, o.id
    `;
    return rows.map((row: Row) => ({
      ...mapDoseOccurrence(row),
      medicationName: row.medication_name,
      doseText: row.dose_text,
    }));
  }

  async function materializeOccurrences(
    patientUserId: string,
    fromDate: string,
    toDate: string,
  ): Promise<void> {
    await sql.begin(async (tx: any) => {
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
          and extract(dow from day_value)::integer = case lower(s.day_of_week)
            when 'sunday' then 0
            when 'monday' then 1
            when 'tuesday' then 2
            when 'wednesday' then 3
            when 'thursday' then 4
            when 'friday' then 5
            when 'saturday' then 6
            else -1
          end
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

  async function insertAudit(
    connection: any,
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
    connection: any,
    relationship: Row,
  ): Promise<Record<string, unknown>> {
    const names = await connection`
      select user_id, display_name
      from lifemate.user_profiles
      where user_id in ${
      sql([
        relationship.patient_user_id,
        relationship.caregiver_user_id,
      ])
    }
    `;
    const byId = new Map(
      names.map((row: Row) => [row.user_id, row.display_name]),
    );
    return mapRelationshipRow({
      ...relationship,
      patient_display_name: byId.get(relationship.patient_user_id),
      caregiver_display_name: byId.get(relationship.caregiver_user_id),
    });
  }

  return {
    health,
    bootstrapUser,
    requireIdentity,
    currentUser,
    createMedication,
    listMedications,
    createTreatmentPlan,
    listTreatmentPlans,
    listDoseOccurrences,
    reportDose,
    createInvitation,
    createQrInvitation,
    listInvitations,
    acceptInvitation,
    listRelationships,
    updateRelationshipPermissions,
    revokeRelationship,
    listCareDoseOccurrences,
  };
}

function mapCurrentUser(user: Row, profile: Row): Record<string, unknown> {
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

function mapMedication(row: Row): Record<string, unknown> {
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
  row: Row,
  medication: Row,
  schedules: Row[],
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

function mapDoseOccurrence(row: Row): Record<string, unknown> {
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

function mapRelationshipRow(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    patientUserId: row.patient_user_id,
    patientDisplayName: row.patient_display_name ?? "LifeMate User",
    caregiverUserId: row.caregiver_user_id,
    caregiverDisplayName: row.caregiver_display_name ?? "LifeMate User",
    status: String(row.status).toLowerCase(),
    canViewWomenCalendar: row.can_view_women_calendar === true,
    patientConsentedAtUtc: iso(row.patient_consented_at_utc),
    caregiverConsentedAtUtc: iso(row.caregiver_consented_at_utc),
    revokedAtUtc: row.revoked_at_utc == null ? null : iso(row.revoked_at_utc),
    createdAtUtc: iso(row.created_at_utc),
  };
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
  return String(value).slice(0, 5);
}
