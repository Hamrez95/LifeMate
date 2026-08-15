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
    "identity bridge dual-writes token and legacy subject atomically during migration",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const accountA = crypto.randomUUID();
    const accountB = crypto.randomUUID();
    const authSubject = crypto.randomUUID();
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

      await sql`
        insert into identity.accounts(id,status)
        values (${accountA}::uuid,'Active'),(${accountB}::uuid,'Active')
      `;

      const identity = {
        provider: "email",
        identity_data: { sub: authSubject },
        created_at: "2026-08-15T00:00:00.000Z",
        last_sign_in_at: "2026-08-15T00:01:00.000Z",
      };
      const bridge = createIdentityBridge(databaseUrl);
      const providers = await bridge.syncExternalIdentities(accountA, {
        id: authSubject,
        identities: [identity],
      });
      assertEquals(providers, ["email"]);

      const expectedToken = await deriveIdentityLinkToken(key, {
        provider: "email",
        issuer: "supabase",
        subject: authSubject,
        keyVersion,
      });
      const tokenRows = await sql`
        select account_id,provider,issuer,subject_token,key_version,status
        from identity.external_identity_tokens
        where account_id=${accountA}::uuid
      `;
      assertEquals(tokenRows.length, 1);
      assertEquals(String(tokenRows[0].account_id), accountA);
      assertEquals(tokenRows[0].provider, "email");
      assertEquals(tokenRows[0].issuer, "supabase");
      assertEquals(tokenRows[0].subject_token, expectedToken);
      assertEquals(Number(tokenRows[0].key_version), keyVersion);
      assertEquals(tokenRows[0].status, "Active");

      const legacyRows = await sql`
        select account_id,provider,issuer,provider_subject,status
        from identity.external_identities
        where account_id=${accountA}::uuid
      `;
      assertEquals(legacyRows.length, 1);
      assertEquals(String(legacyRows[0].account_id), accountA);
      assertEquals(legacyRows[0].provider_subject, authSubject);

      const conflictingBridge = createIdentityBridge(databaseUrl);
      await assertRejects(
        () =>
          conflictingBridge.syncExternalIdentities(accountB, {
            id: authSubject,
            identities: [identity],
          }),
        Error,
        "already linked to another LifeMate account",
      );

      const accountBTokenCount = await sql`
        select count(*)::int as count
        from identity.external_identity_tokens
        where account_id=${accountB}::uuid
      `;
      const accountBLegacyCount = await sql`
        select count(*)::int as count
        from identity.external_identities
        where account_id=${accountB}::uuid
      `;
      assertEquals(Number(accountBTokenCount[0].count), 0);
      assertEquals(Number(accountBLegacyCount[0].count), 0);
    } finally {
      await sql`
        delete from identity.external_identity_tokens
        where account_id in (${accountA}::uuid,${accountB}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from identity.external_identities
        where account_id in (${accountA}::uuid,${accountB}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from identity.accounts
        where id in (${accountA}::uuid,${accountB}::uuid)
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
