import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createContactPointWriter } from "./contact_points.ts";
import { createDataExportStore } from "./data_export.ts";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { createProfileStore } from "./profile.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for ContactPoint key-rotation integration tests.",
  );
}

const envNames = [
  "LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE",
  "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
  "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
  "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY",
  "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION",
  "LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED",
  "LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT",
  "LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE",
] as const;

Deno.test({
  name:
    "contact-only Profile and export survive previous envelope key while new writes use active key only",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const previousEnvironment = new Map<string, string | undefined>();
    for (const name of envNames) {
      previousEnvironment.set(name, Deno.env.get(name));
    }

    const hashingSecret = "contact-key-rotation-integration-hash-secret-32-bytes";
    const previousKey = {
      secret: "contact-key-rotation-previous-envelope-key-32-bytes",
      keyVersion: 51,
    };
    const activeKey = {
      secret: "contact-key-rotation-active-envelope-key-32-bytes",
      keyVersion: 52,
    };
    const suffix = crypto.randomUUID();
    const auth: AuthUser = {
      id: `contact-key-rotation-${suffix}`,
      email: `Rotation-${suffix}@Example.Test`,
      phone: null,
      userMetadata: {},
    };
    const initialPhone = "+989121234567";
    const updatedPhone = "+989120001122";
    let appUserId: string | null = null;
    let accountId: string | null = null;

    try {
      // Bootstrap through the existing legacy compatibility path so this test
      // isolates ContactPoint envelope rotation from identity-link rotation.
      Deno.env.set("LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE", "legacy");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "false");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT", "false");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED", "false");
      for (const name of [
        "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
        "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
        "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY",
        "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION",
      ]) {
        Deno.env.delete(name);
      }

      const db = createLifeMateDatabase(databaseUrl, hashingSecret);
      await db.bootstrapUser(auth, {
        displayName: "Contact Key Rotation",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const identity = await db.requireIdentity(auth);
      appUserId = identity.appUserId;
      const accountRows = await admin`
        select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
          as account_id
      `;
      accountId = String(accountRows[0]?.account_id ?? "");

      const previousWriter = createContactPointWriter(hashingSecret, {
        enabled: true,
        encryptionKey: previousKey,
      });
      await admin.begin(async (tx) => {
        await previousWriter.syncForAccount(
          tx,
          accountId!,
          { email: auth.email, phone: initialPhone },
          "replace",
        );
      });
      await admin`
        update lifemate.user_profiles
        set email=null,phone_number=null,updated_at_utc=now()
        where user_id=${appUserId}::uuid
      `;

      const previousRows = await admin`
        select kind,encryption_key_version
        from identity.contact_points
        where account_id=${accountId}::uuid and status <> 'Revoked'
        order by kind
      `;
      assertEquals(previousRows.length, 2);
      assertEquals(
        previousRows.every((row) =>
          Number(row.encryption_key_version) === previousKey.keyVersion
        ),
        true,
      );

      Deno.env.set("LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE", "contact-only");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED", "true");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "true");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT", "true");
      Deno.env.set(
        "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
        activeKey.secret,
      );
      Deno.env.set(
        "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
        String(activeKey.keyVersion),
      );
      Deno.env.set(
        "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY",
        previousKey.secret,
      );
      Deno.env.set(
        "LIFEMATE_IDENTITY_CONTACT_PREVIOUS_ENCRYPTION_KEY_VERSION",
        String(previousKey.keyVersion),
      );

      const profileStore = createProfileStore(databaseUrl, hashingSecret);
      const profile = await profileStore.getProfile(appUserId);
      assertEquals(profile.email, String(auth.email).toLowerCase());
      assertEquals(profile.phoneNumber, initialPhone);

      const exported = await createDataExportStore(databaseUrl)
        .exportAccountData(appUserId);
      const exportedProfile = exported.profile as Record<string, unknown>;
      assertEquals(exportedProfile.email, String(auth.email).toLowerCase());
      assertEquals(exportedProfile.phoneNumber, initialPhone);

      const updated = await profileStore.updateProfile(appUserId, auth, {
        version: profile.version,
        displayName: "Contact Key Rotation Updated",
        phoneNumber: updatedPhone,
        locale: "fa",
        timeZone: "Asia/Tehran",
        avatarKey: "person_green",
      });
      assertEquals(updated.email, String(auth.email).toLowerCase());
      assertEquals(updated.phoneNumber, updatedPhone);

      const activeRows = await admin`
        select kind,encryption_key_version
        from identity.contact_points
        where account_id=${accountId}::uuid and status <> 'Revoked'
        order by kind
      `;
      assertEquals(activeRows.length, 2);
      assertEquals(
        activeRows.every((row) =>
          Number(row.encryption_key_version) === activeKey.keyVersion
        ),
        true,
      );
      await assertRawContactsNull(admin, appUserId);

      // An envelope version outside the explicitly configured active/previous
      // pair remains unreadable after raw retirement; no legacy fallback exists.
      await admin`
        update identity.contact_points
        set encryption_key_version=${activeKey.keyVersion + 1}
        where account_id=${accountId}::uuid
          and kind='Phone' and status <> 'Revoked'
      `;
      const unavailable = await assertRejects(
        () => profileStore.getProfile(appUserId!),
        ApiError,
      );
      assertEquals(unavailable.status, 503);
      assertEquals(unavailable.code, "contact_point_unavailable");
    } finally {
      if (accountId) {
        await admin`
          delete from identity.contact_points where account_id=${accountId}::uuid
        `.catch(() => undefined);
      }
      if (appUserId) {
        await admin`
          delete from lifemate.audit_logs
          where actor_user_id=${appUserId}::uuid or resource_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.user_profiles where user_id=${appUserId}::uuid
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
          delete from ecosystem.app_enrollments where account_id=${accountId}::uuid
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
      for (const name of envNames) {
        const value = previousEnvironment.get(name);
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
      await admin.end({ timeout: 5 });
    }
  },
});

async function assertRawContactsNull(
  connection: any,
  appUserId: string,
): Promise<void> {
  const rows = await connection`
    select email,phone_number
    from lifemate.user_profiles
    where user_id=${appUserId}::uuid
  `;
  assertEquals(rows.length, 1);
  assertEquals(rows[0].email, null);
  assertEquals(rows[0].phone_number, null);
}
