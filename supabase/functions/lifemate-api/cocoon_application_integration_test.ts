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
    "Cocoon enrollment is idempotent and does not create pregnancy or entitlement state",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const accountId = crypto.randomUUID();
    const boundary = createCocoonApplicationBoundary(databaseUrl);
    try {
      await adminSql`
        insert into identity.accounts(id,status)
        values (${accountId}::uuid,'Active')
      `;

      const before = await adminSql`
        select
          (select count(*)::int from ecosystem.app_enrollments ae
            join ecosystem.applications a on a.id=ae.application_id
            where ae.account_id=${accountId}::uuid and a.code='cocoonmate') as enrollments,
          (select count(*)::int from pregnancy.episodes e
            join core.account_person_links l on l.person_id=e.mother_person_id
            where l.account_id=${accountId}::uuid) as pregnancies,
          (select count(*)::int from commerce.entitlements
            where grantee_account_id=${accountId}::uuid) as entitlements
      `;
      assertEquals(Number(before[0].enrollments), 0);
      assertEquals(Number(before[0].pregnancies), 0);
      assertEquals(Number(before[0].entitlements), 0);

      const first = await boundary.resolveAndEnroll(accountId);
      assertEquals(first, {
        availability: "available",
        enrollmentState: "active",
      });
      const replay = await boundary.resolveAndEnroll(accountId);
      assertEquals(replay, first);

      const after = await adminSql`
        select
          (select count(*)::int from ecosystem.app_enrollments ae
            join ecosystem.applications a on a.id=ae.application_id
            where ae.account_id=${accountId}::uuid and a.code='cocoonmate') as enrollments,
          (select count(*)::int from pregnancy.episodes e
            join core.account_person_links l on l.person_id=e.mother_person_id
            where l.account_id=${accountId}::uuid) as pregnancies,
          (select count(*)::int from commerce.entitlements
            where grantee_account_id=${accountId}::uuid) as entitlements,
          (select count(*)::int from commerce.subscriptions
            where owner_account_id=${accountId}::uuid) as subscriptions
      `;
      assertEquals(Number(after[0].enrollments), 1);
      assertEquals(Number(after[0].pregnancies), 0);
      assertEquals(Number(after[0].entitlements), 0);
      assertEquals(Number(after[0].subscriptions), 0);
    } finally {
      await adminSql`
        delete from ecosystem.app_enrollments where account_id=${accountId}::uuid
      `;
      await adminSql`
        delete from identity.accounts where id=${accountId}::uuid
      `;
      await closeLifeMateSqlClientsForTest();
      await adminSql.end({ timeout: 1 });
    }
  },
});
