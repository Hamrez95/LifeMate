import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createIdentityBridge } from "./identity_bridge.ts";
import { deriveIdentityLinkToken } from "./identity_link_token.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for identity-link integration tests.",
  );
}

const sql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name: "external identity token storage cannot persist raw provider subjects",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const accountA = crypto.randomUUID();
    const accountB = crypto.randomUUID();
    const token = "a".repeat(64);

    try {
      const rawSubjectColumns = await sql`
        select column_name
        from information_schema.columns
        where table_schema='identity'
          and table_name='external_identity_tokens'
          and column_name in ('provider_subject','auth_subject','email','phone')
      `;
      assertEquals(rawSubjectColumns.length, 0);

      await sql`
        insert into identity.accounts(id,status)
        values (${accountA}::uuid,'Active'),(${accountB}::uuid,'Active')
      `;
      await sql`
        insert into identity.external_identity_tokens(
          account_id,provider,issuer,subject_token,key_version,status
        ) values(
          ${accountA}::uuid,'supabase_auth','supabase',${token},1,'Active'
        )
      `;

      const stored = await sql`
        select account_id,provider,issuer,subject_token,key_version,status
        from identity.external_identity_tokens
        where account_id=${accountA}::uuid
      `;
      assertEquals(String(stored[0].account_id), accountA);
      assertEquals(stored[0].provider, "supabase_auth");
      assertEquals(stored[0].issuer, "supabase");
      assertEquals(stored[0].subject_token, token);
      assertEquals(Number(stored[0].key_version), 1);
      assertEquals(stored[0].status, "Active");

      await assertRejects(
        () =>
          sql`
          insert into identity.external_identity_tokens(
            account_id,provider,issuer,subject_token,key_version,status
          ) values(
            ${accountB}::uuid,'supabase_auth','supabase',${token},1,'Active'
          )
        `,
        Error,
      );

      await assertRejects(
        () =>
          sql`
          insert into identity.external_identity_tokens(
            account_id,provider,issuer,subject_token,key_version,status
          ) values(
            ${accountB}::uuid,'supabase_auth','supabase','raw-subject',1,'Active'
          )
        `,
        Error,
      );

      await sql`
        update identity.accounts set status='Deleted',updated_at_utc=now()
        where id=${accountA}::uuid
      `;
      const afterDeletion = await sql`
        select count(*)::int as count
        from identity.external_identity_tokens
        where account_id=${accountA}::uuid
      `;
      assertEquals(Number(afterDeletion[0].count), 0);
    } finally {
      await sql`
        delete from identity.external_identity_tokens
        where account_id in (${accountA}::uuid,${accountB}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from identity.accounts
        where id in (${accountA}::uuid,${accountB}::uuid)
      `.catch(() => undefined);
    }
  },
});

Deno.test({
  name:
    "identity bridge resolves remapped Account and writes canonical auth token atomically",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserA = crypto.randomUUID();
    const remappedAccountA = crypto.randomUUID();
    const appUserB = crypto.randomUUID();
    const authSubject = crypto.randomUUID();
    const authSubjectB = crypto.randomUUID();
    const key = "0123456789abcdef0123456789abcdef";
    const keyVersion = 3;
    const previousDualWrite = Deno.env.get("LIFEMATE_IDENTITY_LINK_DUAL_WRITE");
    const previousKey = Deno.env.get("LIFEMATE_IDENTITY_LINK_KEY");
    const previousKeyVersion = Deno.env.get(
      "LIFEMATE_IDENTITY_LINK_KEY_VERSION",
    );

    try {
      Deno.env.set("LIFEMATE_IDENTITY_LINK_DUAL_WRITE", "true");
      Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY", key);
      Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY_VERSION", String(keyVersion));

      // The legacy compatibility trigger initially creates Account.id ==
      // AppUser.id. Remap A to a provider-agnostic Account UUID to prove the
      // bridge follows legacy_app_user_id instead of assuming UUID equality.
      await sql`
        insert into lifemate.app_users(
          id,auth_subject,status,created_at_utc,updated_at_utc
        ) values
          (${appUserA}::uuid,${authSubject},'Active',now(),now()),
          (${appUserB}::uuid,${authSubjectB},'Active',now(),now())
      `;
      await sql`
        update identity.accounts
        set legacy_app_user_id=null,updated_at_utc=now()
        where id=${appUserA}::uuid
      `;
      await sql`
        insert into identity.accounts(
          id,legacy_app_user_id,status,created_at_utc,updated_at_utc
        ) values(
          ${remappedAccountA}::uuid,${appUserA}::uuid,'Active',now(),now()
        )
      `;

      const identity = {
        provider: "email",
        identity_data: { sub: authSubject },
        created_at: "2026-08-15T00:00:00.000Z",
        last_sign_in_at: "2026-08-15T00:01:00.000Z",
      };
      const bridge = createIdentityBridge(databaseUrl);
      const providers = await bridge.syncExternalIdentities(appUserA, {
        id: authSubject,
        identities: [identity],
      });
      assertEquals(providers, ["email"]);

      const expectedCanonicalToken = await deriveIdentityLinkToken(key, {
        provider: "supabase_auth",
        issuer: "supabase",
        subject: authSubject,
        keyVersion,
      });
      const expectedProviderToken = await deriveIdentityLinkToken(key, {
        provider: "email",
        issuer: "supabase",
        subject: authSubject,
        keyVersion,
      });
      const tokenRows = await sql`
        select account_id,provider,issuer,subject_token,key_version,status
        from identity.external_identity_tokens
        where account_id=${remappedAccountA}::uuid
        order by provider
      `;
      assertEquals(tokenRows.length, 2);
      assertEquals(
        tokenRows.map((row) => ({
          accountId: String(row.account_id),
          provider: row.provider,
          issuer: row.issuer,
          subjectToken: row.subject_token,
          keyVersion: Number(row.key_version),
          status: row.status,
        })),
        [
          {
            accountId: remappedAccountA,
            provider: "email",
            issuer: "supabase",
            subjectToken: expectedProviderToken,
            keyVersion,
            status: "Active",
          },
          {
            accountId: remappedAccountA,
            provider: "supabase_auth",
            issuer: "supabase",
            subjectToken: expectedCanonicalToken,
            keyVersion,
            status: "Active",
          },
        ],
      );

      const legacyRows = await sql`
        select account_id,provider,issuer,provider_subject,status
        from identity.external_identities
        where account_id=${remappedAccountA}::uuid
          and provider='email'
      `;
      assertEquals(legacyRows.length, 1);
      assertEquals(String(legacyRows[0].account_id), remappedAccountA);
      assertEquals(legacyRows[0].provider_subject, authSubject);

      // Reuse A's authenticated subject through B. The canonical token conflict
      // must roll back before B acquires either a token or provider identity.
      const conflictingBridge = createIdentityBridge(databaseUrl);
      await assertRejects(
        () =>
          conflictingBridge.syncExternalIdentities(appUserB, {
            id: authSubject,
            identities: [identity],
          }),
        Error,
        "already linked to another LifeMate account",
      );

      const accountBTokenCount = await sql`
        select count(*)::int as count
        from identity.external_identity_tokens
        where account_id=${appUserB}::uuid
      `;
      const accountBEmailIdentityCount = await sql`
        select count(*)::int as count
        from identity.external_identities
        where account_id=${appUserB}::uuid and provider='email'
      `;
      assertEquals(Number(accountBTokenCount[0].count), 0);
      assertEquals(Number(accountBEmailIdentityCount[0].count), 0);
    } finally {
      await sql`
        delete from identity.external_identity_tokens
        where account_id in (
          ${appUserA}::uuid,${remappedAccountA}::uuid,${appUserB}::uuid
        )
      `.catch(() => undefined);
      await sql`
        delete from identity.external_identities
        where account_id in (
          ${appUserA}::uuid,${remappedAccountA}::uuid,${appUserB}::uuid
        )
      `.catch(() => undefined);
      await sql`
        delete from identity.accounts
        where id in (
          ${remappedAccountA}::uuid,${appUserA}::uuid,${appUserB}::uuid
        )
      `.catch(() => undefined);
      await sql`
        delete from lifemate.app_users
        where id in (${appUserA}::uuid,${appUserB}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from core.persons
        where id in (${appUserA}::uuid,${appUserB}::uuid)
      `.catch(() => undefined);

      if (previousDualWrite == null) {
        Deno.env.delete("LIFEMATE_IDENTITY_LINK_DUAL_WRITE");
      } else {
        Deno.env.set("LIFEMATE_IDENTITY_LINK_DUAL_WRITE", previousDualWrite);
      }
      if (previousKey == null) Deno.env.delete("LIFEMATE_IDENTITY_LINK_KEY");
      else Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY", previousKey);
      if (previousKeyVersion == null) {
        Deno.env.delete("LIFEMATE_IDENTITY_LINK_KEY_VERSION");
      } else {
        Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY_VERSION", previousKeyVersion);
      }
    }
  },
});
