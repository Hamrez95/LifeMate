import { assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createCareRequestStore } from "./care_requests.ts";
import {
  type AppIdentity,
  type AuthUser,
  createLifeMateDatabase,
} from "./database.ts";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createPhoneCareInvitationStore } from "./phone_care_invitation.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Person care request/invitation tests.",
  );
}

const contactSecret = "integration-only-contact-secret-with-32-plus-characters";

Deno.test({
  name:
    "care requests and phone invitations authorize relationships by unequal canonical Persons",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const db = createLifeMateDatabase(databaseUrl, contactSecret);
    const careRequests = createCareRequestStore(databaseUrl, contactSecret);
    const phoneInvitations = createPhoneCareInvitationStore(
      databaseUrl,
      contactSecret,
    );
    const suffix = crypto.randomUUID();

    try {
      const phonePatient = await bootstrap(
        db,
        auth(
          `person-phone-patient-${suffix}`,
          `person-phone-patient-${suffix}@example.test`,
          "+989121230001",
        ),
        "Phone Patient",
      );
      const phoneCaregiver = await bootstrap(
        db,
        auth(
          `person-phone-caregiver-${suffix}`,
          `person-phone-caregiver-${suffix}@example.test`,
          "+989121230002",
        ),
        "Phone Caregiver",
      );
      const requestPatient = await bootstrap(
        db,
        auth(
          `person-request-patient-${suffix}`,
          `person-request-patient-${suffix}@example.test`,
          "+989121230003",
        ),
        "Request Patient",
      );
      const requestCaregiver = await bootstrap(
        db,
        auth(
          `person-request-caregiver-${suffix}`,
          `person-request-caregiver-${suffix}@example.test`,
          "+989121230004",
        ),
        "Request Caregiver",
      );

      const phonePatientPerson = await remapSelfIdentity(
        admin,
        phonePatient.appUserId,
      );
      const phoneCaregiverPerson = await remapSelfIdentity(
        admin,
        phoneCaregiver.appUserId,
      );
      const requestPatientPerson = await remapSelfIdentity(
        admin,
        requestPatient.appUserId,
      );
      const requestCaregiverPerson = await remapSelfIdentity(
        admin,
        requestCaregiver.appUserId,
      );

      for (
        const [appUserId, accountId, personId] of [
          [
            phonePatient.appUserId,
            phonePatientPerson.accountId,
            phonePatientPerson.personId,
          ],
          [
            phoneCaregiver.appUserId,
            phoneCaregiverPerson.accountId,
            phoneCaregiverPerson.personId,
          ],
          [
            requestPatient.appUserId,
            requestPatientPerson.accountId,
            requestPatientPerson.personId,
          ],
          [
            requestCaregiver.appUserId,
            requestCaregiverPerson.accountId,
            requestCaregiverPerson.personId,
          ],
        ]
      ) {
        assertNotEquals(appUserId, accountId);
        assertNotEquals(appUserId, personId);
        assertNotEquals(accountId, personId);
      }

      const phoneInvitation = await phoneInvitations.createPhoneInvitation(
        phonePatient,
        {
          contact: phoneCaregiver.auth.phone,
          consentVersion: "care-patient-consent-v1",
          confirmConsent: true,
        },
      );
      const phoneRelationship = await phoneInvitations.acceptInvitationOrDelegate(
        phoneCaregiver,
        {
          token: phoneInvitation.token,
          consentVersion: "care-caregiver-consent-v1",
          confirmConsent: true,
        },
        () => Promise.reject(new Error("phone invitation delegated unexpectedly")),
      );
      assertEquals(phoneRelationship.status, "active");
      assertEquals(phoneRelationship.patientUserId, phonePatient.appUserId);
      assertEquals(phoneRelationship.caregiverUserId, phoneCaregiver.appUserId);

      const phonePersisted = await admin`
        select patient_user_id::text,caregiver_user_id::text,
               patient_person_id::text,caregiver_person_id::text
        from lifemate.care_relationships
        where id=${String(phoneRelationship.id)}::uuid
      `;
      assertEquals(phonePersisted.length, 1);
      assertEquals(phonePersisted[0].patient_user_id, phonePatient.appUserId);
      assertEquals(
        phonePersisted[0].caregiver_user_id,
        phoneCaregiver.appUserId,
      );
      assertEquals(
        phonePersisted[0].patient_person_id,
        phonePatientPerson.personId,
      );
      assertEquals(
        phonePersisted[0].caregiver_person_id,
        phoneCaregiverPerson.personId,
      );

      const phoneReplay = await phoneInvitations.acceptInvitationOrDelegate(
        phoneCaregiver,
        {
          token: phoneInvitation.token,
          consentVersion: "care-caregiver-consent-v1",
          confirmConsent: true,
        },
        () => Promise.reject(new Error("phone replay delegated unexpectedly")),
      );
      assertEquals(phoneReplay.id, phoneRelationship.id);

      const request = await careRequests.create(requestCaregiver, {
        contact: requestPatient.auth.email,
        consentVersion: "care-caregiver-request-v1",
        confirmConsent: true,
      });
      const accepted = await careRequests.respond(
        requestPatient,
        String(request.id),
        {
          action: "accept",
          consentVersion: "care-patient-consent-v1",
          confirmConsent: true,
        },
      );
      assertEquals(accepted.status, "accepted");

      const requestPersisted = await admin`
        select patient_user_id::text,caregiver_user_id::text,
               patient_person_id::text,caregiver_person_id::text
        from lifemate.care_relationships
        where id=${String(accepted.relationshipId)}::uuid
      `;
      assertEquals(requestPersisted.length, 1);
      assertEquals(
        requestPersisted[0].patient_user_id,
        requestPatient.appUserId,
      );
      assertEquals(
        requestPersisted[0].caregiver_user_id,
        requestCaregiver.appUserId,
      );
      assertEquals(
        requestPersisted[0].patient_person_id,
        requestPatientPerson.personId,
      );
      assertEquals(
        requestPersisted[0].caregiver_person_id,
        requestCaregiverPerson.personId,
      );

      await assertApiError(
        () =>
          careRequests.create(requestCaregiver, {
            contact: requestPatient.auth.email,
            consentVersion: "care-caregiver-request-v1",
            confirmConsent: true,
          }),
        409,
        "care_relationship_already_active",
      );

      const unmapped = await bootstrap(
        db,
        auth(
          `person-unmapped-caregiver-${suffix}`,
          `person-unmapped-caregiver-${suffix}@example.test`,
          "+989121230005",
        ),
        "Unmapped Caregiver",
      );
      await admin`
        update identity.accounts
        set legacy_app_user_id=null,updated_at_utc=now()
        where legacy_app_user_id=${unmapped.appUserId}::uuid
      `;
      await assertApiError(
        () =>
          careRequests.create(unmapped, {
            contact: requestPatient.auth.email,
            consentVersion: "care-caregiver-request-v1",
            confirmConsent: true,
          }),
        409,
        "identity_person_mapping_missing",
      );
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await admin.end({ timeout: 5 }).catch(() => undefined);
    }
  },
});

function auth(subject: string, email: string, phone: string): AuthUser {
  return {
    id: subject,
    email,
    phone,
    userMetadata: {},
  };
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

async function remapSelfIdentity(
  admin: ReturnType<typeof postgres>,
  appUserId: string,
): Promise<{ accountId: string; personId: string }> {
  const accountId = crypto.randomUUID();
  const personId = crypto.randomUUID();
  await admin.begin(async (tx) => {
    await tx`
      update identity.accounts
      set legacy_app_user_id=null,updated_at_utc=now()
      where legacy_app_user_id=${appUserId}::uuid
    `;
    await tx`
      insert into identity.accounts(id,legacy_app_user_id,status)
      values (${accountId}::uuid,${appUserId}::uuid,'Active')
    `;
    await tx`
      insert into core.persons(id,status,subject_category)
      values (${personId}::uuid,'Active','Adult')
    `;
    await tx`
      insert into core.account_person_links(account_id,person_id,link_type,status)
      values (${accountId}::uuid,${personId}::uuid,'Self','Active')
    `;
  });
  return { accountId, personId };
}

async function assertApiError(
  action: () => Promise<unknown>,
  status: number,
  code: string,
): Promise<void> {
  try {
    await action();
  } catch (error) {
    if (!(error instanceof ApiError)) throw error;
    assertEquals(error.status, status);
    assertEquals(error.code, code);
    return;
  }
  throw new Error(`Expected ApiError ${status}/${code}.`);
}
