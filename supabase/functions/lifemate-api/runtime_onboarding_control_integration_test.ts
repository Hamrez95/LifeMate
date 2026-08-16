import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for runtime onboarding control tests.",
  );
}

Deno.test({
  name:
    "runtime onboarding control blocks only new AppUsers and stays read-only to Edge",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const runtime = postgres(databaseUrl, { max: 1, prepare: false });
    const existingId = crypto.randomUUID();
    const resumedId = crypto.randomUUID();
    const existingSubject = `ops-existing-${crypto.randomUUID()}`;
    const blockedSubject = `ops-blocked-${crypto.randomUUID()}`;
    const resumedSubject = `ops-resumed-${crypto.randomUUID()}`;

    const cleanupCompatibilityProjection = async (appUserId: string) => {
      await admin`
        delete from commerce.entitlements
        where grantee_account_id=${appUserId}::uuid
           or beneficiary_person_id=${appUserId}::uuid
      `.catch(() => undefined);
      await admin`
        delete from ecosystem.app_enrollments where account_id=${appUserId}::uuid
      `.catch(() => undefined);
      await admin`
        delete from identity.external_identity_tokens where account_id=${appUserId}::uuid
      `.catch(() => undefined);
      await admin`
        delete from identity.external_identities where account_id=${appUserId}::uuid
      `.catch(() => undefined);
      await admin`
        delete from core.account_person_links where account_id=${appUserId}::uuid
      `.catch(() => undefined);
      await admin`
        delete from identity.accounts where id=${appUserId}::uuid
      `.catch(() => undefined);
      await admin`
        delete from core.person_profiles where person_id=${appUserId}::uuid
      `.catch(() => undefined);
      await admin`
        delete from core.persons where id=${appUserId}::uuid
      `.catch(() => undefined);
      await admin`
        delete from lifemate.app_users where id=${appUserId}::uuid
      `.catch(() => undefined);
    };

    try {
      await admin`
        update security.runtime_controls
        set enabled=true, note='integration baseline'
        where control_key='new_user_onboarding'
      `;

      await admin`
        insert into lifemate.app_users
          (id,auth_subject,status,created_at_utc,updated_at_utc)
        values
          (${existingId}::uuid,${existingSubject},'Active',now(),now())
      `;

      await admin`
        update security.runtime_controls
        set enabled=false, note='integration pause'
        where control_key='new_user_onboarding'
      `;

      const paused = await assertRejects(() =>
        admin`
          insert into lifemate.app_users
            (id,auth_subject,status,created_at_utc,updated_at_utc)
          values
            (${crypto.randomUUID()}::uuid,${blockedSubject},'Active',now(),now())
        `
      );
      assertEquals((paused as { code?: string }).code, "55P03");

      const existing = await admin`
        insert into lifemate.app_users
          (id,auth_subject,status,created_at_utc,updated_at_utc)
        values
          (${crypto.randomUUID()}::uuid,${existingSubject},'Active',now(),now())
        on conflict (auth_subject) do update
          set updated_at_utc=excluded.updated_at_utc
        returning id
      `;
      assertEquals(String(existing[0].id), existingId);

      await runtime`set role lifemate_edge_runtime`;
      const visible = await runtime`
        select enabled
        from security.runtime_controls
        where control_key='new_user_onboarding'
      `;
      assertEquals(visible.length, 1);
      assertEquals(visible[0].enabled, false);
      await assertRejects(() =>
        runtime`
          update security.runtime_controls
          set enabled=true
          where control_key='new_user_onboarding'
        `
      );
      await runtime`reset role`;

      await admin`
        update security.runtime_controls
        set enabled=true, note='integration resume'
        where control_key='new_user_onboarding'
      `;
      await admin`
        insert into lifemate.app_users
          (id,auth_subject,status,created_at_utc,updated_at_utc)
        values
          (${resumedId}::uuid,${resumedSubject},'Active',now(),now())
      `;

      const resumed = await admin`
        select id from lifemate.app_users where auth_subject=${resumedSubject}
      `;
      assertEquals(String(resumed[0].id), resumedId);
    } finally {
      await runtime`reset role`.catch(() => undefined);
      await admin`
        update security.runtime_controls
        set enabled=true, note='integration cleanup'
        where control_key='new_user_onboarding'
      `.catch(() => undefined);
      await cleanupCompatibilityProjection(existingId);
      await cleanupCompatibilityProjection(resumedId);
      await runtime.end({ timeout: 1 }).catch(() => undefined);
      await admin.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});
