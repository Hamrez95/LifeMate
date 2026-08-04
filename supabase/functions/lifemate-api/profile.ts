import postgres from "postgres";
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

export type ProfilePatch = {
  expectedVersion: number;
  displayName: string;
  phoneNumber: string | null;
  locale: string;
  timeZone: string;
  avatarKey: string | null;
};

export function normalizeProfilePatch(
  body: Record<string, unknown>,
): ProfilePatch {
  return {
    expectedVersion: requiredPositiveInt(body.version, "version"),
    displayName: requiredText(body.displayName, "displayName", 120),
    phoneNumber: optionalPhone(body.phoneNumber),
    locale: requiredLocale(body.locale),
    timeZone: requiredTimeZone(body.timeZone),
    avatarKey: optionalAvatarKey(body.avatarKey),
  };
}

/// Profile persistence deliberately supports both the current live schema and
/// the reviewed additive `version` migration. This lets the candidate function
/// be smoke-tested without applying DDL to the production database. Once the
/// migration is promoted, the exact same API automatically switches to the
/// integer version column. Before that, the millisecond `updated_at_utc` value
/// acts as a deterministic optimistic-concurrency token.
export function createProfileStore(databaseUrl: string) {
  const sql = postgres(databaseUrl, {
    max: 2,
    idle_timeout: 20,
    connect_timeout: 10,
    prepare: false,
  });
  let versionColumnPromise: Promise<boolean> | null = null;

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

  async function getProfile(userId: string): Promise<Record<string, unknown>> {
    const rows = await (await hasVersionColumn()
      ? sql`
          select id, user_id, display_name, phone_number, email, locale,
                 time_zone, avatar_key, version, created_at_utc, updated_at_utc
          from lifemate.user_profiles
          where user_id = ${userId}
          limit 1
        `
      : sql`
          select id, user_id, display_name, phone_number, email, locale,
                 time_zone, avatar_key,
                 floor(extract(epoch from updated_at_utc) * 1000)::bigint
                   as version,
                 created_at_utc, updated_at_utc
          from lifemate.user_profiles
          where user_id = ${userId}
          limit 1
        `);
    if (!rows[0]) {
      throw new ApiError(404, "profile_missing", "User profile was not found.");
    }
    return mapProfile(rows[0]);
  }

  async function updateProfile(
    userId: string,
    auth: ProfileAuthSnapshot,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const patch = normalizeProfilePatch(body);
    const usesVersionColumn = await hasVersionColumn();

    return await sql.begin(async (tx: any) => {
      const rows = await (usesVersionColumn
        ? tx`
            update lifemate.user_profiles
            set display_name = ${patch.displayName},
                phone_number = ${patch.phoneNumber},
                email = ${auth.email},
                locale = ${patch.locale},
                time_zone = ${patch.timeZone},
                avatar_key = coalesce(${patch.avatarKey}, avatar_key),
                version = version + 1,
                updated_at_utc = now()
            where user_id = ${userId} and version = ${patch.expectedVersion}
            returning id, user_id, display_name, phone_number, email, locale,
                      time_zone, avatar_key, version, created_at_utc,
                      updated_at_utc
          `
        : tx`
            update lifemate.user_profiles
            set display_name = ${patch.displayName},
                phone_number = ${patch.phoneNumber},
                email = ${auth.email},
                locale = ${patch.locale},
                time_zone = ${patch.timeZone},
                avatar_key = coalesce(${patch.avatarKey}, avatar_key),
                updated_at_utc = greatest(
                  now(),
                  updated_at_utc + interval '1 millisecond'
                )
            where user_id = ${userId}
              and floor(extract(epoch from updated_at_utc) * 1000)::bigint =
                  ${patch.expectedVersion}
            returning id, user_id, display_name, phone_number, email, locale,
                      time_zone, avatar_key,
                      floor(extract(epoch from updated_at_utc) * 1000)::bigint
                        as version,
                      created_at_utc, updated_at_utc
          `);
      if (!rows[0]) {
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

      // Privacy invariant: metadata_json, null; no profile or avatar values.
      await tx`
        insert into lifemate.audit_logs
          (id, actor_user_id, action, resource_type, resource_id,
           metadata_json, created_at_utc)
        values
          (${crypto.randomUUID()}, ${userId}, 'profile.updated',
           'user_profile', ${rows[0].id}, null, now())
      `;
      return mapProfile(rows[0]);
    });
  }

  return { getProfile, updateProfile };
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
