import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import {
  type ContactPointEnvelope,
  decryptContactPoint,
} from "../_shared/contact_point_crypto.ts";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { createIdentityBridge } from "./identity_bridge.ts";
import { createProfileStore } from "./profile.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for profile projection integration tests.",
  );
}

Deno.test({
  name: "legacy Profile projection changes only modified Person fields",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const hashingSecret =
      "integration-only-profile-projection-secret-32-bytes-minimum";
    const encryptionSecret =
      "integration-only-contact-envelope-secret-32-bytes-minimum";
    const encryptionKeyVersion = 7;
    const previousDualWrite = Deno.env.get(
      "LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE",
    );
    const previousEncryptionKey = Deno.env.get(
      "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
    );
    const previousEncryptionKeyVersion = Deno.env.get(
      "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
    );
    const suffix = crypto.randomUUID();
    const auth: AuthUser = {
      id: `profile-projection-${suffix}`,
      email: `Profile-Projection-${suffix}@Example.Test`,
      phone: "+98 (912) 000-0000",
      userMetadata: {},
    };
    const remappedAccountId = crypto.randomUUID();
    const remappedPersonId = crypto.randomUUID();
    let appUserId: string | null = null;

    try {
      Deno.env.set("LIFEMATE_IDENTITY_CONTACT_DUAL_WRITE", "true");
      Deno.env.set(
        "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY",
        encryptionSecret,
      );
      Deno.env.set(
        "LIFEMATE_IDENTITY_CONTACT_ENCRYPTION_KEY_VERSION",
        String(encryptionKeyVersion),
      );

      const db = createLifeMateDatabase(databaseUrl, hashingSecret);
      const profiles = createProfileStore(databaseUrl, hashingSecret);
      const identityBridge = createIdentityBridge(databaseUrl, hashingSecret);

      await db.bootstrapUser(auth, {
        displayName: "legacy initial",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const identity = await db.requireIdentity(auth);
      appUserId = identity.appUserId;

      await admin`
        update identity.accounts
        set legacy_app_user_id = null, updated_at_utc = now()
        where id = ${identity.appUserId}::uuid
      `;
      await admin`
        insert into identity.accounts(id, legacy_app_user_id, status)
        values (${remappedAccountId}::uuid, ${identity.appUserId}::uuid, 'Active')
      `;
      await admin`
        insert into core.persons(id, status, subject_category)
        values (${remappedPersonId}::uuid, 'Active', 'Adult')
      `;
      await admin`
        insert into core.account_person_links(account_id, person_id, link_type, status)
        values (${remappedAccountId}::uuid, ${remappedPersonId}::uuid, 'Self', 'Active')
      `;
      await admin`
        insert into core.person_profiles(
          person_id, display_name, locale, time_zone, avatar_key,
          profile_photo_path, created_at_utc, updated_at_utc
        )
        select ${remappedPersonId}::uuid, display_name, locale, time_zone,
               avatar_key, profile_photo_path, created_at_utc, updated_at_utc
        from lifemate.user_profiles
        where user_id = ${identity.appUserId}::uuid
      `;

      await identityBridge.syncExternalIdentities(identity.appUserId, {
        id: auth.id,
        email: auth.email,
        phone: auth.phone,
        identities: [],
      });
      const seededContacts = await admin`
        select kind,normalized_value_hash,encode(encrypted_value,'base64') as ciphertext_b64,
               encryption_nonce_b64,encryption_key_version,status
        from identity.contact_points
        where account_id=${remappedAccountId}::uuid
          and status <> 'Revoked'
        order by kind
      `;
      assertEquals(seededContacts.length, 2);
      assertEquals(seededContacts[0]?.kind, "Email");
      assertEquals(seededContacts[1]?.kind, "Phone");
      assertEquals(seededContacts[0]?.status, "Pending");
      assertEquals(seededContacts[1]?.status, "Pending");
      assertEquals(String(seededContacts[0]?.normalized_value_hash).length, 64);
      assertEquals(String(seededContacts[1]?.normalized_value_hash).length, 64);
      assertEquals(
        String(seededContacts[0]?.ciphertext_b64).includes(
          String(auth.email).toLowerCase(),
        ),
        false,
      );
      assertEquals(
        String(seededContacts[1]?.ciphertext_b64).includes("+989120000000"),
        false,
      );

      const emailEnvelope: ContactPointEnvelope = {
        ciphertextB64: String(seededContacts[0]?.ciphertext_b64),
        nonceB64: String(seededContacts[0]?.encryption_nonce_b64),
        keyVersion: Number(seededContacts[0]?.encryption_key_version),
      };
      assertEquals(
        await decryptContactPoint(
          { secret: encryptionSecret, keyVersion: encryptionKeyVersion },
          {
            accountId: remappedAccountId,
            kind: "Email",
            normalizedValueHash: String(
              seededContacts[0]?.normalized_value_hash,
            ),
          },
          emailEnvelope,
        ),
        String(auth.email).toLowerCase(),
      );

      await admin`
        update core.person_profiles
        set display_name = 'canonical independent',
            locale = 'en',
            time_zone = 'Europe/Berlin',
            avatar_key = 'person_green'
        where person_id = ${remappedPersonId}::uuid
      `;

      const photoPath = `${identity.appUserId}/${crypto.randomUUID()}.jpg`;
      await admin`
        update lifemate.user_profiles
        set profile_photo_path = ${photoPath}, updated_at_utc = now()
        where user_id = ${identity.appUserId}::uuid
      `;

      const afterPhoto = await admin`
        select display_name, locale, time_zone, avatar_key, profile_photo_path
        from core.person_profiles
        where person_id = ${remappedPersonId}::uuid
      `;
      assertEquals(afterPhoto[0]?.display_name, "canonical independent");
      assertEquals(afterPhoto[0]?.locale, "en");
      assertEquals(afterPhoto[0]?.time_zone, "Europe/Berlin");
      assertEquals(afterPhoto[0]?.avatar_key, "person_green");
      assertEquals(afterPhoto[0]?.profile_photo_path, photoPath);

      await admin`
        update lifemate.user_profiles
        set display_name = 'legacy changed', updated_at_utc = now()
        where user_id = ${identity.appUserId}::uuid
      `;
      const afterDisplay = await admin`
        select display_name, locale, time_zone, avatar_key, profile_photo_path
        from core.person_profiles
        where person_id = ${remappedPersonId}::uuid
      `;
      assertEquals(afterDisplay[0]?.display_name, "legacy changed");
      assertEquals(afterDisplay[0]?.locale, "en");
      assertEquals(afterDisplay[0]?.time_zone, "Europe/Berlin");
      assertEquals(afterDisplay[0]?.avatar_key, "person_green");
      assertEquals(afterDisplay[0]?.profile_photo_path, photoPath);

      const beforeRuntime = await profiles.getProfile(identity.appUserId);
      const runtimeUpdated = await profiles.updateProfile(
        identity.appUserId,
        auth,
        {
          version: beforeRuntime.version,
          displayName: "runtime canonical",
          phoneNumber: "+98 (912) 555-0101",
          locale: "de",
          timeZone: "Europe/Paris",
          avatarKey: "person_purple",
        },
      );
      assertEquals(runtimeUpdated.displayName, "runtime canonical");
      assertEquals(runtimeUpdated.phoneNumber, "+989125550101");
      assertEquals(runtimeUpdated.locale, "de");
      assertEquals(runtimeUpdated.timeZone, "Europe/Paris");
      assertEquals(runtimeUpdated.avatarKey, "person_purple");
      assertEquals(runtimeUpdated.version, Number(beforeRuntime.version) + 1);

      const currentPhoneRows = await admin`
        select normalized_value_hash,encode(encrypted_value,'base64') as ciphertext_b64,
               encryption_nonce_b64,encryption_key_version,status
        from identity.contact_points
        where account_id=${remappedAccountId}::uuid
          and kind='Phone'
          and status <> 'Revoked'
      `;
      assertEquals(currentPhoneRows.length, 1);
      const currentPhoneEnvelope: ContactPointEnvelope = {
        ciphertextB64: String(currentPhoneRows[0]?.ciphertext_b64),
        nonceB64: String(currentPhoneRows[0]?.encryption_nonce_b64),
        keyVersion: Number(currentPhoneRows[0]?.encryption_key_version),
      };
      assertEquals(
        await decryptContactPoint(
          { secret: encryptionSecret, keyVersion: encryptionKeyVersion },
          {
            accountId: remappedAccountId,
            kind: "Phone",
            normalizedValueHash: String(
              currentPhoneRows[0]?.normalized_value_hash,
            ),
          },
          currentPhoneEnvelope,
        ),
        "+989125550101",
      );
      const revokedPhones = await admin`
        select encrypted_value,encryption_nonce_b64,encryption_key_version
        from identity.contact_points
        where account_id=${remappedAccountId}::uuid
          and kind='Phone'
          and status='Revoked'
      `;
      assertEquals(revokedPhones.length, 1);
      assertEquals(revokedPhones[0]?.encrypted_value, null);
      assertEquals(revokedPhones[0]?.encryption_nonce_b64, null);
      assertEquals(revokedPhones[0]?.encryption_key_version, null);

      // Auth synchronization is bootstrap-only for a contact kind once an
      // explicit Profile replacement exists, so it cannot roll the Profile
      // phone back to the older Auth snapshot value.
      await identityBridge.syncExternalIdentities(identity.appUserId, {
        id: auth.id,
        email: auth.email,
        phone: auth.phone,
        identities: [],
      });
      const afterAuthResync = await admin`
        select normalized_value_hash,encode(encrypted_value,'base64') as ciphertext_b64,
               encryption_nonce_b64,encryption_key_version
        from identity.contact_points
        where account_id=${remappedAccountId}::uuid
          and kind='Phone'
          and status <> 'Revoked'
      `;
      const afterAuthEnvelope: ContactPointEnvelope = {
        ciphertextB64: String(afterAuthResync[0]?.ciphertext_b64),
        nonceB64: String(afterAuthResync[0]?.encryption_nonce_b64),
        keyVersion: Number(afterAuthResync[0]?.encryption_key_version),
      };
      assertEquals(
        await decryptContactPoint(
          { secret: encryptionSecret, keyVersion: encryptionKeyVersion },
          {
            accountId: remappedAccountId,
            kind: "Phone",
            normalizedValueHash: String(
              afterAuthResync[0]?.normalized_value_hash,
            ),
          },
          afterAuthEnvelope,
        ),
        "+989125550101",
      );

      const authority = await admin`
        select legacy.display_name as legacy_display_name,
               legacy.locale as legacy_locale,
               legacy.time_zone as legacy_time_zone,
               legacy.avatar_key as legacy_avatar_key,
               legacy.phone_number,
               person.display_name as person_display_name,
               person.locale as person_locale,
               person.time_zone as person_time_zone,
               person.avatar_key as person_avatar_key
        from lifemate.user_profiles legacy
        join core.person_profiles person
          on person.person_id = ${remappedPersonId}::uuid
        where legacy.user_id = ${identity.appUserId}::uuid
      `;
      assertEquals(authority[0]?.legacy_display_name, "legacy changed");
      assertEquals(authority[0]?.legacy_locale, "fa");
      assertEquals(authority[0]?.legacy_time_zone, "Asia/Tehran");
      assertEquals(authority[0]?.legacy_avatar_key, "person_blue");
      assertEquals(authority[0]?.phone_number, "+989125550101");
      assertEquals(authority[0]?.person_display_name, "runtime canonical");
      assertEquals(authority[0]?.person_locale, "de");
      assertEquals(authority[0]?.person_time_zone, "Europe/Paris");
      assertEquals(authority[0]?.person_avatar_key, "person_purple");
    } finally {
      if (appUserId) {
        await admin`
          delete from identity.contact_points
          where account_id=${remappedAccountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.account_person_links
          where account_id = ${remappedAccountId}::uuid
             or person_id = ${remappedPersonId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.person_profiles
          where person_id = ${remappedPersonId}::uuid
        `.catch(() => undefined);
        await admin`
          update identity.accounts
          set legacy_app_user_id = null, updated_at_utc = now()
          where id = ${remappedAccountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from identity.accounts where id = ${remappedAccountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.persons where id = ${remappedPersonId}::uuid
        `.catch(() => undefined);
        await admin`
          update identity.accounts
          set legacy_app_user_id = ${appUserId}::uuid, updated_at_utc = now()
          where id = ${appUserId}::uuid
        `.catch(() => undefined);
      }

      const users = await admin`
        select id from lifemate.app_users where auth_subject = ${auth.id}
      `;
      if (users[0]) {
        await admin`
          delete from lifemate.audit_logs
          where actor_user_id = ${users[0].id}
             or resource_id = ${users[0].id}
        `;
        await admin`
          delete from lifemate.user_profiles where user_id = ${users[0].id}
        `;
        await admin`
          delete from lifemate.app_users where id = ${users[0].id}
        `;
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
