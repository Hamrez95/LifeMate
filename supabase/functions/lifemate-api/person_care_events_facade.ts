import { getLifeMateSql } from "./database_client.ts";
import { createPersonCareEventStoreV2 } from "./person_care_events_v2.ts";
import { ApiError, requiredUuid } from "./validation.ts";

/**
 * Public Care Event runtime facade.
 *
 * Self Care Event ownership lives on canonical Person. Caregiver reads resolve
 * the exact patient/caregiver Person relationship before delegating to the same
 * recurrence-aware store used by WellMate.
 */
export function createPersonAuthorizedCareEventStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const store = createPersonCareEventStoreV2(databaseUrl);

  return {
    ...store,
    listCareRecipientEvents: async (
      caregiverAppUserId: string,
      patientAppUserIdValue: unknown,
      fromValue: unknown,
      toValue: unknown,
    ): Promise<Record<string, unknown>[]> => {
      const patientAppUserId = requiredUuid(
        patientAppUserIdValue,
        "patientUserId",
      );
      const patientPersonId = await requireSelfPerson(sql, patientAppUserId);
      const caregiverPersonId = await requireSelfPerson(
        sql,
        caregiverAppUserId,
      );
      const relationship = await sql`
        select id
        from lifemate.care_relationships
        where patient_person_id = ${patientPersonId}::uuid
          and caregiver_person_id = ${caregiverPersonId}::uuid
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

      return await store.listCareEvents(
        patientAppUserId,
        fromValue,
        toValue,
      );
    },
  };
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
