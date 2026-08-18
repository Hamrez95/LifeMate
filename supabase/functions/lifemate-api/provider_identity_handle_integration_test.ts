import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import {
  decryptProviderIdentitySubject,
  type ProviderIdentityHandleEnvelope,
} from "../_shared/provider_identity_handle_crypto.ts";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { createIdentityBridge } from "./identity_bridge.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for provider-handle integration tests.",
  );
}

Deno.test({
  name: "identity bridge dual-writes opaque recoverable provider handle",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const authSubject = crypto.randomUUID();
    const auth: AuthUser = {
      id: authSubject,
      email: `provider-handle-${authSubject}@example.test`,
      phone: null,
      userMetadata: {},
    };
    const tokenKey = "provider-handle-token-test-key-32-bytes-minimum";
    const handleKey = "provider-handle-envelope-test-key-32-bytes-minimum";
    const tokenKeyVersion = 5;
    const handleKeyVersion = 6;
    const previous = new Map<string, string | undefined>();
    const names = [
      "LIFEMATE_IDENTITY_LINK_DUAL_WRITE",
      "LIFEMATE_IDENTITY_LINK_KEY",
      "LIFEMATE_IDENTITY_LINK_KEY_VERSION",
      "LIFEMATE_IDENTITY_PROVIDER_HANDLE_DUAL_WRITE",
      "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY",
      "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION",
    ];
    for (const name of names) previous.set(name, Deno.env.get(name));
    let appUserId: string | null = null;

    try {
      Deno.env.set("LIFEMATE_IDENTITY_LINK_DUAL_WRITE", "true");
      Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY", tokenKey);
      Deno.env.set(
        "LIFEMATE_IDENTITY_LINK_KEY_VERSION",
        String(tokenKeyVersion),
      );
      Deno.env.set("LIFEMATE_IDENTITY_PROVIDER_HANDLE_DUAL_WRITE", "true");
      Deno.env.set("LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY", handleKey);
      Deno.env.set(
        "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION",
        String(handleKeyVersion),
      );

      const db = createLifeMateDatabase(
        databaseUrl,
        "integration-only-provider-handle-contact-secret-32-bytes",
      );
      await db.bootstrapUser(auth, {
        displayName: "Provider Handle",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const rows = await admin`
        select id::text as id
        from lifemate.app_users
        where auth_subject=${authSubject}
      `;
      appUserId = String(rows[0]?.id ?? "");
      if (!appUserId) throw new Error("provider-handle AppUser missing");

      const bridge = createIdentityBridge(databaseUrl);
      await bridge.syncExternalIdentities(appUserId, {
        id: authSubject,
        identities: [],
      });

      const accountRows = await admin`
        select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
          as account_id
      `;
      const accountId = String(accountRows[0]?.account_id ?? "");
      const handleRows = await admin`
        select ciphertext_b64,nonce_b64,key_version,status
        from identity.provider_identity_handles
        where account_id=${accountId}::uuid
          and provider='supabase_auth'
          and issuer='supabase'
      `;
      assertEquals(handleRows.length, 1);
      assertEquals(handleRows[0]?.status, "Active");
      assertEquals(Number(handleRows[0]?.key_version), handleKeyVersion);
      assertEquals(
        String(handleRows[0]?.ciphertext_b64).includes(authSubject),
        false,
      );

      const envelope: ProviderIdentityHandleEnvelope = {
        ciphertextB64: String(handleRows[0]?.ciphertext_b64),
        nonceB64: String(handleRows[0]?.nonce_b64),
        keyVersion: Number(handleRows[0]?.key_version),
      };
      assertEquals(
        await decryptProviderIdentitySubject(
          { secret: handleKey, keyVersion: handleKeyVersion },
          { accountId, provider: "supabase_auth", issuer: "supabase" },
          envelope,
        ),
        authSubject,
      );

      const tokenRows = await admin`
        select count(*)::int as count
        from identity.external_identity_tokens
        where account_id=${accountId}::uuid
          and provider='supabase_auth'
          and issuer='supabase'
          and status='Active'
      `;
      assertEquals(Number(tokenRows[0]?.count), 1);

      // This slice is additive: raw compatibility still exists until protected
      // backfill/readiness evidence permits the following retirement slice.
      const rawRows = await admin`
        select auth_subject
        from lifemate.app_users
        where id=${appUserId}::uuid
      `;
      assertEquals(rawRows[0]?.auth_subject, authSubject);

      const forbiddenColumns = await admin`
        select column_name
        from information_schema.columns
        where table_schema='identity'
          and table_name='provider_identity_handles'
          and column_name in (
            'auth_subject','provider_subject','email','phone','encryption_key'
          )
      `;
      assertEquals(forbiddenColumns.length, 0);
    } finally {
      if (appUserId) {
        await admin`
          delete from identity.provider_identity_handles
          where account_id in (
            select id from identity.accounts
            where legacy_app_user_id=${appUserId}::uuid or id=${appUserId}::uuid
          )
        `.catch(() => undefined);
        await admin`
          delete from identity.external_identity_tokens
          where account_id in (
            select id from identity.accounts
            where legacy_app_user_id=${appUserId}::uuid or id=${appUserId}::uuid
          )
        `.catch(() => undefined);
        await admin`
          delete from lifemate.audit_logs
          where actor_user_id=${appUserId}::uuid
             or resource_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.user_profiles where user_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from identity.external_identities
          where account_id in (
            select id from identity.accounts
            where legacy_app_user_id=${appUserId}::uuid or id=${appUserId}::uuid
          )
        `.catch(() => undefined);
        await admin`
          delete from commerce.entitlements
          where grantee_account_id in (
            select id from identity.accounts
            where legacy_app_user_id=${appUserId}::uuid or id=${appUserId}::uuid
          ) or beneficiary_person_id in (
            select person_id from core.account_person_links
            where account_id in (
              select id from identity.accounts
              where legacy_app_user_id=${appUserId}::uuid or id=${appUserId}::uuid
            )
          )
        `.catch(() => undefined);
        await admin`
          delete from ecosystem.app_enrollments
          where account_id in (
            select id from identity.accounts
            where legacy_app_user_id=${appUserId}::uuid or id=${appUserId}::uuid
          )
        `.catch(() => undefined);
        await admin`
          delete from core.account_person_links
          where account_id in (
            select id from identity.accounts
            where legacy_app_user_id=${appUserId}::uuid or id=${appUserId}::uuid
          )
        `.catch(() => undefined);
        await admin`
          delete from identity.accounts
          where legacy_app_user_id=${appUserId}::uuid or id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.app_users where id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.person_profiles where person_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.persons where id=${appUserId}::uuid
        `.catch(() => undefined);
      }
      for (const [name, value] of previous) {
        if (value == null) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
      await admin.end({ timeout: 5 });
    }
  },
});
