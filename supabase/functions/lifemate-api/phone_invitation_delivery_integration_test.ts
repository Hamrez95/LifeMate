import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import {
  type AppIdentity,
  type AuthUser,
  createLifeMateDatabase,
} from "./database.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for phone invitation integration tests.",
  );
}

const contactSecret = "integration-only-contact-secret-with-32-plus-characters";

Deno.test({
  name:
    "phone invitations store only hashed contacts while SMS delivery stays retired",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const db = createLifeMateDatabase(databaseUrl, contactSecret);
    const suffix = crypto.randomUUID();
    const authSubject = `phone-retired-patient-${suffix}`;
    try {
      const patient = await bootstrap(
        db,
        auth(
          authSubject,
          `phone-retired-patient-${suffix}@example.test`,
          "+989121111111",
        ),
        "بیمار تست",
      );

      const invitation = await db.createInvitation(patient, {
        contactType: "phone",
        contact: "۰۹۳۵ ۱۲۳ ۵۶۷۸",
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
      });
      assertEquals(invitation.contactType, "phone");
      assert(typeof invitation.id === "string");
      assert(typeof invitation.token === "string");
      assert(String(invitation.token).length === 10);

      const invitations = await admin`
        select contact_hash,contact_hint,token_hash
        from lifemate.care_invitations
        where inviter_user_id = ${patient.appUserId}
          and contact_type = 'Phone'
      `;
      assertEquals(invitations.length, 1);
      assertEquals(invitations[0].contact_hint, invitation.contactHint);
      assert(String(invitations[0].contact_hash).length >= 64);
      assert(String(invitations[0].token_hash) !== invitation.token);
      assert(!JSON.stringify(invitations[0]).includes("+989351235678"));

      const audits = await admin`
        select count(*)::int as count
        from lifemate.audit_logs
        where actor_user_id = ${patient.appUserId}
          and action = 'care_invitation.phone_created'
      `;
      assertEquals(Number(audits[0]?.count ?? 0), 1);
    } finally {
      const users = await admin`
        select id::text as id from lifemate.app_users
        where auth_subject=${authSubject}
      `;
      const appUserId = String(users[0]?.id ?? "");
      if (appUserId) {
        const accounts = await admin`
          select id::text as id from identity.accounts
          where legacy_app_user_id=${appUserId}::uuid
        `;
        const accountIds = accounts.map((row) => String(row.id));
        const persons = accountIds.length > 0
          ? await admin`
            select person_id::text as id from core.account_person_links
            where account_id in ${admin(accountIds)} and link_type='Self'
          `
          : [];
        const personIds = persons.map((row) => String(row.id));
        await admin`
          delete from lifemate.care_invitations
          where inviter_user_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.audit_logs where actor_user_id=${appUserId}::uuid
        `.catch(() => undefined);
        if (accountIds.length > 0) {
          await admin`
            delete from consent.consent_records
            where actor_account_id in ${admin(accountIds)}
          `.catch(() => undefined);
          await admin`
            delete from identity.external_identity_tokens
            where account_id in ${admin(accountIds)}
          `.catch(() => undefined);
          await admin`
            delete from identity.external_identities
            where account_id in ${admin(accountIds)}
          `.catch(() => undefined);
          await admin`
            delete from core.account_person_links
            where account_id in ${admin(accountIds)}
          `.catch(() => undefined);
          await admin`
            update identity.accounts
            set legacy_app_user_id=null,updated_at_utc=now()
            where id in ${admin(accountIds)}
          `.catch(() => undefined);
          await admin`
            delete from identity.accounts where id in ${admin(accountIds)}
          `.catch(() => undefined);
        }
        if (personIds.length > 0) {
          await admin`
            delete from consent.consent_records
            where subject_person_id in ${admin(personIds)}
          `.catch(() => undefined);
          await admin`
            delete from core.person_profiles
            where person_id in ${admin(personIds)}
          `.catch(() => undefined);
          await admin`
            delete from core.persons where id in ${admin(personIds)}
          `.catch(() => undefined);
        }
        await admin`
          delete from lifemate.user_profiles where user_id=${appUserId}::uuid
        `.catch(() => undefined);
        await admin`
          delete from lifemate.app_users where id=${appUserId}::uuid
        `.catch(() => undefined);
      }
      await admin.end({ timeout: 5 });
    }
  },
});

function auth(subject: string, email: string, phone: string): AuthUser {
  return { id: subject, email, phone, userMetadata: {} };
}

async function bootstrap(
  db: ReturnType<typeof createLifeMateDatabase>,
  authUser: AuthUser,
  displayName: string,
): Promise<AppIdentity> {
  await db.bootstrapUser(authUser, {
    displayName,
    locale: "fa",
    timeZone: "Asia/Tehran",
  });
  return await db.requireIdentity(authUser);
}
