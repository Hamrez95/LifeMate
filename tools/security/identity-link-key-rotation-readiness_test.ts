import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "npm:postgres@3.4.7";
import { assessIdentityLinkRotationReadiness } from "./identity-link-key-rotation-readiness.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for identity-link rotation readiness tests.",
  );
}

Deno.test({
  name: "rotation readiness stays count-only and fails closed until every active Account has exactly one active-version token",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const sql = postgres(databaseUrl, { max: 1, prepare: false });
    const appUserA = crypto.randomUUID();
    const appUserB = crypto.randomUUID();
    const appUserC = crypto.randomUUID();
    const activeVersion = 8;

    try {
      for (const [id, subject] of [
        [appUserA, `rotation-ready-a-${crypto.randomUUID()}`],
        [appUserB, `rotation-ready-b-${crypto.randomUUID()}`],
        [appUserC, `rotation-ready-c-${crypto.randomUUID()}`],
      ]) {
        await sql`
          insert into lifemate.app_users(
            id,auth_subject,status,created_at_utc,updated_at_utc
          ) values(${id}::uuid,${subject},'Active',now(),now())
        `;
      }

      await sql`
        insert into identity.external_identity_tokens(
          account_id,provider,issuer,subject_token,key_version,status,
          created_at_utc,last_authenticated_at_utc
        ) values
          (${appUserA}::uuid,'supabase_auth','supabase',${"a".repeat(64)},${activeVersion},'Active',now(),now()),
          (${appUserB}::uuid,'supabase_auth','supabase',${"b".repeat(64)},${activeVersion - 1},'Active',now(),now()),
          (${appUserC}::uuid,'supabase_auth','supabase',${"c".repeat(64)},${activeVersion},'Active',now(),now()),
          (${appUserC}::uuid,'supabase_auth','supabase',${"d".repeat(64)},${activeVersion},'Active',now(),now())
      `;

      const blocked = await assessIdentityLinkRotationReadiness({
        databaseUrl,
        activeVersion,
      });
      assertEquals(blocked.activeVersion, activeVersion);
      assertEquals(blocked.activeAccounts, 3);
      assertEquals(blocked.currentVersionReadyAccounts, 1);
      assertEquals(blocked.missingActiveVersionTokens, 1);
      assertEquals(blocked.multipleActiveVersionTokens, 1);
      assertEquals(blocked.unmappedActiveAccounts, 0);
      assertEquals(blocked.readyForPreviousKeyRemoval, false);

      await sql`
        delete from identity.external_identity_tokens
        where account_id=${appUserC}::uuid
          and provider='supabase_auth'
          and issuer='supabase'
          and key_version=${activeVersion}
          and subject_token=${"d".repeat(64)}
      `;
      await sql`
        insert into identity.external_identity_tokens(
          account_id,provider,issuer,subject_token,key_version,status,
          created_at_utc,last_authenticated_at_utc
        ) values(
          ${appUserB}::uuid,'supabase_auth','supabase',${"e".repeat(64)},
          ${activeVersion},'Active',now(),now()
        )
      `;

      const ready = await assessIdentityLinkRotationReadiness({
        databaseUrl,
        activeVersion,
      });
      assertEquals(ready.activeAccounts, 3);
      assertEquals(ready.currentVersionReadyAccounts, 3);
      assertEquals(ready.missingActiveVersionTokens, 0);
      assertEquals(ready.multipleActiveVersionTokens, 0);
      assertEquals(ready.unmappedActiveAccounts, 0);
      assertEquals(ready.readyForPreviousKeyRemoval, true);
    } finally {
      await sql`
        delete from identity.external_identity_tokens
        where account_id in (
          ${appUserA}::uuid,${appUserB}::uuid,${appUserC}::uuid
        )
      `.catch(() => undefined);
      await sql`
        delete from identity.external_identities
        where account_id in (
          ${appUserA}::uuid,${appUserB}::uuid,${appUserC}::uuid
        )
      `.catch(() => undefined);
      await sql`
        update identity.accounts
        set legacy_app_user_id=null,updated_at_utc=now()
        where id in (${appUserA}::uuid,${appUserB}::uuid,${appUserC}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from identity.accounts
        where id in (${appUserA}::uuid,${appUserB}::uuid,${appUserC}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.app_users
        where id in (${appUserA}::uuid,${appUserB}::uuid,${appUserC}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from core.person_profiles
        where person_id in (${appUserA}::uuid,${appUserB}::uuid,${appUserC}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from core.persons
        where id in (${appUserA}::uuid,${appUserB}::uuid,${appUserC}::uuid)
      `.catch(() => undefined);
      await sql.end({ timeout: 5 });
    }
  },
});
