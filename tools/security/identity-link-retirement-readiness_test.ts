import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "npm:postgres@3.4.7";
import { deriveIdentityLinkToken } from "../../supabase/functions/lifemate-api/identity_link_token.ts";
import { assessIdentityRetirementReadiness } from "./identity-link-retirement-readiness.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for identity retirement readiness tests.",
  );
}

const sql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name:
    "retirement readiness requires the exact canonical token for every active Account",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserId = crypto.randomUUID();
    const authSubject = crypto.randomUUID();
    const key = "0123456789abcdef0123456789abcdef";
    const keyVersion = 11;

    try {
      await sql`
        insert into lifemate.app_users(
          id,auth_subject,status,created_at_utc,updated_at_utc
        ) values(
          ${appUserId}::uuid,${authSubject},'Active',now(),now()
        )
      `;

      const before = await assessIdentityRetirementReadiness({
        databaseUrl,
        externalKey: key,
        keyVersion,
      });
      assertEquals(before.activeAccounts, 1);
      assertEquals(before.tokenizedAccounts, 0);
      assertEquals(before.missingCanonicalTokens, 1);
      assertEquals(before.readyForTokenOnly, false);

      const token = await deriveIdentityLinkToken(key, {
        provider: "supabase_auth",
        issuer: "supabase",
        subject: authSubject,
        keyVersion,
      });
      await sql`
        insert into identity.external_identity_tokens(
          account_id,provider,issuer,subject_token,key_version,status,
          created_at_utc,last_authenticated_at_utc
        ) values(
          ${appUserId}::uuid,'supabase_auth','supabase',${token},
          ${keyVersion},'Active',now(),now()
        )
      `;

      const after = await assessIdentityRetirementReadiness({
        databaseUrl,
        externalKey: key,
        keyVersion,
      });
      assertEquals(after.activeAccounts, 1);
      assertEquals(after.tokenizedAccounts, 1);
      assertEquals(after.missingCanonicalTokens, 0);
      assertEquals(after.conflictingCanonicalTokens, 0);
      assertEquals(after.unmappedActiveAccounts, 0);
      assertEquals(after.readyForTokenOnly, true);
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
