import { getLifeMateSql } from "./database_client.ts";
import { createProfileStore } from "./profile.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

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

/**
 * Staged profile identity migration.
 *
 * Person-facing self profile fields are authoritative on core.person_profiles.
 * The legacy user_profiles row remains temporarily responsible for identity
 * contact compatibility and optimistic-concurrency versioning, while existing
 * write triggers project accepted changes into the canonical Person profile.
 */
export function createPersonProfileStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const legacy = createProfileStore(databaseUrl);

  async function getProfile(appUserId: string): Promise<Record<string, unknown>> {
    const personId = await requireSelfPerson(sql, appUserId);
    const [compatibility, rows] = await Promise.all([
      legacy.getProfile(appUserId),
      sql`
        select display_name, locale, time_zone, avatar_key
        from core.person_profiles
        where person_id = ${personId}::uuid
        limit 1
      `,
    ]);
    const personProfile = rows[0] as Row | undefined;
    if (!personProfile) {
      throw new ApiError(
        404,
        "profile_missing",
        "User profile was not found.",
      );
    }

    return {
      ...compatibility,
      displayName: personProfile.display_name,
      locale: personProfile.locale,
      timeZone: personProfile.time_zone,
      avatarKey: personProfile.avatar_key ?? "person_blue",
    };
  }

  async function updateProfile(
    appUserId: string,
    auth: { email: string | null },
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    await requireSelfPerson(sql, appUserId);
    await legacy.updateProfile(appUserId, auth, body);
    return await getProfile(appUserId);
  }

  return {
    getProfile,
    updateProfile,
    getProfilePhotoPath: legacy.getProfilePhotoPath,
    replaceProfilePhotoPath: legacy.replaceProfilePhotoPath,
  };
}
