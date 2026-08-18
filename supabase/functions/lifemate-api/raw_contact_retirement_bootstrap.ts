import { createContactPointWriter } from "./contact_points.ts";
import { getLifeMateSql } from "./database_client.ts";
import type { AuthUser } from "./database_legacy.ts";
import { ApiError, normalizeOptional, requiredTimeZone } from "./validation.ts";

export function createRawContactRetirementBootstrapStore(
  databaseUrl: string,
  contactHashingSecret: string,
) {
  const sql = getLifeMateSql(databaseUrl);
  const contactPoints = createContactPointWriter(contactHashingSecret);
  if (!contactPoints.rawRetirementEnabled) {
    throw new Error(
      "Raw-contact retirement bootstrap must only run when LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT=true.",
    );
  }

  async function bootstrapUser(
    auth: AuthUser,
    body: Record<string, unknown>,
  ): Promise<string> {
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
      // The existing AppUser foundation trigger creates/refreshes Account + Self
      // Person inside this exact transaction before ContactPoint synchronization.
      const users = await tx`
        insert into lifemate.app_users
          (id, auth_subject, status, created_at_utc, updated_at_utc)
        values
          (${crypto.randomUUID()}, ${auth.id}, 'Active', ${now}, ${now})
        on conflict (auth_subject) do update
          set updated_at_utc = excluded.updated_at_utc
        returning id
      `;
      const appUserId = users[0]?.id;
      if (typeof appUserId !== "string" || appUserId.length === 0) {
        throw new ApiError(
          409,
          "identity_account_mapping_missing",
          "The LifeMate account mapping is unavailable.",
        );
      }

      // Raw email/phone compatibility storage is deliberately never populated
      // in retirement mode. Re-bootstrap also clears a pre-existing legacy
      // value in the same transaction that verifies canonical ContactPoints.
      await tx`
        insert into lifemate.user_profiles
          (id, user_id, display_name, phone_number, email, locale, time_zone,
           created_at_utc, updated_at_utc)
        values
          (${crypto.randomUUID()}, ${appUserId}, ${displayName}, null, null,
           ${locale}, ${timeZone}, ${now}, ${now})
        on conflict (user_id) do update set
          display_name = coalesce(
            nullif(lifemate.user_profiles.display_name, ''),
            excluded.display_name
          ),
          phone_number = null,
          email = null,
          locale = excluded.locale,
          time_zone = excluded.time_zone,
          updated_at_utc = excluded.updated_at_utc
      `;

      // Bootstrap/auth synchronization may seed an empty canonical kind, but it
      // must never overwrite a later explicit Profile contact with a different
      // auth snapshot. This is the same `if-missing` invariant used by the
      // identity bridge, now inside the bootstrap transaction.
      await contactPoints.syncForLegacyAppUser(
        tx,
        appUserId,
        { email: auth.email, phone: auth.phone },
        "if-missing",
      );

      await tx`
        insert into lifemate.audit_logs
          (id, actor_user_id, action, resource_type, resource_id,
           metadata_json, created_at_utc)
        values
          (${crypto.randomUUID()}, ${appUserId}, 'user.bootstrap',
           'app_user', ${appUserId}, null, now())
      `;
      return appUserId;
    });
  }

  return { bootstrapUser };
}
