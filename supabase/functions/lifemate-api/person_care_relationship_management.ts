import { createContactPointReader } from "./contact_points.ts";
import { getLifeMateSql } from "./database_client.ts";
import { ApiError, requiredUuid } from "./validation.ts";

type Row = Record<string, any>;

const completionModes = new Set([
  "all",
  "important",
  "after_missed",
  "daily_summary",
  "off",
]);
const lockScreenDetails = new Set(["full", "limited", "hidden"]);

/**
 * Canonical Person membership boundary for relationship inventory, caregiver
 * preferences, permission ownership and revocation. Legacy AppUser participant
 * IDs remain only for public compatibility and actor/audit provenance.
 */
export function createPersonCareRelationshipManagementStore(
  databaseUrl: string,
) {
  const sql = getLifeMateSql(databaseUrl);
  const contactReader = createContactPointReader();

  async function listRelationships(
    appUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const personId = await requireSelfPerson(sql, appUserId);
    const rows = await sql`
      select r.*,
             patient.display_name as patient_display_name,
             caregiver.display_name as caregiver_display_name
      from lifemate.care_relationships r
      left join core.person_profiles patient
        on patient.person_id = r.patient_person_id
      left join core.person_profiles caregiver
        on caregiver.person_id = r.caregiver_person_id
      where r.patient_person_id = ${personId}::uuid
         or r.caregiver_person_id = ${personId}::uuid
      order by r.created_at_utc desc
      limit 100
    `;
    const mapped: Record<string, unknown>[] = [];
    for (const row of rows) {
      const relationship = mapRelationshipRow(row);
      const isActiveCaregiver = String(row.status).toLowerCase() === "active" &&
        String(row.caregiver_person_id) === personId &&
        row.patient_consented_at_utc != null &&
        row.caregiver_consented_at_utc != null;
      relationship.patientPhoneNumber = await readPatientPhoneForCaregiver(
        sql,
        contactReader,
        row,
        personId,
      );
      relationship.notificationPreferences = isActiveCaregiver
        ? mapNotificationPreferences(row)
        : null;
      mapped.push(relationship);
    }
    return mapped;
  }

  async function getNotificationPreferences(
    caregiverAppUserId: string,
    relationshipIdValue: unknown,
  ): Promise<Record<string, unknown>> {
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    const caregiverPersonId = await requireSelfPerson(sql, caregiverAppUserId);
    const rows = await sql`
      select *
      from lifemate.care_relationships
      where id = ${relationshipId}::uuid
        and caregiver_person_id = ${caregiverPersonId}::uuid
        and status = 'Active'
        and patient_consented_at_utc is not null
        and caregiver_consented_at_utc is not null
      limit 1
    `;
    if (!rows[0]) {
      throw new ApiError(
        404,
        "relationship_not_found",
        "Active caregiver relationship was not found.",
      );
    }
    return mapNotificationPreferences(rows[0]);
  }

  async function updateNotificationPreferences(
    caregiverAppUserId: string,
    relationshipIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    const patch = normalizeNotificationPreferences(body);
    return await sql.begin(async (tx: any) => {
      const caregiverPersonId = await requireSelfPerson(tx, caregiverAppUserId);
      const rows = await tx`
        update lifemate.care_relationships
        set caregiver_notifications_enabled = ${patch.enabled},
            caregiver_missed_alerts_enabled = ${patch.missedAlertsEnabled},
            caregiver_completion_mode = ${patch.completionMode},
            caregiver_care_events_enabled = ${patch.careEventsEnabled},
            caregiver_daily_summary_enabled = ${patch.dailySummaryEnabled},
            caregiver_daily_summary_local_time = ${patch.dailySummaryLocalTime}::time,
            caregiver_lock_screen_detail = ${patch.lockScreenDetail},
            updated_at_utc = now()
        where id = ${relationshipId}::uuid
          and caregiver_person_id = ${caregiverPersonId}::uuid
          and status = 'Active'
          and patient_consented_at_utc is not null
          and caregiver_consented_at_utc is not null
        returning *
      `;
      if (!rows[0]) {
        throw new ApiError(
          404,
          "relationship_not_found",
          "Active caregiver relationship was not found.",
        );
      }
      await insertAudit(
        tx,
        caregiverAppUserId,
        "care_relationship.notification_preferences_updated",
        "care_relationship",
        relationshipId,
      );
      return mapNotificationPreferences(rows[0]);
    });
  }

  async function updateRelationshipPermissions(
    patientAppUserId: string,
    relationshipIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    const hasWomenPermission = typeof body.canViewWomenCalendar === "boolean";
    const hasSchedulePermission = typeof body.canManageCareSchedule === "boolean";
    if (!hasWomenPermission && !hasSchedulePermission) {
      throw new ApiError(
        400,
        "invalid_care_permission",
        "At least one supported care permission must be provided.",
      );
    }
    if (
      body.canViewWomenCalendar != null &&
      typeof body.canViewWomenCalendar !== "boolean"
    ) {
      throw new ApiError(
        400,
        "invalid_care_permission",
        "canViewWomenCalendar must be a boolean.",
      );
    }
    if (
      body.canManageCareSchedule != null &&
      typeof body.canManageCareSchedule !== "boolean"
    ) {
      throw new ApiError(
        400,
        "invalid_care_permission",
        "canManageCareSchedule must be a boolean.",
      );
    }

    return await sql.begin(async (tx: any) => {
      const patientPersonId = await requireSelfPerson(tx, patientAppUserId);
      const existingRows = await tx`
        select *
        from lifemate.care_relationships
        where id = ${relationshipId}::uuid
          and patient_person_id = ${patientPersonId}::uuid
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

      const canViewWomenCalendar = hasWomenPermission
        ? body.canViewWomenCalendar as boolean
        : existing.can_view_women_calendar === true;
      const canManageCareSchedule = hasSchedulePermission
        ? body.canManageCareSchedule as boolean
        : existing.can_manage_care_schedule === true;

      const rows = await tx`
        update lifemate.care_relationships
        set can_view_women_calendar = ${canViewWomenCalendar},
            can_manage_care_schedule = ${canManageCareSchedule},
            updated_at_utc = now()
        where id = ${relationshipId}::uuid
        returning *
      `;
      if (hasSchedulePermission) {
        await tx`
          select security.sync_care_schedule_write_scopes(
            ${relationshipId}::uuid,
            ${canManageCareSchedule}
          )
        `;
      }
      await insertAudit(
        tx,
        patientAppUserId,
        "care_relationship.permissions_updated",
        "care_relationship",
        relationshipId,
      );
      return await mapRelationship(tx, rows[0]);
    });
  }

  async function revokeRelationship(
    actorAppUserId: string,
    relationshipIdValue: unknown,
  ): Promise<void> {
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    await sql.begin(async (tx: any) => {
      const actorPersonId = await requireSelfPerson(tx, actorAppUserId);
      const relationships = await tx`
        select *
        from lifemate.care_relationships
        where id = ${relationshipId}::uuid
          and (
            patient_person_id = ${actorPersonId}::uuid
            or caregiver_person_id = ${actorPersonId}::uuid
          )
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
        set status = 'Revoked', revoked_by_user_id = ${actorAppUserId}::uuid,
            revoked_at_utc = now(), updated_at_utc = now()
        where id = ${relationshipId}::uuid
      `;
      await insertAudit(
        tx,
        actorAppUserId,
        "care_relationship.revoked",
        "care_relationship",
        relationshipId,
      );
    });
  }

  return {
    listRelationships,
    getNotificationPreferences,
    updateNotificationPreferences,
    updateRelationshipPermissions,
    revokeRelationship,
  };
}

type NotificationPreferences = {
  enabled: boolean;
  missedAlertsEnabled: boolean;
  completionMode: string;
  careEventsEnabled: boolean;
  dailySummaryEnabled: boolean;
  dailySummaryLocalTime: string;
  lockScreenDetail: string;
};

function normalizeNotificationPreferences(
  body: Record<string, unknown>,
): NotificationPreferences {
  const enabled = requiredBoolean(body.enabled, "enabled");
  const missedAlertsEnabled = requiredBoolean(
    body.missedAlertsEnabled,
    "missedAlertsEnabled",
  );
  const careEventsEnabled = requiredBoolean(
    body.careEventsEnabled,
    "careEventsEnabled",
  );
  const dailySummaryEnabled = requiredBoolean(
    body.dailySummaryEnabled,
    "dailySummaryEnabled",
  );
  const completionMode = requiredChoice(
    body.completionMode,
    "completionMode",
    completionModes,
  );
  const lockScreenDetail = requiredChoice(
    body.lockScreenDetail,
    "lockScreenDetail",
    lockScreenDetails,
  );
  const dailySummaryLocalTime = String(body.dailySummaryLocalTime ?? "").trim();
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(dailySummaryLocalTime)) {
    throw new ApiError(
      400,
      "invalid_notification_preference",
      "dailySummaryLocalTime must use HH:mm.",
    );
  }
  return {
    enabled,
    missedAlertsEnabled,
    completionMode,
    careEventsEnabled,
    dailySummaryEnabled,
    dailySummaryLocalTime,
    lockScreenDetail,
  };
}

function requiredBoolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") {
    throw new ApiError(
      400,
      "invalid_notification_preference",
      `${field} must be a boolean.`,
    );
  }
  return value;
}

function requiredChoice(
  value: unknown,
  field: string,
  allowed: Set<string>,
): string {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (!allowed.has(normalized)) {
    throw new ApiError(
      400,
      "invalid_notification_preference",
      `${field} has an unsupported value.`,
    );
  }
  return normalized;
}

function mapNotificationPreferences(row: Row): Record<string, unknown> {
  const rawTime = row.caregiver_daily_summary_local_time;
  const localTime = typeof rawTime === "string"
    ? rawTime.slice(0, 5)
    : rawTime instanceof Date
    ? `${rawTime.getHours().toString().padStart(2, "0")}:${
      rawTime.getMinutes().toString().padStart(2, "0")
    }`
    : "20:00";
  return {
    enabled: row.caregiver_notifications_enabled !== false,
    missedAlertsEnabled: row.caregiver_missed_alerts_enabled !== false,
    completionMode: String(row.caregiver_completion_mode ?? "off"),
    careEventsEnabled: row.caregiver_care_events_enabled !== false,
    dailySummaryEnabled: row.caregiver_daily_summary_enabled === true,
    dailySummaryLocalTime: localTime,
    lockScreenDetail: String(row.caregiver_lock_screen_detail ?? "limited"),
  };
}

async function readPatientPhoneForCaregiver(
  connection: any,
  contactReader: ReturnType<typeof createContactPointReader>,
  row: Row,
  callerPersonId: string,
): Promise<string | null> {
  if (
    String(row.status).toLowerCase() !== "active" ||
    String(row.caregiver_person_id) !== callerPersonId ||
    row.patient_consented_at_utc == null ||
    row.caregiver_consented_at_utc == null ||
    typeof row.patient_user_id !== "string"
  ) {
    return null;
  }
  const legacyRows = await connection`
    select phone_number
    from lifemate.user_profiles
    where user_id = ${row.patient_user_id}::uuid
    limit 1
  `;
  const legacyPhone = legacyRows[0]?.phone_number == null
    ? null
    : String(legacyRows[0].phone_number);
  return await contactReader.readForProfile(
    connection,
    String(row.patient_user_id),
    "Phone",
    legacyPhone,
  );
}

async function requireSelfPerson(
  connection: any,
  appUserId: string,
): Promise<string> {
  const rows = await connection`
    select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text
      as person_id
  `;
  const personId = rows[0]?.person_id;
  if (typeof personId !== "string" || personId.length === 0) {
    throw new ApiError(
      409,
      "identity_person_mapping_missing",
      "The LifeMate person mapping is unavailable.",
    );
  }
  return personId;
}

async function mapRelationship(
  connection: any,
  relationship: Row,
): Promise<Record<string, unknown>> {
  const names = await connection`
    select person_id::text, display_name
    from core.person_profiles
    where person_id in (
      ${relationship.patient_person_id}::uuid,
      ${relationship.caregiver_person_id}::uuid
    )
  `;
  const byId = new Map(
    names.map((row: Row) => [String(row.person_id), row.display_name]),
  );
  return mapRelationshipRow({
    ...relationship,
    patient_display_name: byId.get(String(relationship.patient_person_id)),
    caregiver_display_name: byId.get(String(relationship.caregiver_person_id)),
  });
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
    canManageCareSchedule: row.can_manage_care_schedule === true,
    patientConsentedAtUtc: iso(row.patient_consented_at_utc),
    caregiverConsentedAtUtc: iso(row.caregiver_consented_at_utc),
    revokedAtUtc: row.revoked_at_utc == null ? null : iso(row.revoked_at_utc),
    createdAtUtc: iso(row.created_at_utc),
  };
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
      (${crypto.randomUUID()}, ${actorUserId}::uuid, ${action}, ${resourceType},
       ${resourceId}::uuid, null, now())
  `;
}

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}
