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

export function createProfileStore(databaseUrl: string) {
  const sql = postgres(databaseUrl, {
    max: 2,
    idle_timeout: 20,
    connect_timeout: 10,
    prepare: false,
  });

  async function getProfile(userId: string): Promise<Record<string, unknown>> {
    const rows = await sql`
      select id, user_id, display_name, phone_number, email, locale, time_zone,
             version, created_at_utc, updated_at_utc
      from lifemate.user_profiles
      where user_id = ${userId}
      limit 1
    `;
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
    const expectedVersion = requiredPositiveInt(body.version, "version");
    const displayName = requiredText(body.displayName, "displayName", 120);
    const locale = requiredLocale(body.locale);
    const timeZone = requiredTimeZone(body.timeZone);
    const phoneNumber = optionalPhone(body.phoneNumber);

    return await sql.begin(async (tx: any) => {
      const rows = await tx`
        update lifemate.user_profiles
        set display_name = ${displayName},
            phone_number = ${phoneNumber},
            email = ${auth.email},
            locale = ${locale},
            time_zone = ${timeZone},
            version = version + 1,
            updated_at_utc = now()
        where user_id = ${userId} and version = ${expectedVersion}
        returning id, user_id, display_name, phone_number, email, locale,
                  time_zone, version, created_at_utc, updated_at_utc
      `;
      if (!rows[0]) {
        const current = await tx`
          select version
          from lifemate.user_profiles
          where user_id = ${userId}
          limit 1
        `;
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

      await tx`
        insert into lifemate.audit_events
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
    version: row.version,
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}
