import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";

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
    const db = createLifeMateDatabase(
      databaseUrl,
      "integration-only-profile-projection-secret-32-bytes-minimum",
    );
    const suffix = crypto.randomUUID();
    const auth: AuthUser = {
      id: `profile-projection-${suffix}`,
      email: `profile-projection-${suffix}@example.test`,
      phone: null,
      userMetadata: {},
    };
    const remappedAccountId = crypto.randomUUID();
    const remappedPersonId = crypto.randomUUID();
    let appUserId: string | null = null;

    try {
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
