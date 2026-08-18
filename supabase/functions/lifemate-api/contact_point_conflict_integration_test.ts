import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { createProfileStore } from "./profile.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for ContactPoint conflict integration tests.",
  );
}

Deno.test({
  name: "ContactPoint conflict rolls back Profile contact and version writes",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const hashingSecret = "integration-only-contact-conflict-hash-secret-32-bytes";
    const encryptionSecret =
      "integration-only-contact-conflict-envelope-key-32-bytes";
    const previousDualWrite = Deno.env.get(
      "LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE",
    );
    const previousEncryptionKey = Deno.env.get(
      "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
    );
    const previousEncryptionKeyVersion = Deno.env.get(
      "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
    );
    const authA: AuthUser = {
      id: `contact-conflict-a-${crypto.randomUUID()}`,
      email: `contact-conflict-a-${crypto.randomUUID()}@example.test`,
      phone: null,
      userMetadata: {},
    };
    const authB: AuthUser = {
      id: `contact-conflict-b-${crypto.randomUUID()}`,
      email: `contact-conflict-b-${crypto.randomUUID()}@example.test`,
      phone: null,
      userMetadata: {},
    };
    const sharedPhone = "+989121111111";
    const appUserIds: string[] = [];

    try {
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "true");
      Deno.env.set(
        "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
        encryptionSecret,
      );
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION", "11");

      const db = createLifeMateDatabase(databaseUrl, hashingSecret);
      const profiles = createProfileStore(databaseUrl, hashingSecret);

      await db.bootstrapUser(authA, {
        displayName: "Contact A",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      await db.bootstrapUser(authB, {
        displayName: "Contact B",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const identityA = await db.requireIdentity(authA);
      const identityB = await db.requireIdentity(authB);
      appUserIds.push(identityA.appUserId, identityB.appUserId);

      const profileA = await profiles.getProfile(identityA.appUserId);
      await profiles.updateProfile(identityA.appUserId, authA, {
        version: profileA.version,
        displayName: "Contact A",
        phoneNumber: sharedPhone,
        locale: "fa",
        timeZone: "Asia/Tehran",
        avatarKey: "person_blue",
      });

      const beforeB = await profiles.getProfile(identityB.appUserId);
      const error = await assertRejects(
        () =>
          profiles.updateProfile(identityB.appUserId, authB, {
            version: beforeB.version,
            displayName: "Contact B changed",
            phoneNumber: sharedPhone,
            locale: "en",
            timeZone: "Europe/Berlin",
            avatarKey: "person_green",
          }),
        ApiError,
      );
      assertEquals(error.status, 409);
      assertEquals(error.code, "contact_point_conflict");

      const afterB = await profiles.getProfile(identityB.appUserId);
      assertEquals(afterB.version, beforeB.version);
      assertEquals(afterB.phoneNumber, beforeB.phoneNumber);
      assertEquals(afterB.displayName, beforeB.displayName);
      assertEquals(afterB.locale, beforeB.locale);
      assertEquals(afterB.timeZone, beforeB.timeZone);
      assertEquals(afterB.avatarKey, beforeB.avatarKey);

      const ownership = await admin`
        select cp.account_id::text as account_id,
               identity.account_id_for_legacy_app_user(${identityA.appUserId}::uuid)::text
                 as account_a,
               identity.account_id_for_legacy_app_user(${identityB.appUserId}::uuid)::text
                 as account_b
        from identity.contact_points cp
        where cp.kind='Phone' and cp.status <> 'Revoked'
      `;
      assertEquals(ownership.length, 1);
      assertEquals(ownership[0]?.account_id, ownership[0]?.account_a);
      assertEquals(ownership[0]?.account_id === ownership[0]?.account_b, false);

      const bContacts = await admin`
        select count(*)::int as count
        from identity.contact_points
        where account_id=identity.account_id_for_legacy_app_user(
          ${identityB.appUserId}::uuid
        )
      `;
      assertEquals(Number(bContacts[0]?.count), 0);
    } finally {
      for (const appUserId of appUserIds.reverse()) {
        const accountRows = await admin`
          select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
            as account_id
        `.catch(() => [] as Record<string, unknown>[]);
        const accountId = typeof accountRows[0]?.account_id === "string"
          ? accountRows[0].account_id
          : appUserId;
        await admin`
          delete from identity.contact_points where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.audit_logs
          where actor_user_id=${appUserId}::uuid or resource_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.user_profiles where user_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from commerce.entitlements
          where grantee_account_id=${accountId}::uuid
             or beneficiary_person_id in (
               select person_id from core.account_person_links
               where account_id=${accountId}::uuid
             )
        `.catch(() => undefined);
        await admin`
          delete from ecosystem.app_enrollments where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from identity.external_identity_tokens where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from identity.external_identities where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.account_person_links where account_id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from identity.accounts where id=${accountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.app_users where id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.person_profiles where person_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.persons where id=${appUserId}::uuid
        `.catch(() => undefined);
      }

      if (previousDualWrite == null) {
        Deno.env.delete("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE");
      } else {
        Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", previousDualWrite);
      }
      if (previousEncryptionKey == null) {
        Deno.env.delete("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY");
      } else {
        Deno.env.set(
          "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
          previousEncryptionKey,
        );
      }
      if (previousEncryptionKeyVersion == null) {
        Deno.env.delete("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION");
      } else {
        Deno.env.set(
          "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
          previousEncryptionKeyVersion,
        );
      }
      await admin.end({ timeout: 5 });
    }
  },
});
