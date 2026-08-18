import { createContactPointWriter } from "./contact_points.ts";
import { getLifeMateSql } from "./database_client.ts";
import { identityLinkDualWriteEnabled } from "./identity_bridge.ts";
import {
  deriveIdentityLinkToken,
  readIdentityLinkKeyFromEnvironment,
} from "./identity_link_token.ts";
import { ApiError, normalizeOptional, requiredTimeZone } from "./validation.ts";

type RetirementAuthUser = {
  id: string;
  email: string | null;
  phone: string | null;
  userMetadata: Record<string, unknown>;
};

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

  const identityLookupMode =
    (Deno.env.get("LIFEMATE_IDENTITY_LINK_LOOKUP_MODE") ?? "legacy")
      .trim()
      .toLowerCase();
  if (identityLookupMode !== "token-only") {
    throw new Error(
      "Raw Profile contact retirement bootstrap requires LIFEMATE_IDENTITY_LINK_LOOKUP_MODE=token-only so new accounts never need a raw authentication lookup value.",
    );
  }
  if (!identityLinkDualWriteEnabled()) {
    throw new Error(
      "Raw Profile contact retirement bootstrap requires LIFEMATE_IDENTITY_LINK_DUAL_WRITE=true.",
    );
  }
  const identityLinkKey = readIdentityLinkKeyFromEnvironment();

  async function bootstrapUser(
    auth: RetirementAuthUser,
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
    const appUserId = crypto.randomUUID();
    const subjectToken = await deriveIdentityLinkToken(identityLinkKey.secret, {
      provider: "supabase_auth",
      issuer: "supabase",
      subject: auth.id,
      keyVersion: identityLinkKey.keyVersion,
    });

    return await sql.begin(async (tx: any) => {
      // New retirement-mode AppUsers start without a raw authentication lookup
      // value. The existing foundation trigger still creates Account + Self
      // Person from the AppUser id/status inside this same transaction.
      await tx`
        insert into lifemate.app_users
          (id, status, created_at_utc, updated_at_utc)
        values
          (${appUserId}::uuid, 'Active', ${now}, ${now})
      `;

      const accountRows = await tx`
        select identity.account_id_for_legacy_app_user(
          ${appUserId}::uuid
        )::text as account_id
      `;
      const accountId = accountRows[0]?.account_id;
      if (typeof accountId !== "string" || accountId.length === 0) {
        throw new ApiError(
          409,
          "identity_account_mapping_missing",
          "The LifeMate account mapping is unavailable.",
        );
      }

      // Canonical authentication lookup is committed atomically with the new
      // compatibility AppUser. Concurrent first-bootstrap attempts converge on
      // the unique token; a token already owned by another Account rolls this
      // entire transaction back instead of creating a duplicate account.
      const tokenRows = await tx`
        insert into identity.external_identity_tokens(
          account_id,provider,issuer,subject_token,key_version,
          created_at_utc,last_authenticated_at_utc,status
        ) values(
          ${accountId}::uuid,'supabase_auth','supabase',${subjectToken},
          ${identityLinkKey.keyVersion},${now},${now},'Active'
        )
        on conflict(provider,issuer,key_version,subject_token) do update set
          last_authenticated_at_utc=greatest(
            identity.external_identity_tokens.last_authenticated_at_utc,
            excluded.last_authenticated_at_utc
          ),
          status='Active'
        where identity.external_identity_tokens.account_id=excluded.account_id
        returning account_id::text as account_id
      `;
      if (tokenRows[0]?.account_id !== accountId) {
        throw new ApiError(
          409,
          "external_identity_token_account_conflict",
          "This external identity is already linked to another LifeMate account.",
        );
      }

      // Raw email/phone compatibility storage is deliberately never populated
      // in retirement mode. Re-bootstrap is resolved by the canonical identity
      // token before this store is called, so there is no plaintext re-seeding.
      await tx`
        insert into lifemate.user_profiles
          (id, user_id, display_name, phone_number, email, locale, time_zone,
           created_at_utc, updated_at_utc)
        values
          (${crypto.randomUUID()}, ${appUserId}::uuid, ${displayName}, null, null,
           ${locale}, ${timeZone}, ${now}, ${now})
      `;

      // Bootstrap/auth synchronization may seed an empty canonical kind, but it
      // must never overwrite a later explicit Profile contact with a different
      // auth snapshot. This is the same `if-missing` invariant used by the
      // identity bridge, now inside the bootstrap transaction.
      await contactPoints.syncForAccount(
        tx,
        accountId,
        { email: auth.email, phone: auth.phone },
        "if-missing",
      );

      await tx`
        insert into lifemate.audit_logs
          (id, actor_user_id, action, resource_type, resource_id,
           metadata_json, created_at_utc)
        values
          (${crypto.randomUUID()}, ${appUserId}::uuid, 'user.bootstrap',
           'app_user', ${appUserId}::uuid, null, now())
      `;
      return appUserId;
    });
  }

  return { bootstrapUser };
}
