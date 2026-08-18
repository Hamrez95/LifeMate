import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "npm:postgres@3.4.7";
import {
  type AuthUser,
  createLifeMateDatabase,
} from "../../supabase/functions/lifemate-api/database.ts";
import { createProfileStore } from "../../supabase/functions/lifemate-api/profile.ts";
import { backfillContactPoints } from "./contact-point-backfill.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for ContactPoint backfill tests.",
  );
}

const sql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name: "ContactPoint backfill is dry-run safe, bounded and idempotent",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const hashingSecret = "contact-backfill-hashing-secret-32-bytes-minimum";
    const encryptionKey = "contact-backfill-envelope-key-32-bytes-minimum";
    const keyVersion = 23;
    const auth: AuthUser = {
      id: `contact-backfill-${crypto.randomUUID()}`,
      email: `Contact-Backfill-${crypto.randomUUID()}@Example.Test`,
      phone: null,
      userMetadata: {},
    };
    const db = createLifeMateDatabase(databaseUrl, hashingSecret);
    const profiles = createProfileStore(databaseUrl, hashingSecret);
    let appUserId: string | null = null;
    let accountId: string | null = null;

    try {
      await db.bootstrapUser(auth, {
        displayName: "Contact Backfill",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const identity = await db.requireIdentity(auth);
      appUserId = identity.appUserId;
      const accountRows = await sql`
        select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
          as account_id
      `;
      accountId = String(accountRows[0]?.account_id ?? "");

      const beforeProfile = await profiles.getProfile(appUserId);
      await profiles.updateProfile(appUserId, auth, {
        version: beforeProfile.version,
        displayName: "Contact Backfill",
        phoneNumber: "+98 (912) 765-4321",
        locale: "fa",
        timeZone: "Asia/Tehran",
        avatarKey: "person_blue",
      });

      const dryRun = await backfillContactPoints({
        databaseUrl,
        hashingSecret,
        encryptionKey,
        keyVersion,
        mode: "dry-run",
        maxAccounts: 100,
      });
      assertEquals(dryRun.scannedAccounts, 1);
      assertEquals(dryRun.plannedContacts, 2);
      assertEquals(dryRun.insertedOrRefreshed, 0);
      const beforeRows = await sql`
        select count(*)::int as count
        from identity.contact_points
        where account_id=${accountId}::uuid and status <> 'Revoked'
      `;
      assertEquals(Number(beforeRows[0]?.count), 0);

      const applied = await backfillContactPoints({
        databaseUrl,
        hashingSecret,
        encryptionKey,
        keyVersion,
        mode: "apply",
        maxAccounts: 100,
      });
      assertEquals(applied.scannedAccounts, 1);
      assertEquals(applied.plannedContacts, 2);
      assertEquals(applied.insertedOrRefreshed, 2);

      const firstRows = await sql`
        select id::text as id,kind,normalized_value_hash
        from identity.contact_points
        where account_id=${accountId}::uuid and status <> 'Revoked'
        order by kind
      `;
      assertEquals(firstRows.length, 2);

      const second = await backfillContactPoints({
        databaseUrl,
        hashingSecret,
        encryptionKey,
        keyVersion,
        mode: "apply",
        maxAccounts: 100,
      });
      assertEquals(second.alreadyCurrentContacts, 2);
      assertEquals(second.insertedOrRefreshed, 2);
      const secondRows = await sql`
        select id::text as id,kind,normalized_value_hash
        from identity.contact_points
        where account_id=${accountId}::uuid and status <> 'Revoked'
        order by kind
      `;
      assertEquals(secondRows, firstRows);
    } finally {
      if (accountId) {
        await sql`delete from identity.contact_points where account_id=${accountId}::uuid`
          .catch(() => undefined);
      }
      if (appUserId) {
        await sql`
          delete from lifemate.audit_logs
          where actor_user_id=${appUserId}::uuid or resource_id=${appUserId}::uuid
        `.catch(() => undefined);
        await sql`delete from lifemate.user_profiles where user_id=${appUserId}::uuid`
          .catch(() => undefined);
        await sql`delete from identity.external_identity_tokens where account_id=${accountId}::uuid`
          .catch(() => undefined);
        await sql`delete from identity.external_identities where account_id=${accountId}::uuid`
          .catch(() => undefined);
        await sql`delete from core.account_person_links where account_id=${accountId}::uuid`
          .catch(() => undefined);
        await sql`delete from ecosystem.app_enrollments where account_id=${accountId}::uuid`
          .catch(() => undefined);
        await sql`delete from identity.accounts where id=${accountId}::uuid`
          .catch(() => undefined);
        await sql`delete from lifemate.app_users where id=${appUserId}::uuid`
          .catch(() => undefined);
        await sql`delete from core.person_profiles where person_id=${appUserId}::uuid`
          .catch(() => undefined);
        await sql`delete from core.persons where id=${appUserId}::uuid`
          .catch(() => undefined);
      }
    }
  },
});
