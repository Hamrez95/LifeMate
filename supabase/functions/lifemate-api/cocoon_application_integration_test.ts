import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createCocoonApplicationBoundary } from "./cocoon_application.ts";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Cocoon application tests.",
  );
}

const adminSql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name:
    "Cocoon enrollment resolves remapped canonical Account and does not create pregnancy or entitlement state",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserId = crypto.randomUUID();
    const accountId = crypto.randomUUID();
    const personId = crypto.randomUUID();
    const authSubject = `cocoon-app-${crypto.randomUUID()}`;
    const boundary = createCocoonApplicationBoundary(databaseUrl);

    try {
      await adminSql`
        insert into lifemate.app_users(
          id,auth_subject,status,created_at_utc,updated_at_utc
        ) values(
          ${appUserId}::uuid,${authSubject},'Active',now(),now()
        )
      `;
      // AppUser bootstrap compatibility may create an Account with the same id.
      // Detach the legacy pointer so this fixture proves Cocoon survives the
      // canonical Account != AppUser migration state.
      await adminSql`
        update identity.accounts
        set legacy_app_user_id=null,updated_at_utc=now()
        where id=${appUserId}::uuid
      `;
      await adminSql`
        insert into identity.accounts(
          id,legacy_app_user_id,status,created_at_utc,updated_at_utc
        ) values(
          ${accountId}::uuid,${appUserId}::uuid,'Active',now(),now()
        )
      `;
      await adminSql`
        insert into core.persons(id,status,subject_category)
        values(${personId}::uuid,'Active','Adult')
      `;
      await adminSql`
        insert into core.account_person_links(
          account_id,person_id,link_type,status,created_at_utc
        ) values(
          ${accountId}::uuid,${personId}::uuid,'Self','Active',now()
        )
      `;

      const before = await adminSql`
        select
          (select count(*)::int from ecosystem.app_enrollments ae
            join ecosystem.applications a on a.id=ae.application_id
            where ae.account_id=${accountId}::uuid and a.code='cocoonmate') as enrollments,
          (select count(*)::int from pregnancy.episodes e
            where e.mother_person_id=${personId}::uuid) as pregnancies,
          (select count(*)::int from commerce.entitlements
            where grantee_account_id=${accountId}::uuid) as entitlements
      `;
      assertEquals(Number(before[0].enrollments), 0);
      assertEquals(Number(before[0].pregnancies), 0);
      assertEquals(Number(before[0].entitlements), 0);

      const first = await boundary.resolveAndEnroll(appUserId);
      assertEquals(first, {
        availability: "available",
        enrollmentState: "active",
      });
      const replay = await boundary.resolveAndEnroll(appUserId);
      assertEquals(replay, first);

      const after = await adminSql`
        select
          (select count(*)::int from ecosystem.app_enrollments ae
            join ecosystem.applications a on a.id=ae.application_id
            where ae.account_id=${accountId}::uuid and a.code='cocoonmate') as canonical_enrollments,
          (select count(*)::int from ecosystem.app_enrollments ae
            join ecosystem.applications a on a.id=ae.application_id
            where ae.account_id=${appUserId}::uuid and a.code='cocoonmate') as legacy_enrollments,
          (select count(*)::int from pregnancy.episodes e
            where e.mother_person_id=${personId}::uuid) as pregnancies,
          (select count(*)::int from commerce.entitlements
            where grantee_account_id=${accountId}::uuid) as entitlements,
          (select count(*)::int from commerce.subscriptions
            where owner_account_id=${accountId}::uuid) as subscriptions
      `;
      assertEquals(Number(after[0].canonical_enrollments), 1);
      assertEquals(Number(after[0].legacy_enrollments), 0);
      assertEquals(Number(after[0].pregnancies), 0);
      assertEquals(Number(after[0].entitlements), 0);
      assertEquals(Number(after[0].subscriptions), 0);
    } finally {
      // `lifemate.app_users` still has compatibility triggers that create the
      // same-id Account/Person/free entitlements. Remove both the compatibility
      // projection and the remapped fixture so this integration test is hermetic.
      await adminSql`
        delete from commerce.entitlements
        where grantee_account_id in (${accountId}::uuid,${appUserId}::uuid)
           or beneficiary_person_id in (${personId}::uuid,${appUserId}::uuid)
      `.catch(() => undefined);
      await adminSql`
        delete from ecosystem.app_enrollments
        where account_id in (${accountId}::uuid,${appUserId}::uuid)
      `.catch(() => undefined);
      await adminSql`
        delete from identity.external_identities
        where account_id in (${accountId}::uuid,${appUserId}::uuid)
      `.catch(() => undefined);
      await adminSql`
        delete from core.account_person_links
        where account_id in (${accountId}::uuid,${appUserId}::uuid)
           or person_id in (${personId}::uuid,${appUserId}::uuid)
      `.catch(() => undefined);
      await adminSql`
        delete from core.person_profiles
        where person_id in (${personId}::uuid,${appUserId}::uuid)
      `.catch(() => undefined);
      await adminSql`
        delete from core.persons
        where id in (${personId}::uuid,${appUserId}::uuid)
      `.catch(() => undefined);
      await adminSql`
        update identity.accounts
        set legacy_app_user_id=null,updated_at_utc=now()
        where id in (${accountId}::uuid,${appUserId}::uuid)
      `.catch(() => undefined);
      await adminSql`
        delete from identity.accounts
        where id in (${accountId}::uuid,${appUserId}::uuid)
      `.catch(() => undefined);
      await adminSql`
        delete from lifemate.app_users where id=${appUserId}::uuid
      `.catch(() => undefined);
      await closeLifeMateSqlClientsForTest();
      await adminSql.end({ timeout: 1 });
    }
  },
});
