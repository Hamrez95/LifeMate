import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "npm:postgres@3.4.7";
import { backfillIdentityLinkTokens } from "./identity-link-token-backfill.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required for identity-token backfill tests.");
}

const sql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name: "identity token backfill is dry-run safe and apply is idempotent",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserId = crypto.randomUUID();
    const authSubject = crypto.randomUUID();
    const key = "abcdef0123456789abcdef0123456789";
    const keyVersion = 9;

    try {
      await sql`
        insert into lifemate.app_users(
          id,auth_subject,status,created_at_utc,updated_at_utc
        ) values(
          ${appUserId}::uuid,${authSubject},'Active',now(),now()
        )
      `;
      await sql`
        insert into identity.external_identities(
          account_id,provider,issuer,provider_subject,status,
          created_at_utc,last_authenticated_at_utc
        ) values(
          ${appUserId}::uuid,'email','supabase',${authSubject},'Active',
          now(),now()
        )
      `;

      const dryRun = await backfillIdentityLinkTokens({
        databaseUrl,
        externalKey: key,
        keyVersion,
        mode: "dry-run",
      });
      assertEquals(dryRun.mode, "dry-run");
      assertEquals(dryRun.canonicalAccounts, 1);
      assertEquals(dryRun.providerIdentities, 2);
      assertEquals(dryRun.plannedTokens, 2);
      assertEquals(dryRun.insertedOrRefreshed, 0);

      const beforeApply = await sql`
        select count(*)::int as count
        from identity.external_identity_tokens
        where account_id=${appUserId}::uuid and key_version=${keyVersion}
      `;
      assertEquals(Number(beforeApply[0].count), 0);

      const firstApply = await backfillIdentityLinkTokens({
        databaseUrl,
        externalKey: key,
        keyVersion,
        mode: "apply",
      });
      assertEquals(firstApply.plannedTokens, 2);
      assertEquals(firstApply.insertedOrRefreshed, 2);

      const secondApply = await backfillIdentityLinkTokens({
        databaseUrl,
        externalKey: key,
        keyVersion,
        mode: "apply",
      });
      assertEquals(secondApply.plannedTokens, 2);
      assertEquals(secondApply.insertedOrRefreshed, 2);

      const stored = await sql`
        select provider,issuer,key_version,status,length(subject_token) as token_length
        from identity.external_identity_tokens
        where account_id=${appUserId}::uuid and key_version=${keyVersion}
        order by provider
      `;
      assertEquals(
        stored.map((row) => ({
          provider: row.provider,
          issuer: row.issuer,
          keyVersion: Number(row.key_version),
          status: row.status,
          tokenLength: Number(row.token_length),
        })),
        [
          {
            provider: "email",
            issuer: "supabase",
            keyVersion,
            status: "Active",
            tokenLength: 64,
          },
          {
            provider: "supabase_auth",
            issuer: "supabase",
            keyVersion,
            status: "Active",
            tokenLength: 64,
          },
        ],
      );
    } finally {
      await sql`
        delete from identity.external_identity_tokens
        where account_id=${appUserId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from identity.external_identities
        where account_id=${appUserId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from identity.accounts where id=${appUserId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from lifemate.app_users where id=${appUserId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from core.persons where id=${appUserId}::uuid
      `.catch(() => undefined);
    }
  },
});
