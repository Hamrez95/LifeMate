import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createProviderAuthSubjectResolver } from "../lifemate-worker/provider_auth_subject.ts";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { createIdentityBridge } from "./identity_bridge.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for raw identity retirement integration tests.",
  );
}

Deno.test({
  name: "token-only retirement removes raw subjects without breaking runtime",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const authSubject = crypto.randomUUID();
    const providerSubject = `google-${crypto.randomUUID()}`;
    const auth: AuthUser = {
      id: authSubject,
      email: `raw-retirement-${authSubject}@example.test`,
      phone: null,
      userMetadata: {},
    };
    const tokenKey = "raw-retirement-token-test-key-32-bytes-minimum";
    const handleKey = "raw-retirement-handle-test-key-32-bytes-minimum";
    const tokenKeyVersion = 13;
    const handleKeyVersion = 14;
    const names = [
      "LIFEMATE_IDENTITY_LINK_LOOKUP_MODE",
      "LIFEMATE_IDENTITY_LINK_DUAL_WRITE",
      "LIFEMATE_IDENTITY_LINK_KEY",
      "LIFEMATE_IDENTITY_LINK_KEY_VERSION",
      "LIFEMATE_IDENTITY_PROVIDER_HANDLE_DUAL_WRITE",
      "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY",
      "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION",
      "LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT",
    ];
    const previous = new Map(
      names.map((name) => [name, Deno.env.get(name)] as const),
    );
    let appUserId: string | null = null;
    let accountId: string | null = null;

    try {
      Deno.env.set("LIFEMATE_IDENTITY_LINK_LOOKUP_MODE", "token-only");
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
      Deno.env.set("LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT", "true");

      const db = createLifeMateDatabase(
        databaseUrl,
        "integration-only-raw-retirement-contact-secret-32-bytes",
      );
      assertEquals(db.identityLookupMode, "token-only");

      // First bootstrap is the staged compatibility path. #353 guarantees that
      // after canonical tokenization repeated token-only bootstrap never returns
      // to this raw-subject insert/update path.
      await db.bootstrapUser(auth, {
        displayName: "Raw Retirement",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const appRows = await admin`
        select id::text as id
        from lifemate.app_users
        where auth_subject=${authSubject}
      `;
      appUserId = String(appRows[0]?.id ?? "");
      if (!appUserId) throw new Error("retirement bootstrap AppUser missing");

      const accountRows = await admin`
        select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
          as account_id
      `;
      accountId = String(accountRows[0]?.account_id ?? "");
      if (!accountId) throw new Error("retirement Account mapping missing");

      const beforeRaw = await admin`
        select auth_subject from lifemate.app_users where id=${appUserId}::uuid
      `;
      assertEquals(beforeRaw[0]?.auth_subject, authSubject);
      const beforeExternal = await admin`
        select count(*)::int as count
        from identity.external_identities
        where account_id=${accountId}::uuid
      `;
      assertEquals(Number(beforeExternal[0]?.count) >= 1, true);

      const bridge = createIdentityBridge(databaseUrl);
      const providers = await bridge.syncExternalIdentities(appUserId, {
        id: authSubject,
        identities: [{
          provider: "google",
          identity_data: { sub: providerSubject },
          created_at: new Date().toISOString(),
          last_sign_in_at: new Date().toISOString(),
        }],
      });
      assertEquals(providers, ["google"]);

      // Database-only breach proof for this fixture: raw canonical Auth/provider
      // subjects are gone, while opaque token + encrypted recovery state remain.
      const retired = await admin`
        select auth_subject
        from lifemate.app_users
        where id=${appUserId}::uuid
      `;
      assertEquals(retired[0]?.auth_subject, null);
      const rawExternal = await admin`
        select count(*)::int as count
        from identity.external_identities
        where account_id=${accountId}::uuid
      `;
      assertEquals(Number(rawExternal[0]?.count), 0);
      const tokenRows = await admin`
        select provider,issuer,subject_token,key_version
        from identity.external_identity_tokens
        where account_id=${accountId}::uuid and status='Active'
        order by provider,issuer
      `;
      assertEquals(tokenRows.length, 2);
      assertEquals(
        tokenRows.some((row) => row.provider === "supabase_auth"),
        true,
      );
      assertEquals(tokenRows.some((row) => row.provider === "google"), true);
      for (const row of tokenRows) {
        assertEquals(String(row.subject_token).includes(authSubject), false);
        assertEquals(String(row.subject_token).includes(providerSubject), false);
      }
      const handleRows = await admin`
        select ciphertext_b64,nonce_b64,key_version
        from identity.provider_identity_handles
        where account_id=${accountId}::uuid
          and provider='supabase_auth'
          and issuer='supabase'
          and status='Active'
      `;
      assertEquals(handleRows.length, 1);
      assertEquals(
        String(handleRows[0]?.ciphertext_b64).includes(authSubject),
        false,
      );

      // Token-only auth and current-user remain functional. authSubject is a
      // response compatibility field sourced from the JWT snapshot, not DB.
      const identity = await db.requireIdentity(auth);
      assertEquals(identity.appUserId, appUserId);
      const current = await db.currentUser(identity);
      const user = current.user as Record<string, unknown>;
      assertEquals(user.authSubject, authSubject);

      // The Worker can still recover the Supabase Auth UUID from the encrypted
      // external-key handle and never needs the now-null AppUser subject.
      const workerResolver = createProviderAuthSubjectResolver(admin);
      assertEquals(await workerResolver.resolve(accountId), authSubject);

      const beforeBootstrapAudits = await admin`
        select count(*)::int as count
        from lifemate.audit_logs
        where actor_user_id=${appUserId}::uuid and action='user.bootstrap'
      `;
      assertEquals(Number(beforeBootstrapAudits[0]?.count), 1);
      const repeated = await db.bootstrapUser(auth, {
        displayName: "must not recreate raw identity",
        locale: "en",
        timeZone: "Europe/Berlin",
      });
      const repeatedUser = repeated.user as Record<string, unknown>;
      assertEquals(repeatedUser.authSubject, authSubject);
      const afterBootstrapAudits = await admin`
        select count(*)::int as count
        from lifemate.audit_logs
        where actor_user_id=${appUserId}::uuid and action='user.bootstrap'
      `;
      assertEquals(Number(afterBootstrapAudits[0]?.count), 1);
      const afterRepeat = await admin`
        select auth_subject
        from lifemate.app_users
        where id=${appUserId}::uuid
      `;
      assertEquals(afterRepeat[0]?.auth_subject, null);
      const afterRepeatRaw = await admin`
        select count(*)::int as count
        from identity.external_identities
        where account_id=${accountId}::uuid
      `;
      assertEquals(Number(afterRepeatRaw[0]?.count), 0);

      // A later compatibility timestamp/status update must not recreate raw
      // external identity rows once auth_subject has been scrubbed.
      await admin`
        update lifemate.app_users
        set updated_at_utc=now()
        where id=${appUserId}::uuid
      `;
      const afterCompatibilityUpdate = await admin`
        select count(*)::int as count
        from identity.external_identities
        where account_id=${accountId}::uuid
      `;
      assertEquals(Number(afterCompatibilityUpdate[0]?.count), 0);
    } finally {
      if (accountId) {
        await admin`
          delete from identity.provider_identity_handles
          where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from identity.external_identity_tokens
          where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from identity.external_identities
          where account_id=${accountId}::uuid
        `.catch(() => undefined);
      }
      if (appUserId) {
        await admin`
          delete from lifemate.audit_logs
          where actor_user_id=${appUserId}::uuid
             or resource_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.user_profiles where user_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from commerce.entitlements
          where grantee_account_id=${accountId}::uuid
             or beneficiary_person_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from ecosystem.app_enrollments
          where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.account_person_links
          where account_id=${accountId}::uuid
             or person_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from identity.accounts where id=${accountId}::uuid
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
