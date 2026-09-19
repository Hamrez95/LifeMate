import {
  assertEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPregnancyMeasurementRouteHandler } from "./pregnancy_measurements.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for pregnancy measurement integration tests.",
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
    "pregnancy measurement rejection before active pregnancy leaves no canonical observation",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserId = crypto.randomUUID();
    const accountId = crypto.randomUUID();
    const personId = crypto.randomUUID();
    const authSubject = `pregnancy-measurement-${crypto.randomUUID()}`;
    const clientRequestId = crypto.randomUUID();
    const handler = createPregnancyMeasurementRouteHandler(databaseUrl);

    try {
      await seedRemappedIdentity({
        appUserId,
        accountId,
        personId,
        authSubject,
      });

      const error = await assertRejects(
        () =>
          handler({
            request: new Request(
              "https://lifemate.test/api/v1/cocoon/pregnancy/measurements",
              {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                  clientRequestId,
                  observationType: "weight",
                  valuePrimary: 70,
                  observedAtUtc: "2026-09-19T10:00:00.000Z",
                  observedLocalDate: "2026-09-19",
                  timeZone: "Asia/Tehran",
                }),
              },
            ),
            path: "/api/v1/cocoon/pregnancy/measurements",
            appUserId,
          }),
        ApiError,
      );
      assertEquals(error.status, 409);
      assertEquals(error.code, "active_pregnancy_required");

      const rows = await adminSql`
        select count(*)::int as observation_count
        from lifemate.health_observations
        where person_id=${personId}::uuid
          and client_request_id=${clientRequestId}::uuid
      `;
      assertEquals(Number(rows[0].observation_count), 0);
    } finally {
      await adminSql`
        delete from pregnancy.observation_links
        where observation_id in (
          select id from lifemate.health_observations
          where person_id=${personId}::uuid
        )
      `.catch(() => undefined);
      await adminSql`
        delete from lifemate.health_observations
        where person_id=${personId}::uuid
      `.catch(() => undefined);
      await adminSql`
        delete from lifemate.audit_logs
        where actor_user_id=${appUserId}::uuid
      `.catch(() => undefined);
      await cleanupRemappedIdentity({ appUserId, accountId, personId });
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await adminSql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});

async function seedRemappedIdentity(input: {
  appUserId: string;
  accountId: string;
  personId: string;
  authSubject: string;
}): Promise<void> {
  await adminSql`
    insert into lifemate.app_users(
      id,auth_subject,status,created_at_utc,updated_at_utc
    ) values(
      ${input.appUserId}::uuid,${input.authSubject},'Active',now(),now()
    )
  `;
  await adminSql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id=${input.appUserId}::uuid
  `;
  await adminSql`
    insert into identity.accounts(
      id,legacy_app_user_id,status,created_at_utc,updated_at_utc
    ) values(
      ${input.accountId}::uuid,${input.appUserId}::uuid,'Active',now(),now()
    )
  `;
  await adminSql`
    insert into core.persons(id,status,subject_category)
    values(${input.personId}::uuid,'Active','Adult')
  `;
  await adminSql`
    insert into core.account_person_links(
      account_id,person_id,link_type,status,created_at_utc
    ) values(
      ${input.accountId}::uuid,${input.personId}::uuid,'Self','Active',now()
    )
  `;
}

async function cleanupRemappedIdentity(input: {
  appUserId: string;
  accountId: string;
  personId: string;
}): Promise<void> {
  await adminSql`
    delete from commerce.entitlements
    where grantee_account_id in (${input.appUserId}::uuid,${input.accountId}::uuid)
       or beneficiary_person_id in (${input.appUserId}::uuid,${input.personId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from ecosystem.app_enrollments
    where account_id in (${input.appUserId}::uuid,${input.accountId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from identity.external_identities
    where account_id in (${input.appUserId}::uuid,${input.accountId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from core.account_person_links
    where account_id in (${input.appUserId}::uuid,${input.accountId}::uuid)
       or person_id in (${input.appUserId}::uuid,${input.personId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from core.person_profiles
    where person_id in (${input.appUserId}::uuid,${input.personId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from core.persons
    where id in (${input.appUserId}::uuid,${input.personId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id in (${input.appUserId}::uuid,${input.accountId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from identity.accounts
    where id in (${input.appUserId}::uuid,${input.accountId}::uuid)
  `.catch(() => undefined);
  await adminSql`
    delete from lifemate.app_users where id=${input.appUserId}::uuid
  `.catch(() => undefined);
}
