import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import {
  encryptProviderIdentitySubject,
} from "../_shared/provider_identity_handle_crypto.ts";
import {
  createProviderAuthSubjectResolver,
} from "../lifemate-worker/provider_auth_subject.ts";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { createIdentityBridge } from "./identity_bridge.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for provider-handle key-rotation integration tests.",
  );
}

const envNames = [
  "LIFEMATE_IDENTITY_LINK_DUAL_WRITE",
  "LIFEMATE_IDENTITY_LINK_KEY",
  "LIFEMATE_IDENTITY_LINK_KEY_VERSION",
  "LIFEMATE_IDENTITY_PROVIDER_HANDLE_DUAL_WRITE",
  "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY",
  "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION",
  "LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY",
  "LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION",
  "LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT",
] as const;

Deno.test({
  name:
    "provider-handle overlap keeps API writes active-only and Worker recovery previous-key aware after raw retirement",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const saved = new Map<string, string | undefined>();
    for (const name of envNames) saved.set(name, Deno.env.get(name));

    const tokenKey = "provider-handle-rotation-token-key-32-bytes-minimum";
    const activeKey = {
      secret: "provider-handle-rotation-active-runtime-key-32-bytes-minimum",
      keyVersion: 112,
    };
    const previousKey = {
      secret: "provider-handle-rotation-previous-runtime-key-32-bytes-minimum",
      keyVersion: 111,
    };
    const authSubject = crypto.randomUUID();
    const auth: AuthUser = {
      id: authSubject,
      email: `provider-rotation-${authSubject}@example.test`,
      phone: null,
      userMetadata: {},
    };
    let appUserId: string | null = null;
    let accountId: string | null = null;

    try {
      Deno.env.set("LIFEMATE_IDENTITY_LINK_DUAL_WRITE", "true");
      Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY", tokenKey);
      Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY_VERSION", "7");
      Deno.env.set("LIFEMATE_IDENTITY_PROVIDER_HANDLE_DUAL_WRITE", "true");
      Deno.env.set("LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY", activeKey.secret);
      Deno.env.set(
        "LIFEMATE_IDENTITY_PROVIDER_HANDLE_KEY_VERSION",
        String(activeKey.keyVersion),
      );
      Deno.env.set(
        "LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY",
        previousKey.secret,
      );
      Deno.env.set(
        "LIFEMATE_IDENTITY_PROVIDER_HANDLE_PREVIOUS_KEY_VERSION",
        String(previousKey.keyVersion),
      );
      Deno.env.set("LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT", "false");

      const db = createLifeMateDatabase(
        databaseUrl,
        "provider-handle-rotation-contact-secret-32-bytes-minimum",
      );
      await db.bootstrapUser(auth, {
        displayName: "Provider Handle Rotation",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const identity = await db.requireIdentity(auth);
      appUserId = identity.appUserId;
      const accountRows = await admin`
        select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
          as account_id
      `;
      accountId = String(accountRows[0]?.account_id ?? "");
      if (!accountId) throw new Error("provider-handle Account missing");

      const bridge = createIdentityBridge(databaseUrl);
      await bridge.syncExternalIdentities(appUserId, {
        id: authSubject,
        identities: [],
      });
      const written = await admin`
        select key_version,status
        from identity.provider_identity_handles
        where account_id=${accountId}::uuid
          and provider='supabase_auth' and issuer='supabase'
      `;
      assertEquals(written.length, 1);
      assertEquals(Number(written[0]?.key_version), activeKey.keyVersion);
      assertEquals(written[0]?.status, "Active");

      const previousEnvelope = await encryptProviderIdentitySubject(
        previousKey,
        {
          accountId,
          provider: "supabase_auth",
          issuer: "supabase",
        },
        authSubject,
      );
      await admin`
        update identity.provider_identity_handles
        set ciphertext_b64=${previousEnvelope.ciphertextB64},
            nonce_b64=${previousEnvelope.nonceB64},
            key_version=${previousEnvelope.keyVersion},
            updated_at_utc=now()
        where account_id=${accountId}::uuid
          and provider='supabase_auth' and issuer='supabase'
      `;
      await admin`
        update lifemate.app_users
        set auth_subject=null,updated_at_utc=now()
        where id=${appUserId}::uuid
      `;
      Deno.env.set("LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT", "true");

      const resolver = createProviderAuthSubjectResolver(admin);
      assertEquals(await resolver.resolve(accountId), authSubject);

      await admin`
        update identity.provider_identity_handles
        set key_version=${activeKey.keyVersion + 1},updated_at_utc=now()
        where account_id=${accountId}::uuid
          and provider='supabase_auth' and issuer='supabase'
      `;
      await assertRejects(
        () => resolver.resolve(accountId!),
        Error,
        "provider_handle_decrypt_failed",
      );
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
        await admin`
          delete from core.account_person_links
          where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from ecosystem.app_enrollments
          where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from commerce.entitlements
          where grantee_account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          update identity.accounts
          set legacy_app_user_id=null,updated_at_utc=now()
          where id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from identity.accounts where id=${accountId}::uuid
        `.catch(() => undefined);
      }
      if (appUserId) {
        await admin`
          delete from lifemate.audit_logs
          where actor_user_id=${appUserId}::uuid or resource_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.user_profiles where user_id=${appUserId}::uuid
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
      for (const name of envNames) {
        const value = saved.get(name);
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
      await admin.end({ timeout: 5 });
    }
  },
});
