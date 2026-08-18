import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createDataExportStore } from "./data_export.ts";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { createProfileStore } from "./profile.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for raw ContactPoint retirement integration tests.",
  );
}

const envNames = [
  "LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE",
  "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
  "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
  "LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED",
  "LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT",
  "LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE",
] as const;

Deno.test({
  name:
    "retired Profile contacts stay raw-null across bootstrap, update, export and conflict rollback",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const previous = new Map<string, string | undefined>();
    for (const name of envNames) previous.set(name, Deno.env.get(name));

    const hashingSecret =
      "raw-contact-retirement-integration-hash-secret-32-bytes";
    const encryptionKey = {
      secret: "raw-contact-retirement-integration-envelope-key-32-bytes",
      keyVersion: 43,
    };
    const suffix = crypto.randomUUID();
    const auth: AuthUser = {
      id: `raw-contact-retirement-${suffix}`,
      email: `Raw-Contact-${suffix}@Example.Test`,
      phone: "+989121234567",
      userMetadata: {},
    };
    const otherAuth: AuthUser = {
      id: `raw-contact-retirement-other-${suffix}`,
      email: `other-raw-contact-${suffix}@example.test`,
      phone: "+989129998877",
      userMetadata: {},
    };
    let appUserId: string | null = null;
    let accountId: string | null = null;
    let otherAppUserId: string | null = null;
    let otherAccountId: string | null = null;

    try {
      Deno.env.set("LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE", "contact-only");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED", "true");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "true");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT", "true");
      Deno.env.set(
        "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
        encryptionKey.secret,
      );
      Deno.env.set(
        "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
        String(encryptionKey.keyVersion),
      );

      const db = createLifeMateDatabase(databaseUrl, hashingSecret);
      const bootstrapped = await db.bootstrapUser(auth, {
        displayName: "Raw Contact Retirement",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const identity = await db.requireIdentity(auth);
      appUserId = identity.appUserId;
      accountId = await accountFor(admin, appUserId);

      await assertRawProfileContactsNull(admin, appUserId);
      assertEquals(await currentContactCount(admin, accountId), 2);
      const bootstrapProfile = bootstrapped.profile as Record<string, unknown>;
      assertEquals(bootstrapProfile.email, auth.email!.toLowerCase());
      assertEquals(bootstrapProfile.phoneNumber, auth.phone);

      const current = await db.currentUser(identity);
      const currentProfile = current.profile as Record<string, unknown>;
      assertEquals(currentProfile.email, auth.email!.toLowerCase());
      assertEquals(currentProfile.phoneNumber, auth.phone);

      const profiles = createProfileStore(databaseUrl, hashingSecret);
      const updatedPhone = "+989120001122";
      const updated = await profiles.updateProfile(appUserId, auth, {
        version: currentProfile.version,
        displayName: "Raw Contact Retirement Updated",
        phoneNumber: "+98 (912) 000-1122",
        locale: "fa",
        timeZone: "Asia/Tehran",
        avatarKey: "person_green",
      });
      assertEquals(updated.email, auth.email!.toLowerCase());
      assertEquals(updated.phoneNumber, updatedPhone);
      await assertRawProfileContactsNull(admin, appUserId);

      const exported = await createDataExportStore(databaseUrl)
        .exportAccountData(appUserId);
      const exportedProfile = exported.profile as Record<string, unknown>;
      assertEquals(exportedProfile.email, auth.email!.toLowerCase());
      assertEquals(exportedProfile.phoneNumber, updatedPhone);

      const otherDb = createLifeMateDatabase(databaseUrl, hashingSecret);
      await otherDb.bootstrapUser(otherAuth, {
        displayName: "Other Raw Contact",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const otherIdentity = await otherDb.requireIdentity(otherAuth);
      otherAppUserId = otherIdentity.appUserId;
      otherAccountId = await accountFor(admin, otherAppUserId);
      await assertRawProfileContactsNull(admin, otherAppUserId);

      const conflict = await assertRejects(
        () =>
          profiles.updateProfile(appUserId!, auth, {
            version: updated.version,
            displayName: "Must Roll Back",
            phoneNumber: otherAuth.phone,
            locale: "fa",
            timeZone: "Asia/Tehran",
            avatarKey: "person_blue",
          }),
        ApiError,
      );
      assertEquals(conflict.status, 409);
      assertEquals(conflict.code, "contact_point_conflict");

      await assertRawProfileContactsNull(admin, appUserId);
      const afterConflict = await profiles.getProfile(appUserId);
      assertEquals(afterConflict.phoneNumber, updatedPhone);
      assertEquals(afterConflict.version, updated.version);
    } finally {
      await cleanupAccount(admin, otherAppUserId, otherAccountId);
      await cleanupAccount(admin, appUserId, accountId);
      for (const name of envNames) {
        const value = previous.get(name);
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
      await admin.end({ timeout: 5 });
    }
  },
});

async function accountFor(connection: any, appUserId: string): Promise<string> {
  const rows = await connection`
    select identity.account_id_for_legacy_app_user(${appUserId}::uuid)::text
      as account_id
  `;
  const accountId = rows[0]?.account_id;
  if (typeof accountId !== "string" || accountId.length === 0) {
    throw new Error(
      "Expected Account mapping for raw contact retirement test.",
    );
  }
  return accountId;
}

async function assertRawProfileContactsNull(
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

async function currentContactCount(
  connection: any,
  accountId: string,
): Promise<number> {
  const rows = await connection`
    select count(*)::int as count
    from identity.contact_points
    where account_id=${accountId}::uuid and status <> 'Revoked'
  `;
  return Number(rows[0]?.count ?? 0);
}

async function cleanupAccount(
  connection: any,
  appUserId: string | null,
  accountId: string | null,
): Promise<void> {
  if (accountId) {
    await connection`
      delete from identity.contact_points where account_id=${accountId}::uuid
    `.catch(() => undefined);
    await connection`
      delete from identity.external_identity_tokens where account_id=${accountId}::uuid
    `.catch(() => undefined);
    await connection`
      delete from identity.provider_identity_handles where account_id=${accountId}::uuid
    `.catch(() => undefined);
    await connection`
      delete from identity.external_identities where account_id=${accountId}::uuid
    `.catch(() => undefined);
    await connection`
      delete from core.account_person_links where account_id=${accountId}::uuid
    `.catch(() => undefined);
    await connection`
      delete from ecosystem.app_enrollments where account_id=${accountId}::uuid
    `.catch(() => undefined);
  }
  if (appUserId) {
    await connection`
      delete from lifemate.audit_logs
      where actor_user_id=${appUserId}::uuid or resource_id=${appUserId}::uuid
    `.catch(() => undefined);
    await connection`
      delete from lifemate.user_profiles where user_id=${appUserId}::uuid
    `.catch(() => undefined);
  }
  if (accountId) {
    await connection`
      delete from identity.accounts where id=${accountId}::uuid
    `.catch(() => undefined);
  }
  if (appUserId) {
    await connection`
      delete from lifemate.app_users where id=${appUserId}::uuid
    `.catch(() => undefined);
    await connection`
      delete from core.person_profiles where person_id=${appUserId}::uuid
    `.catch(() => undefined);
    await connection`
      delete from core.persons where id=${appUserId}::uuid
    `.catch(() => undefined);
  }
}
