import {
  createContactPointReader,
  createContactPointWriter,
} from "./contact_points.ts";
import { getLifeMateSql } from "./database_client.ts";
import {
  createPrivacyPreferenceStore,
  parsePrivacyPreferencePayload,
} from "./privacy_preferences.ts";
import {
  ApiError,
  normalizeOptional,
  requiredPositiveInt,
  requiredText,
  requiredTimeZone,
} from "./validation.ts";

type ProfileAuthSnapshot = {
  email: string | null;
};

type Row = Record<string, any>;

const allowedAvatarKeys = new Set([
  "person_blue",
  "person_green",
  "person_purple",
  "person_orange",
  "heart_coral",
  "caregiver_teal",
]);

const allowedPresentationIntents = new Set([
  "Self",
  "Caregiving",
  "Both",
]);

const allowedWellMateFirstValueStates = new Set([
  "Skipped",
  "Completed",
]);

export type ProfilePatch = {
  expectedVersion: number;
  displayName: string;
  phoneNumber: string | null;
  locale: string;
  timeZone: string;
  avatarKey: string | null;
  presentationIntent: string | null;
  completeOnboarding: boolean;
  wellMateFirstValueState: string | null;
};

export function normalizeProfilePatch(
  body: Record<string, unknown>,
): ProfilePatch {
  const presentationIntent = optionalPresentationIntent(
    body.presentationIntent,
  );
  const completeOnboarding = body.completeOnboarding === true;
  if (completeOnboarding && presentationIntent == null) {
    throw new ApiError(
      400,
      "onboarding_intent_required",
      "presentationIntent is required when onboarding is completed.",
    );
  }
  return {
    expectedVersion: requiredPositiveInt(body.version, "version"),
    displayName: requiredText(body.displayName, "displayName", 120),
    phoneNumber: optionalPhone(body.phoneNumber),
    locale: requiredLocale(body.locale),
    timeZone: requiredTimeZone(body.timeZone),
    avatarKey: optionalAvatarKey(body.avatarKey),
    presentationIntent,
    completeOnboarding,
    wellMateFirstValueState: optionalWellMateFirstValueState(
      body.wellMateFirstValueState,
    ),
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

/// Profile persistence deliberately supports both the current live schema and
/// the reviewed additive `version` migration. This lets the candidate function
/// be smoke-tested without applying DDL to the production database. Once the
/// migration is promoted, the exact same API automatically switches to the
/// integer version column. Before that, the millisecond `updated_at_utc` value
/// acts as a deterministic optimistic-concurrency token.
export function createProfileStore(
  databaseUrl: string,
  contactHashingSecret?: string,
) {
  const sql = getLifeMateSql(databaseUrl);
  const contactPoints = createContactPointWriter(contactHashingSecret);
  const contactReader = createContactPointReader();
  const privacyPreferences = createPrivacyPreferenceStore(databaseUrl);
  let versionColumnPromise: Promise<boolean> | null = null;
  let photoColumnPromise: Promise<boolean> | null = null;

  function hasVersionColumn(): Promise<boolean> {
    versionColumnPromise ??= sql`
      select exists (
        select 1
        from information_schema.columns
        where table_schema = 'lifemate'
          and table_name = 'user_profiles'
          and column_name = 'version'
      ) as present
    `.then((rows: Row[]) => rows[0]?.present === true);
    return versionColumnPromise;
  }

  function hasPhotoColumn(): Promise<boolean> {
    photoColumnPromise ??= sql`
      select exists (
        select 1
        from information_schema.columns
        where table_schema = 'lifemate'
          and table_name = 'user_profiles'
          and column_name = 'profile_photo_path'
      ) as present
    `.then((rows: Row[]) => rows[0]?.present === true);
    return photoColumnPromise;
  }

  async function getProfilePhotoPath(userId: string): Promise<string | null> {
    if (!(await hasPhotoColumn())) return null;
    const personId = await requireSelfPerson(sql, userId);
    const rows = await sql`
      select profile_photo_path
      from core.person_profiles
      where person_id = ${personId}::uuid
      limit 1
    `;
    if (!rows[0]) {
      throw new ApiError(404, "profile_missing", "User profile was not found.");
    }
    const value = rows[0].profile_photo_path;
    return typeof value === "string" && value.length > 0 ? value : null;
  }

  async function replaceProfilePhotoPath(
    userId: string,
    nextPath: string | null,
  ): Promise<string | null> {
    if (!(await hasPhotoColumn())) {
      throw new ApiError(
        503,
        "profile_photo_not_ready",
        "Profile photo storage is not ready for this environment.",
      );
    }
    if (nextPath != null && !nextPath.startsWith(`${userId}/`)) {
      throw new ApiError(
        400,
        "invalid_profile_photo_path",
        "Profile photo path does not belong to the current user.",
      );
    }
    const usesVersionColumn = await hasVersionColumn();
    return await sql.begin(async (tx: any) => {
      const personId = await requireSelfPerson(tx, userId);
      const current = await tx`
        select id
        from lifemate.user_profiles
        where user_id = ${userId}
        for update
      `;
      const canonical = await tx`
        select profile_photo_path
        from core.person_profiles
        where person_id = ${personId}::uuid
        for update
      `;
      if (!current[0] || !canonical[0]) {
        throw new ApiError(
          404,
          "profile_missing",
          "User profile was not found.",
        );
      }
      const previous = typeof canonical[0].profile_photo_path === "string"
        ? canonical[0].profile_photo_path
        : null;
      if (usesVersionColumn) {
        await tx`
          update lifemate.user_profiles
          set profile_photo_path = ${nextPath},
              version = version + 1,
              updated_at_utc = now()
          where user_id = ${userId}
        `;
      } else {
        await tx`
          update lifemate.user_profiles
          set profile_photo_path = ${nextPath},
              updated_at_utc = greatest(
                now(),
                updated_at_utc + interval '1 millisecond'
              )
          where user_id = ${userId}
        `;
      }
      await tx`
        insert into lifemate.audit_logs
          (id, actor_user_id, action, resource_type, resource_id,
           metadata_json, created_at_utc)
        values
          (${crypto.randomUUID()}, ${userId},
           ${
        nextPath == null ? "profile.photo_deleted" : "profile.photo_updated"
      },
           'user_profile', ${current[0].id}, null, now())
      `;
      return previous;
    });
  }

  async function getProfile(userId: string): Promise<Record<string, unknown>> {
    const personId = await requireSelfPerson(sql, userId);
    const rows = await (await hasVersionColumn()
      ? sql`
          select legacy.id, legacy.user_id,
                 person.display_name,
                 legacy.phone_number, legacy.email,
                 person.locale, person.time_zone, person.avatar_key,
                 legacy.presentation_intent,
                 legacy.onboarding_completed_at_utc,
                 legacy.wellmate_first_value_state,
                 legacy.version,
                 legacy.created_at_utc, legacy.updated_at_utc
          from lifemate.user_profiles legacy
          join core.person_profiles person
            on person.person_id = ${personId}::uuid
          where legacy.user_id = ${userId}::uuid
          limit 1
        `
      : sql`
          select legacy.id, legacy.user_id,
                 person.display_name,
                 legacy.phone_number, legacy.email,
                 person.locale, person.time_zone, person.avatar_key,
                 legacy.presentation_intent,
                 legacy.onboarding_completed_at_utc,
                 legacy.wellmate_first_value_state,
                 floor(extract(epoch from legacy.updated_at_utc) * 1000)::bigint
                   as version,
                 legacy.created_at_utc, legacy.updated_at_utc
          from lifemate.user_profiles legacy
          join core.person_profiles person
            on person.person_id = ${personId}::uuid
          where legacy.user_id = ${userId}::uuid
          limit 1
        `);
    if (!rows[0]) {
      throw new ApiError(404, "profile_missing", "User profile was not found.");
    }
    const row = rows[0];
    const legacyPhone = row.phone_number == null
      ? null
      : String(row.phone_number);
    const legacyEmail = row.email == null ? null : String(row.email);
    const phoneNumber = await contactReader.readForProfile(
      sql,
      userId,
      "Phone",
      legacyPhone,
    );
    const email = await contactReader.readForProfile(
      sql,
      userId,
      "Email",
      legacyEmail,
    );
    return {
      ...mapProfile({ ...row, phone_number: phoneNumber, email }),
      privacyPreferences: await privacyPreferences.preferences(userId),
    };
  }

  async function updateProfile(
    userId: string,
    auth: ProfileAuthSnapshot,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    if (Object.hasOwn(body, "privacyPreference")) {
      if (Object.keys(body).length !== 1) {
        throw new ApiError(
          400,
          "profile_patch_mixed_contracts",
          "Profile fields and privacy preferences must be updated separately.",
        );
      }
      const preference = parsePrivacyPreferencePayload(body.privacyPreference);
      await privacyPreferences.setPreference(
        userId,
        preference.purpose,
        preference.enabled,
      );
      return await getProfile(userId);
    }

    const patch = normalizeProfilePatch(body);
    const usesVersionColumn = await hasVersionColumn();
    const rawPhone = contactReader.rawRetirementEnabled
      ? null
      : patch.phoneNumber;
    const rawEmail = contactReader.rawRetirementEnabled ? null : auth.email;

    return await sql.begin(async (tx: any) => {
      const personId = await requireSelfPerson(tx, userId);
      const compatibilityRows = await (usesVersionColumn
        ? tx`
            update lifemate.user_profiles
            set phone_number = ${rawPhone},
                email = ${rawEmail},
                presentation_intent = coalesce(
                  ${patch.presentationIntent},
                  presentation_intent
                ),
                onboarding_completed_at_utc = case
                  when ${patch.completeOnboarding}
                    then coalesce(onboarding_completed_at_utc, now())
                  else onboarding_completed_at_utc
                end,
                wellmate_first_value_state = coalesce(
                  ${patch.wellMateFirstValueState},
                  wellmate_first_value_state
                ),
                version = version + 1,
                updated_at_utc = now()
            where user_id = ${userId} and version = ${patch.expectedVersion}
            returning id, user_id, phone_number, email,
                      presentation_intent, onboarding_completed_at_utc,
                      wellmate_first_value_state,
                      version, created_at_utc, updated_at_utc
          `
        : tx`
            update lifemate.user_profiles
            set phone_number = ${rawPhone},
                email = ${rawEmail},
                presentation_intent = coalesce(
                  ${patch.presentationIntent},
                  presentation_intent
                ),
                onboarding_completed_at_utc = case
                  when ${patch.completeOnboarding}
                    then coalesce(onboarding_completed_at_utc, now())
                  else onboarding_completed_at_utc
                end,
                wellmate_first_value_state = coalesce(
                  ${patch.wellMateFirstValueState},
                  wellmate_first_value_state
                ),
                updated_at_utc = greatest(
                  now(),
                  updated_at_utc + interval '1 millisecond'
                )
            where user_id = ${userId}
              and floor(extract(epoch from updated_at_utc) * 1000)::bigint =
                  ${patch.expectedVersion}
            returning id, user_id, phone_number, email,
                      presentation_intent, onboarding_completed_at_utc,
                      wellmate_first_value_state,
                      floor(extract(epoch from updated_at_utc) * 1000)::bigint
                        as version,
                      created_at_utc, updated_at_utc
          `);
      if (!compatibilityRows[0]) {
        const current = await (usesVersionColumn
          ? tx`
              select version
              from lifemate.user_profiles
              where user_id = ${userId}
              limit 1
            `
          : tx`
              select floor(extract(epoch from updated_at_utc) * 1000)::bigint
                       as version
              from lifemate.user_profiles
              where user_id = ${userId}
              limit 1
            `);
        if (!current[0]) {
          throw new ApiError(
            404,
            "profile_missing",
            "User profile was not found.",
          );
        }
        throw new ApiError(
          409,
          "stale_profile",
          "Profile has changed. Refresh and try again.",
        );
      }

      // ContactPoint encryption runs inside the exact same transaction as the
      // compatibility Profile/version write. A global contact conflict or crypto
      // failure therefore rolls the Profile/version mutation back as well.
      await contactPoints.syncForLegacyAppUser(
        tx,
        userId,
        { phone: patch.phoneNumber, email: auth.email },
        "replace",
      );

      if (contactReader.rawRetirementEnabled) {
        // Preserve the public Profile response while proving that plaintext is
        // read back from the authenticated canonical envelope, not from a raw
        // compatibility column that retirement has deliberately left NULL.
        compatibilityRows[0].phone_number = await contactReader.readForProfile(
          tx,
          userId,
          "Phone",
          null,
        );
        compatibilityRows[0].email = await contactReader.readForProfile(
          tx,
          userId,
          "Email",
          null,
        );
      }

      const personRows = await tx`
        update core.person_profiles
        set display_name = ${patch.displayName},
            locale = ${patch.locale},
            time_zone = ${patch.timeZone},
            avatar_key = coalesce(${patch.avatarKey}, avatar_key),
            updated_at_utc = now()
        where person_id = ${personId}::uuid
        returning display_name, locale, time_zone, avatar_key
      `;
      if (!personRows[0]) {
        throw new ApiError(
          404,
          "profile_missing",
          "User profile was not found.",
        );
      }

      // Privacy invariant: metadata_json stays null. Intent and first-value state
      // are presentation metadata and never become healthcare authorization.
      await tx`
        insert into lifemate.audit_logs
          (id, actor_user_id, action, resource_type, resource_id,
           metadata_json, created_at_utc)
        values
          (${crypto.randomUUID()}, ${userId},
           ${
        patch.completeOnboarding
          ? "profile.onboarding_completed"
          : "profile.updated"
      },
           'user_profile', ${compatibilityRows[0].id}, null, now())
      `;
      return {
        ...mapProfile({
          ...compatibilityRows[0],
          ...personRows[0],
        }),
        privacyPreferences: await privacyPreferences.preferences(userId),
      };
    });
  }

  return {
    getProfile,
    updateProfile,
    getProfilePhotoPath,
    replaceProfilePhotoPath,
  };
}

function optionalAvatarKey(value: unknown): string | null {
  const normalized = normalizeOptional(value);
  if (normalized == null) return null;
  if (!allowedAvatarKeys.has(normalized)) {
    throw new ApiError(
      400,
      "invalid_avatar_key",
      "avatarKey is not supported.",
    );
  }
  return normalized;
}

function optionalPresentationIntent(value: unknown): string | null {
  const normalized = normalizeOptional(value);
  if (normalized == null) return null;
  if (!allowedPresentationIntents.has(normalized)) {
    throw new ApiError(
      400,
      "invalid_presentation_intent",
      "presentationIntent is not supported.",
    );
  }
  return normalized;
}

function optionalWellMateFirstValueState(value: unknown): string | null {
  const normalized = normalizeOptional(value);
  if (normalized == null) return null;
  if (!allowedWellMateFirstValueStates.has(normalized)) {
    throw new ApiError(
      400,
      "invalid_wellmate_first_value_state",
      "wellMateFirstValueState is not supported.",
    );
  }
  return normalized;
}

function requiredLocale(value: unknown): string {
  const locale = normalizeOptional(value);
  if (
    locale == null ||
    locale.length > 16 ||
    !/^[a-z]{2,3}(?:-[A-Z]{2})?$/.test(locale)
  ) {
    throw new ApiError(400, "invalid_locale", "locale is invalid.");
  }
  return locale;
}

function optionalPhone(value: unknown): string | null {
  const normalized = normalizeOptional(value);
  if (normalized == null) return null;
  const compact = normalized.replace(/[\s()-]/g, "");
  if (!/^\+?[0-9]{7,15}$/.test(compact)) {
    throw new ApiError(
      400,
      "invalid_phone_number",
      "phoneNumber is invalid.",
    );
  }
  return compact;
}

function mapProfile(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    userId: row.user_id,
    displayName: row.display_name,
    phoneNumber: row.phone_number,
    email: row.email,
    locale: row.locale,
    timeZone: row.time_zone,
    avatarKey: row.avatar_key ?? "person_blue",
    presentationIntent: row.presentation_intent ?? null,
    onboardingCompleted: row.onboarding_completed_at_utc != null,
    onboardingCompletedAtUtc: row.onboarding_completed_at_utc == null
      ? null
      : iso(row.onboarding_completed_at_utc),
    wellMateFirstValueState: row.wellmate_first_value_state ?? null,
    version: Number(row.version),
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}
