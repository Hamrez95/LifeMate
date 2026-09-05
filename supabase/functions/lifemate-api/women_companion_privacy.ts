import { getLifeMateSql } from "./database_client.ts";
import { ApiError, requiredUuid } from "./validation.ts";

export const companionPrivacyScopeKeys = [
  "viewPeriodTiming",
  "viewPhaseSummary",
  "viewSharedWellbeing",
  "receiveMoodSupportNotifications",
  "receivePhaseNotifications",
  "viewFertilityEstimate",
  "receiveFertilityNotifications",
  "viewCalendarDetail",
] as const;
type ScopeKey = typeof companionPrivacyScopeKeys[number];
type ScopeRecord = Record<ScopeKey, boolean>;
const columns: Record<ScopeKey, string> = {
  viewPeriodTiming: "view_period_timing",
  viewPhaseSummary: "view_phase_summary",
  viewSharedWellbeing: "view_shared_wellbeing",
  receiveMoodSupportNotifications: "receive_mood_support_notifications",
  receivePhaseNotifications: "receive_phase_notifications",
  viewFertilityEstimate: "view_fertility_estimate",
  receiveFertilityNotifications: "receive_fertility_notifications",
  viewCalendarDetail: "view_calendar_detail",
};
export const defaultCompanionPrivacyScopes = (): ScopeRecord => ({
  viewPeriodTiming: false,
  viewPhaseSummary: false,
  viewSharedWellbeing: false,
  receiveMoodSupportNotifications: false,
  receivePhaseNotifications: false,
  viewFertilityEstimate: false,
  receiveFertilityNotifications: false,
  viewCalendarDetail: false,
});

export function createWomenCompanionPrivacyStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function listOwnerScopes(ownerAppUserId: string) {
    const ownerPersonId = await selfPersonId(sql, ownerAppUserId);
    const rows = await sql`
      select r.id::text as relationship_id, r.caregiver_user_id::text,
        p.display_name as caregiver_display_name, s.*
      from lifemate.care_relationships r
      left join core.person_profiles p on p.person_id = r.caregiver_person_id
      left join lifemate.women_companion_privacy_scopes s on s.relationship_id = r.id
      where r.patient_person_id = ${ownerPersonId}::uuid and r.status = 'Active'
      order by r.created_at_utc asc
    `;
    return rows.map((row: Record<string, unknown>) => present(row));
  }

  async function updateOwnerScopes(
    ownerAppUserId: string,
    relationshipIdValue: unknown,
    body: Record<string, unknown>,
  ) {
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    const expectedVersion = integer(body.version, "version", 0);
    const next = normalize(body.scopes);
    return await sql.begin(async (tx: any) => {
      await requirePeriodProductAccess(tx, ownerAppUserId);
      const ownerPersonId = await selfPersonId(tx, ownerAppUserId);
      const relationship = await tx`
        select id::text from lifemate.care_relationships
        where id = ${relationshipId}::uuid and patient_person_id = ${ownerPersonId}::uuid
          and status = 'Active'
        for update
      `;
      if (!relationship[0]) {
        throw new ApiError(
          404,
          "companion_relationship_not_found",
          "Active companion relationship was not found.",
        );
      }
      const existing = await tx`
        select * from lifemate.women_companion_privacy_scopes
        where relationship_id = ${relationshipId}::uuid for update
      `;
      let row;
      if (!existing[0]) {
        if (expectedVersion !== 0) throw stale();
        const rows = await tx`
          insert into lifemate.women_companion_privacy_scopes
            (relationship_id, view_period_timing, view_phase_summary, view_shared_wellbeing,
             receive_mood_support_notifications, receive_phase_notifications,
             view_fertility_estimate, receive_fertility_notifications, view_calendar_detail,
             version, updated_by_user_id)
          values (${relationshipId}::uuid, ${next.viewPeriodTiming}, ${next.viewPhaseSummary}, ${next.viewSharedWellbeing},
             ${next.receiveMoodSupportNotifications}, ${next.receivePhaseNotifications},
             ${next.viewFertilityEstimate}, ${next.receiveFertilityNotifications}, ${next.viewCalendarDetail},
             1, ${ownerAppUserId}::uuid) returning *
        `;
        row = rows[0];
      } else {
        if (Number(existing[0].version) !== expectedVersion) throw stale();
        const rows = await tx`
          update lifemate.women_companion_privacy_scopes set
            view_period_timing=${next.viewPeriodTiming}, view_phase_summary=${next.viewPhaseSummary},
            view_shared_wellbeing=${next.viewSharedWellbeing},
            receive_mood_support_notifications=${next.receiveMoodSupportNotifications},
            receive_phase_notifications=${next.receivePhaseNotifications},
            view_fertility_estimate=${next.viewFertilityEstimate},
            receive_fertility_notifications=${next.receiveFertilityNotifications},
            view_calendar_detail=${next.viewCalendarDetail}, version=version+1,
            updated_by_user_id=${ownerAppUserId}::uuid, updated_at_utc=now()
          where relationship_id=${relationshipId}::uuid returning *
        `;
        row = rows[0];
      }
      await tx`
        insert into lifemate.audit_logs
          (id, actor_user_id, action, resource_type, resource_id, metadata_json, created_at_utc)
        values (${crypto.randomUUID()}::uuid, ${ownerAppUserId}::uuid,
          'women_calendar.companion_privacy_scopes_updated', 'care_relationship',
          ${relationshipId}::uuid, null, now())
      `;
      return present({ relationship_id: relationshipId, ...row });
    });
  }
  return { listOwnerScopes, updateOwnerScopes };
}

async function requirePeriodProductAccess(
  connection: any,
  appUserId: string,
): Promise<void> {
  const rows = await connection`
    select commerce.period_access_snapshot(${appUserId}::uuid) as snapshot
  `;
  const snapshot = rows[0]?.snapshot as Record<string, unknown> | undefined;
  if (snapshot?.hasProductAccess !== true) {
    throw new ApiError(
      403,
      "period_subscription_required",
      "An active Period Calendar trial or subscription is required.",
    );
  }
}
async function selfPersonId(
  connection: any,
  appUserId: string,
): Promise<string> {
  const rows =
    await connection`select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text as person_id`;
  if (!rows[0]?.person_id) {
    throw new ApiError(
      409,
      "identity_person_mapping_missing",
      "The LifeMate person mapping is unavailable.",
    );
  }
  return rows[0].person_id;
}
function normalize(value: unknown): ScopeRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "invalid_companion_privacy_scopes",
      "scopes must be an object.",
    );
  }
  const record = value as Record<string, unknown>,
    result = defaultCompanionPrivacyScopes();
  for (const key of companionPrivacyScopeKeys) {
    if (typeof record[key] !== "boolean") {
      throw new ApiError(
        400,
        "invalid_companion_privacy_scopes",
        `${key} must be boolean.`,
      );
    }
    result[key] = record[key] as boolean;
  }
  return result;
}
function present(row: Record<string, unknown>) {
  const scopes = defaultCompanionPrivacyScopes();
  for (const key of companionPrivacyScopeKeys) {
    scopes[key] = row[columns[key]] === true;
  }
  return {
    relationshipId: String(row.relationship_id),
    caregiverUserId: row.caregiver_user_id ?? null,
    caregiverDisplayName: row.caregiver_display_name ?? null,
    version: Number(row.version ?? 0),
    scopes,
  };
}
function integer(value: unknown, name: string, minimum: number) {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isInteger(parsed) || parsed < minimum) {
    throw new ApiError(
      400,
      "invalid_companion_privacy_version",
      `${name} is invalid.`,
    );
  }
  return parsed;
}
function stale() {
  return new ApiError(
    409,
    "stale_companion_privacy_scopes",
    "Companion privacy settings changed. Refresh and try again.",
  );
}
