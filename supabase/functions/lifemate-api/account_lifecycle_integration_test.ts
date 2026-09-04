import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createAccountLifecycleStore } from "./account_lifecycle.ts";
import { createBootstrapAccountStateGuard } from "./bootstrap_account_state.ts";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required for account lifecycle tests.");
}

const adminSql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name:
    "account deletion API store resolves AppUser to provider-agnostic Account and blocks re-bootstrap",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const appUserId = crypto.randomUUID();
    const accountId = crypto.randomUUID();
    const personId = crypto.randomUUID();
    const authSubject = crypto.randomUUID();
    const store = createAccountLifecycleStore(databaseUrl);
    const bootstrapGuard = createBootstrapAccountStateGuard(databaseUrl);

    try {
      await adminSql`
        insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc)
        values (${appUserId}::uuid,${authSubject},'Active',now(),now())
      `;

      // Replace the bootstrap equal-ID compatibility projection with an
      // explicit Account -> Self Person mapping.
      await adminSql`
        delete from commerce.entitlements
        where grantee_account_id=${appUserId}::uuid
           or beneficiary_person_id=${appUserId}::uuid
      `;
      await adminSql`
        delete from ecosystem.app_enrollments where account_id=${appUserId}::uuid
      `;
      await adminSql`
        delete from identity.external_identities where account_id=${appUserId}::uuid
      `;
      await adminSql`
        delete from core.account_person_links where account_id=${appUserId}::uuid
      `;
      await adminSql`
        delete from identity.accounts where id=${appUserId}::uuid
      `;
      await adminSql`
        delete from core.persons where id=${appUserId}::uuid
      `;

      await adminSql`
        insert into identity.accounts(id,legacy_app_user_id,status)
        values (${accountId}::uuid,${appUserId}::uuid,'Active')
      `;
      await adminSql`
        insert into core.persons(id,status,subject_category)
        values (${personId}::uuid,'Active','Adult')
      `;
      await adminSql`
        insert into core.account_person_links(account_id,person_id,link_type,status)
        values (${accountId}::uuid,${personId}::uuid,'Self','Active')
      `;

      await bootstrapGuard.assertAllowed(authSubject);

      const requested = await store.requestDeletion(appUserId);
      assertEquals(requested.accountId, accountId);
      assertEquals(requested.status, "requested");

      const state = await adminSql`
        select a.status as account_status,u.status as app_user_status,
               r.account_id,r.retention_policy_version
        from identity.accounts a
        join lifemate.app_users u on u.id=${appUserId}::uuid
        join identity.account_deletion_requests r on r.account_id=a.id
        where a.id=${accountId}::uuid
      `;
      assertEquals(state[0].account_status, "DeletionPending");
      assertEquals(state[0].app_user_status, "Disabled");
      assertEquals(String(state[0].account_id), accountId);
      assertEquals(state[0].retention_policy_version, "retention-v2");

      let blocked: ApiError | null = null;
      try {
        await bootstrapGuard.assertAllowed(authSubject);
      } catch (error) {
        if (error instanceof ApiError) blocked = error;
        else throw error;
      }
      assertEquals(blocked?.status, 409);
      assertEquals(blocked?.code, "account_deletion_pending");

      const latest = await store.latestDeletionRequest(appUserId);
      assertEquals(latest?.id, requested.id);
      assertEquals(latest?.status, "requested");
      assertEquals(latest?.retentionPolicyVersion, "retention-v2");
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await adminSql`
        delete from integration.outbox_messages where aggregate_id=${accountId}::uuid
      `.catch(() => undefined);
      await adminSql`
        delete from identity.account_deletion_requests where account_id=${accountId}::uuid
      `.catch(() => undefined);
      await adminSql`
        delete from commerce.entitlements
        where grantee_account_id=${accountId}::uuid
           or beneficiary_person_id=${personId}::uuid
      `.catch(() => undefined);
      await adminSql`
        delete from ecosystem.app_enrollments where account_id=${accountId}::uuid
      `.catch(() => undefined);
      await adminSql`
        delete from identity.external_identities where account_id=${accountId}::uuid
      `.catch(() => undefined);
      await adminSql`
        delete from core.account_person_links where account_id=${accountId}::uuid
      `.catch(() => undefined);
      await adminSql`
        delete from identity.accounts where id=${accountId}::uuid
      `.catch(() => undefined);
      await adminSql`
        delete from core.persons where id=${personId}::uuid
      `.catch(() => undefined);
      await adminSql`
        delete from lifemate.app_users where id=${appUserId}::uuid
      `.catch(() => undefined);
      await adminSql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});
