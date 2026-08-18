import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { createProfileStore } from "./profile.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for profile integration tests.",
  );
}

Deno.test({
  name:
    "profile avatar persists with optimistic concurrency and redacted audit",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const db = createLifeMateDatabase(
      databaseUrl,
      "integration-only-profile-contact-secret-32-bytes-minimum",
    );
    const profiles = createProfileStore(databaseUrl);
    const suffix = crypto.randomUUID();
    const auth: AuthUser = {
      id: `profile-${suffix}`,
      email: `profile-${suffix}@example.test`,
      phone: null,
      userMetadata: {},
    };
    const remappedAccountId = crypto.randomUUID();
    const remappedPersonId = crypto.randomUUID();
    let appUserId: string | null = null;

    try {
      await db.bootstrapUser(auth, {
        displayName: "نام اولیه",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const identity = await db.requireIdentity(auth);
      appUserId = identity.appUserId;

      // The bootstrap compatibility fixture initially uses equal UUIDs. Detach
      // only its legacy AppUser bridge and create a deliberately unequal
      // Account -> Self Person mapping, preserving the original bootstrap rows.
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

      const mapping = await admin`
        select core.self_person_id_for_legacy_app_user(
          ${identity.appUserId}::uuid
        )::text as person_id
      `;
      const personId = String(mapping[0]?.person_id ?? "");
      assertEquals(personId, remappedPersonId);
      assertEquals(personId === identity.appUserId, false);
      assertEquals(remappedAccountId === identity.appUserId, false);
      assertEquals(remappedAccountId === remappedPersonId, false);

      const initial = await profiles.getProfile(identity.appUserId);
      assertEquals(initial.version, 1);
      assertEquals(initial.displayName, "نام اولیه");
      assertEquals(initial.avatarKey, "person_blue");

      // Canonical Person-facing fields win even if the legacy compatibility
      // projection is stale. Contact/version fields remain legacy in this slice.
      await admin`
        update core.person_profiles
        set display_name = 'نام canonical',
            locale = 'en',
            time_zone = 'Europe/Berlin',
            avatar_key = 'person_green'
        where person_id = ${personId}::uuid
      `;
      const canonicalRead = await profiles.getProfile(identity.appUserId);
      assertEquals(canonicalRead.displayName, "نام canonical");
      assertEquals(canonicalRead.locale, "en");
      assertEquals(canonicalRead.timeZone, "Europe/Berlin");
      assertEquals(canonicalRead.avatarKey, "person_green");
      assertEquals(canonicalRead.version, 1);
      assertEquals(canonicalRead.email, auth.email);

      const updated = await profiles.updateProfile(identity.appUserId, auth, {
        version: 1,
        displayName: "نام ویرایش‌شده",
        phoneNumber: "+98 (912) 123-4567",
        locale: "fa",
        timeZone: "Europe/Berlin",
        avatarKey: "person_purple",
      });
      assertEquals(updated.version, 2);
      assertEquals(updated.displayName, "نام ویرایش‌شده");
      assertEquals(updated.phoneNumber, "+989121234567");
      assertEquals(updated.email, auth.email);
      assertEquals(updated.timeZone, "Europe/Berlin");
      assertEquals(updated.avatarKey, "person_purple");

      const stale = await assertRejects(
        () =>
          profiles.updateProfile(identity.appUserId, auth, {
            version: 1,
            displayName: "ویرایش قدیمی",
            phoneNumber: null,
            locale: "fa",
            timeZone: "Asia/Tehran",
            avatarKey: "person_green",
          }),
        ApiError,
      );
      assertEquals(stale.status, 409);
      assertEquals(stale.code, "stale_profile");

      const reconnected = createProfileStore(databaseUrl);
      const persisted = await reconnected.getProfile(identity.appUserId);
      assertEquals(persisted.version, 2);
      assertEquals(persisted.displayName, "نام ویرایش‌شده");
      assertEquals(persisted.avatarKey, "person_purple");

      const current = await db.currentUser(identity);
      const currentProfile = current.profile as Record<string, unknown>;
      assertEquals(currentProfile.avatarKey, "person_purple");

      const legacyPhotoPath = `${identity.appUserId}/legacy-profile.jpg`;
      const canonicalPhotoPath = `${identity.appUserId}/canonical-profile.jpg`;
      const replacementPhotoPath = `${identity.appUserId}/replacement-profile.jpg`;
      await admin`
        update lifemate.user_profiles
        set profile_photo_path = ${legacyPhotoPath}
        where user_id = ${identity.appUserId}::uuid
      `;
      await admin`
        update core.person_profiles
        set profile_photo_path = ${canonicalPhotoPath}
        where person_id = ${personId}::uuid
      `;
      assertEquals(
        await profiles.getProfilePhotoPath(identity.appUserId),
        canonicalPhotoPath,
      );
      assertEquals(
        await profiles.replaceProfilePhotoPath(
          identity.appUserId,
          replacementPhotoPath,
        ),
        canonicalPhotoPath,
      );
      const photoRows = await admin`
        select legacy.profile_photo_path as legacy_path,
               person.profile_photo_path as canonical_path
        from lifemate.user_profiles legacy
        join core.person_profiles person
          on person.person_id = ${personId}::uuid
        where legacy.user_id = ${identity.appUserId}::uuid
      `;
      assertEquals(photoRows[0]?.legacy_path, replacementPhotoPath);
      assertEquals(photoRows[0]?.canonical_path, replacementPhotoPath);

      const audits = await admin`
        select action, resource_type, metadata_json
        from lifemate.audit_logs
        where actor_user_id = ${identity.appUserId}
          and action in ('profile.updated', 'profile.photo_updated')
        order by action
      `;
      assertEquals(audits.length, 2);
      assertEquals(audits[0].metadata_json, null);
      assertEquals(audits[1].metadata_json, null);
    } finally {
      if (appUserId) {
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
      await admin.end({ timeout: 5 });
    }
  },
});
