import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { type AuthUser, createLifeMateDatabase } from "./database.ts";
import { createIdentityBridge } from "./identity_bridge.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for token-only bootstrap integration tests.",
  );
}

Deno.test({
  name:
    "token-only bootstrap reuses canonical identity without legacy rebootstrap",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const authSubject = crypto.randomUUID();
    const auth: AuthUser = {
      id: authSubject,
      email: `token-bootstrap-${authSubject}@example.test`,
      phone: null,
      userMetadata: {},
    };
    const remappedAccountId = crypto.randomUUID();
    const remappedPersonId = crypto.randomUUID();
    const key = "token-only-bootstrap-test-key-32-bytes-minimum";
    const keyVersion = 9;
    const previousMode = Deno.env.get("LIFEMATE_IDENTITY_LINK_LOOKUP_MODE");
    const previousDualWrite = Deno.env.get("LIFEMATE_IDENTITY_LINK_DUAL_WRITE");
    const previousKey = Deno.env.get("LIFEMATE_IDENTITY_LINK_KEY");
    const previousKeyVersion = Deno.env.get(
      "LIFEMATE_IDENTITY_LINK_KEY_VERSION",
    );
    let appUserId: string | null = null;

    try {
      Deno.env.set("LIFEMATE_IDENTITY_LINK_LOOKUP_MODE", "token-only");
      Deno.env.set("LIFEMATE_IDENTITY_LINK_DUAL_WRITE", "true");
      Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY", key);
      Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY_VERSION", String(keyVersion));

      const db = createLifeMateDatabase(
        databaseUrl,
        "integration-only-token-bootstrap-contact-secret-32-bytes",
      );
      assertEquals(db.identityLookupMode, "token-only");

      // No canonical token exists yet, so the first bootstrap is allowed to use
      // the staged legacy compatibility path. The API route subsequently calls
      // the identity bridge; this test performs that same synchronization.
      await db.bootstrapUser(auth, {
        displayName: "legacy bootstrap",
        locale: "fa",
        timeZone: "Asia/Tehran",
      });
      const appRows = await admin`
        select id::text as id
        from lifemate.app_users
        where auth_subject=${authSubject}
      `;
      appUserId = String(appRows[0]?.id ?? "");
      if (!appUserId) throw new Error("bootstrap AppUser was not created");

      // Detach the compatibility Account and create unequal Account + Self
      // Person identities. This proves token-only bootstrap follows explicit
      // mapping rather than relying on UUID equality.
      await admin`
        update identity.accounts
        set legacy_app_user_id=null,updated_at_utc=now()
        where id=${appUserId}::uuid
      `;
      await admin`
        insert into identity.accounts(
          id,legacy_app_user_id,status,created_at_utc,updated_at_utc
        ) values(
          ${remappedAccountId}::uuid,${appUserId}::uuid,'Active',now(),now()
        )
      `;
      await admin`
        insert into core.persons(id,status,subject_category)
        values (${remappedPersonId}::uuid,'Active','Adult')
      `;
      await admin`
        insert into core.account_person_links(
          account_id,person_id,link_type,status,created_at_utc
        ) values(
          ${remappedAccountId}::uuid,${remappedPersonId}::uuid,
          'Self','Active',now()
        )
      `;
      await admin`
        insert into core.person_profiles(
          person_id,display_name,locale,time_zone,avatar_key,
          profile_photo_path,created_at_utc,updated_at_utc
        )
        select ${remappedPersonId}::uuid,display_name,locale,time_zone,
               avatar_key,profile_photo_path,created_at_utc,updated_at_utc
        from lifemate.user_profiles
        where user_id=${appUserId}::uuid
      `;

      const bridge = createIdentityBridge(databaseUrl);
      await bridge.syncExternalIdentities(appUserId, {
        id: authSubject,
        identities: [],
      });
      const tokenRows = await admin`
        select account_id::text as account_id
        from identity.external_identity_tokens
        where provider='supabase_auth'
          and issuer='supabase'
          and account_id=${remappedAccountId}::uuid
          and status='Active'
      `;
      assertEquals(tokenRows.length, 1);
      assertEquals(tokenRows[0]?.account_id, remappedAccountId);

      await admin`
        update core.person_profiles
        set display_name='canonical retained',
            locale='en',
            time_zone='Europe/Berlin',
            avatar_key='person_green',
            updated_at_utc=now()
        where person_id=${remappedPersonId}::uuid
      `;

      const beforeAudits = await admin`
        select count(*)::int as count
        from lifemate.audit_logs
        where actor_user_id=${appUserId}::uuid and action='user.bootstrap'
      `;
      assertEquals(Number(beforeAudits[0]?.count), 1);

      const repeated = await db.bootstrapUser(auth, {
        displayName: "must not rebootstrap",
        locale: "fa",
        timeZone: "Europe/Paris",
      });
      const profile = repeated.profile as Record<string, unknown>;
      assertEquals(profile.displayName, "canonical retained");
      assertEquals(profile.locale, "en");
      assertEquals(profile.timeZone, "Europe/Berlin");
      assertEquals(profile.avatarKey, "person_green");

      const afterAudits = await admin`
        select count(*)::int as count
        from lifemate.audit_logs
        where actor_user_id=${appUserId}::uuid and action='user.bootstrap'
      `;
      assertEquals(Number(afterAudits[0]?.count), 1);
      const appUserCount = await admin`
        select count(*)::int as count
        from lifemate.app_users
        where auth_subject=${authSubject}
      `;
      assertEquals(Number(appUserCount[0]?.count), 1);

      // Disabled canonical accounts fail closed at the bootstrap account-state
      // guard before token-only resolution can attempt any legacy fallback.
      await admin`
        update identity.accounts
        set status='Disabled',updated_at_utc=now()
        where id=${remappedAccountId}::uuid
      `;
      const broken = await assertRejects(
        () =>
          db.bootstrapUser(auth, {
            displayName: "must fail closed",
            locale: "fa",
            timeZone: "Asia/Tehran",
          }),
        ApiError,
      );
      assertEquals(broken.status, 409);
      assertEquals(broken.code, "account_disabled");
      const finalAudits = await admin`
        select count(*)::int as count
        from lifemate.audit_logs
        where actor_user_id=${appUserId}::uuid and action='user.bootstrap'
      `;
      assertEquals(Number(finalAudits[0]?.count), 1);
    } finally {
      if (appUserId) {
        await admin`
          delete from identity.external_identity_tokens
          where account_id in (
            ${appUserId}::uuid,${remappedAccountId}::uuid
          )
        `.catch(() => undefined);
        await admin`
          delete from identity.external_identities
          where account_id in (
            ${appUserId}::uuid,${remappedAccountId}::uuid
          )
        `.catch(() => undefined);
        await admin`
          delete from core.account_person_links
          where account_id=${remappedAccountId}::uuid
             or person_id=${remappedPersonId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.person_profiles
          where person_id=${remappedPersonId}::uuid
        `.catch(() => undefined);
        await admin`
          update identity.accounts
          set legacy_app_user_id=null,updated_at_utc=now()
          where id=${remappedAccountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from identity.accounts
          where id=${remappedAccountId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.persons
          where id=${remappedPersonId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.audit_logs
          where actor_user_id=${appUserId}::uuid
             or resource_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.user_profiles
          where user_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from identity.accounts
          where id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.app_users
          where id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from core.persons
          where id=${appUserId}::uuid
        `.catch(() => undefined);
      }

      if (previousMode == null) {
        Deno.env.delete("LIFEMATE_IDENTITY_LINK_LOOKUP_MODE");
      } else {
        Deno.env.set("LIFEMATE_IDENTITY_LINK_LOOKUP_MODE", previousMode);
      }
      if (previousDualWrite == null) {
        Deno.env.delete("LIFEMATE_IDENTITY_LINK_DUAL_WRITE");
      } else {
        Deno.env.set("LIFEMATE_IDENTITY_LINK_DUAL_WRITE", previousDualWrite);
      }
      if (previousKey == null) Deno.env.delete("LIFEMATE_IDENTITY_LINK_KEY");
      else Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY", previousKey);
      if (previousKeyVersion == null) {
        Deno.env.delete("LIFEMATE_IDENTITY_LINK_KEY_VERSION");
      } else {
        Deno.env.set("LIFEMATE_IDENTITY_LINK_KEY_VERSION", previousKeyVersion);
      }
      await admin.end({ timeout: 5 });
    }
  },
});
