import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import postgres from "npm:postgres@3.4.7";
import { createContactPointWriter } from "../../supabase/functions/lifemate-api/contact_points.ts";
import { type AuthUser, createLifeMateDatabase } from "../../supabase/functions/lifemate-api/database.ts";
import { createProfileStore } from "../../supabase/functions/lifemate-api/profile.ts";
import { assessContactPointReadiness } from "./contact-point-readiness.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required for ContactPoint readiness tests.");
}

const sql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name: "ContactPoint readiness requires exact encrypted Email and Phone coverage",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const hashingSecret = "contact-readiness-hashing-secret-32-bytes-minimum";
    const encryptionKey = {
      secret: "contact-readiness-envelope-key-32-bytes-minimum",
      keyVersion: 17,
    };
    const auth: AuthUser = {
      id: `contact-readiness-${crypto.randomUUID()}`,
      email: `Contact-Readiness-${crypto.randomUUID()}@Example.Test`,
      phone: null,
      userMetadata: {},
    };
    const db = createLifeMateDatabase(databaseUrl, hashingSecret);
    const profiles = createProfileStore(databaseUrl, hashingSecret);
    let appUserId: string | null = null;
    let accountId: string | null = null;

    try {
      await db.bootstrapUser(auth, {
        displayName: "Contact Readiness",
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
        displayName: "Contact Readiness",
        phoneNumber: "+98 (912) 345-6789",
        locale: "fa",
        timeZone: "Asia/Tehran",
        avatarKey: "person_blue",
      });

      const missing = await assessContactPointReadiness({
        databaseUrl,
        hashingSecret,
        encryptionKey: encryptionKey.secret,
        keyVersion: encryptionKey.keyVersion,
      });
      assertEquals(missing.email.legacyPresent, 1);
      assertEquals(missing.phone.legacyPresent, 1);
      assertEquals(missing.email.missingCanonical, 1);
      assertEquals(missing.phone.missingCanonical, 1);
      assertEquals(missing.readyForContactOnly, false);

      const writer = createContactPointWriter(hashingSecret, {
        enabled: true,
        encryptionKey,
      });
      await sql.begin(async (tx) => {
        await writer.syncForLegacyAppUser(
          tx,
          appUserId!,
          { email: auth.email, phone: "+989123456789" },
          "replace",
        );
      });

      const ready = await assessContactPointReadiness({
        databaseUrl,
        hashingSecret,
        encryptionKey: encryptionKey.secret,
        keyVersion: encryptionKey.keyVersion,
      });
      assertEquals(ready.email.missingCanonical, 0);
      assertEquals(ready.phone.missingCanonical, 0);
      assertEquals(ready.email.invalidEnvelope, 0);
      assertEquals(ready.phone.invalidEnvelope, 0);
      assertEquals(ready.unmappedActiveAccounts, 0);
      assertEquals(ready.readyForContactOnly, true);
      const serialized = JSON.stringify(ready);
      assertEquals(serialized.includes(String(auth.email)), false);
      assertEquals(serialized.includes("+989123456789"), false);
      assertStringIncludes(serialized, "readyForContactOnly");

      await sql`
        update identity.contact_points
        set encryption_key_version=18
        where account_id=${accountId}::uuid and kind='Phone' and status <> 'Revoked'
      `;
      const invalid = await assessContactPointReadiness({
        databaseUrl,
        hashingSecret,
        encryptionKey: encryptionKey.secret,
        keyVersion: encryptionKey.keyVersion,
      });
      assertEquals(invalid.phone.invalidEnvelope, 1);
      assertEquals(invalid.readyForContactOnly, false);
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
