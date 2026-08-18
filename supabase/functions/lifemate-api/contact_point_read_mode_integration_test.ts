import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createContactPointWriter } from "./contact_points.ts";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { createProfileStore } from "./profile.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for ContactPoint read-mode integration tests.",
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
    "Profile contact read modes preserve legacy fallback and fail closed in contact-only",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const previous = new Map<string, string | undefined>();
    for (const name of envNames) previous.set(name, Deno.env.get(name));

    const hashingSecret = "contact-read-mode-integration-hash-secret-32-bytes";
    const encryptionKey = {
      secret: "contact-read-mode-integration-envelope-key-32-bytes",
      keyVersion: 37,
    };
    const auth: AuthUser = {
      id: `contact-read-mode-${crypto.randomUUID()}`,
      email: `canonical-${crypto.randomUUID()}@example.test`,
      phone: null,
      userMetadata: {},
    };
    const canonicalPhone = "+989121234567";
    const legacyEmail = `legacy-${crypto.randomUUID()}@example.test`;
    const legacyPhone = "+989129999999";
    let appUserId: string | null = null;
    let accountId: string | null = null;

    try {
      Deno.env.set("LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE", "legacy");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "false");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT", "false");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED", "false");
      Deno.env.delete("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY");
      Deno.env.delete("LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION");

      const db = createLifeMateDatabase(databaseUrl, hashingSecret);
      const legacyStore = createProfileStore(databaseUrl, hashingSecret);
      await db.bootstrapUser(auth, {
        displayName: "Contact Read Mode",
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

      const before = await legacyStore.getProfile(appUserId);
      await legacyStore.updateProfile(appUserId, auth, {
        version: before.version,
        displayName: "Contact Read Mode",
        phoneNumber: canonicalPhone,
        locale: "fa",
        timeZone: "Asia/Tehran",
        avatarKey: "person_blue",
      });

      const writer = createContactPointWriter(hashingSecret, {
        enabled: true,
        encryptionKey,
      });
      await admin.begin(async (tx) => {
        await writer.syncForAccount(
          tx,
          accountId!,
          { email: auth.email, phone: canonicalPhone },
          "replace",
        );
      });

      await admin`
        update lifemate.user_profiles
        set email=${legacyEmail},phone_number=${legacyPhone},updated_at_utc=now()
        where user_id=${appUserId}::uuid
      `;

      const legacyRead = await legacyStore.getProfile(appUserId);
      assertEquals(legacyRead.email, legacyEmail);
      assertEquals(legacyRead.phoneNumber, legacyPhone);

      Deno.env.set("LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE", "prefer-contact");
      Deno.env.set(
        "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
        encryptionKey.secret,
      );
      Deno.env.set(
        "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
        String(encryptionKey.keyVersion),
      );
      const preferStore = createProfileStore(databaseUrl, hashingSecret);
      const preferred = await preferStore.getProfile(appUserId);
      assertEquals(preferred.email, String(auth.email).toLowerCase());
      assertEquals(preferred.phoneNumber, canonicalPhone);

      await admin`
        update identity.contact_points
        set encryption_key_version=${encryptionKey.keyVersion + 1}
        where account_id=${accountId}::uuid
          and kind='Phone' and status <> 'Revoked'
      `;
      const fallback = await preferStore.getProfile(appUserId);
      assertEquals(fallback.email, String(auth.email).toLowerCase());
      assertEquals(fallback.phoneNumber, legacyPhone);

      Deno.env.set("LIFEMATE_PROFILE_CONTACT_LOOKUP_MODE", "contact-only");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED", "false");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "true");
      assertThrows(
        () => createProfileStore(databaseUrl, hashingSecret),
        Error,
        "READINESS_APPROVED",
      );

      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_READINESS_APPROVED", "true");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "false");
      assertThrows(
        () => createProfileStore(databaseUrl, hashingSecret),
        Error,
        "DUAL_WRITE",
      );

      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "true");
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT", "true");
      const contactOnlyBroken = createProfileStore(databaseUrl, hashingSecret);
      const unavailable = await assertRejects(
        () => contactOnlyBroken.getProfile(appUserId!),
        ApiError,
      );
      assertEquals(unavailable.status, 503);
      assertEquals(unavailable.code, "contact_point_unavailable");

      await admin`
        update identity.contact_points
        set encryption_key_version=${encryptionKey.keyVersion}
        where account_id=${accountId}::uuid
          and kind='Phone' and status <> 'Revoked'
      `;
      const contactOnly = createProfileStore(databaseUrl, hashingSecret);
      const canonical = await contactOnly.getProfile(appUserId);
      assertEquals(canonical.email, String(auth.email).toLowerCase());
      assertEquals(canonical.phoneNumber, canonicalPhone);
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
        const value = previous.get(name);
        if (value === undefined) Deno.env.delete(name);
        else Deno.env.set(name, value);
      }
      await admin.end({ timeout: 5 });
    }
  },
});
