import { assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { hashContactPoint } from "../_shared/contact_point_crypto.ts";
import { createCareRequestStore } from "./care_requests.ts";
import {
  type AppIdentity,
  type AuthUser,
  createLifeMateDatabase,
} from "./database.ts";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for phone care request integration tests.",
  );
}

const contactSecret = "integration-only-contact-secret-with-32-plus-characters";

Deno.test({
  name:
    "phone care request is non-enumerating, Person-safe, consent-gated and retry-safe",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const db = createLifeMateDatabase(databaseUrl, contactSecret);
    const requests = createCareRequestStore(databaseUrl, contactSecret);
    const suffix = crypto.randomUUID();

    try {
      const patient = await bootstrap(
        db,
        auth(
          `phone-request-patient-${suffix}`,
          `phone-request-patient-${suffix}@example.test`,
          "+989121230101",
        ),
        "Phone Request Patient",
      );
      const caregiver = await bootstrap(
        db,
        auth(
          `phone-request-caregiver-${suffix}`,
          `phone-request-caregiver-${suffix}@example.test`,
          "+989121230102",
        ),
        "Phone Request Caregiver",
      );
      const unrelated = await bootstrap(
        db,
        auth(
          `phone-request-unrelated-${suffix}`,
          `phone-request-unrelated-${suffix}@example.test`,
          "+989121230103",
        ),
        "Phone Request Unrelated",
      );

      const patientMap = await remapSelfIdentity(admin, patient.appUserId);
      const caregiverMap = await remapSelfIdentity(admin, caregiver.appUserId);
      const unrelatedMap = await remapSelfIdentity(admin, unrelated.appUserId);
      for (
        const [appUserId, accountId, personId] of [
          [patient.appUserId, patientMap.accountId, patientMap.personId],
          [caregiver.appUserId, caregiverMap.accountId, caregiverMap.personId],
          [unrelated.appUserId, unrelatedMap.accountId, unrelatedMap.personId],
        ]
      ) {
        assertNotEquals(appUserId, accountId);
        assertNotEquals(appUserId, personId);
        assertNotEquals(accountId, personId);
      }

      const phoneHash = await hashContactPoint(
        contactSecret,
        "Phone",
        patient.auth.phone!,
      );
      await admin`
        insert into identity.contact_points(
          account_id,kind,normalized_value_hash,status,verified_at_utc
        ) values(
          ${patientMap.accountId}::uuid,'Phone',${phoneHash},'Verified',now()
        )
      `;

      const beforeRelationships = await relationshipCount(
        admin,
        patientMap.personId,
        caregiverMap.personId,
      );
      assertEquals(beforeRelationships, 0);

      const created = await requests.create(caregiver, {
        contactType: "phone",
        contact: patient.auth.phone,
        consentVersion: "care-caregiver-request-v1",
        confirmConsent: true,
      });
      assertEquals(created.contactType, "phone");
      assertEquals(created.status, "pending");

      const retry = await requests.create(caregiver, {
        contactType: "phone",
        contact: patient.auth.phone,
        consentVersion: "care-caregiver-request-v1",
        confirmConsent: true,
      });
      assertEquals(retry.id, created.id);
      assertEquals(
        await relationshipCount(
          admin,
          patientMap.personId,
          caregiverMap.personId,
        ),
        0,
      );

      const persisted = await admin`
        select contact_type,target_account_id::text,status,contact_hint,
               token_hash,contact_hash
        from lifemate.care_invitations
        where id=${String(created.id)}::uuid
      `;
      assertEquals(persisted.length, 1);
      assertEquals(persisted[0].contact_type, "CareRequestPhone");
      assertEquals(persisted[0].target_account_id, patientMap.accountId);
      assertEquals(persisted[0].status, "Pending");
      assertEquals(
        String(persisted[0].contact_hint).includes("9121230101"),
        false,
      );
      assertEquals(String(persisted[0].contact_hash).includes("+989"), false);
      assertEquals(String(persisted[0].token_hash).includes("+989"), false);

      const patientIncoming = await requests.listIncoming(patient);
      assertEquals(
        patientIncoming.some((item) => item.id === created.id),
        true,
      );
      const unrelatedIncoming = await requests.listIncoming(unrelated);
      assertEquals(
        unrelatedIncoming.some((item) => item.id === created.id),
        false,
      );

      await assertApiError(
        () =>
          requests.respond(unrelated, String(created.id), {
            action: "accept",
            consentVersion: "care-patient-consent-v1",
            confirmConsent: true,
          }),
        404,
        "care_request_not_found",
      );
      await assertApiError(
        () =>
          requests.respond(patient, String(created.id), {
            action: "accept",
            consentVersion: "care-patient-consent-v1",
            confirmConsent: false,
          }),
        400,
        "patient_consent_required",
      );
      assertEquals(
        await relationshipCount(
          admin,
          patientMap.personId,
          caregiverMap.personId,
        ),
        0,
      );

      const accepted = await requests.respond(patient, String(created.id), {
        action: "accept",
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
      });
      assertEquals(accepted.status, "accepted");

      const relationship = await admin`
        select id::text,patient_user_id::text,caregiver_user_id::text,
               patient_person_id::text,caregiver_person_id::text,status
        from lifemate.care_relationships
        where id=${String(accepted.relationshipId)}::uuid
      `;
      assertEquals(relationship.length, 1);
      assertEquals(relationship[0].patient_user_id, patient.appUserId);
      assertEquals(relationship[0].caregiver_user_id, caregiver.appUserId);
      assertEquals(relationship[0].patient_person_id, patientMap.personId);
      assertEquals(relationship[0].caregiver_person_id, caregiverMap.personId);
      assertEquals(relationship[0].status, "Active");

      const unmatched = await requests.create(caregiver, {
        contactType: "phone",
        contact: "+989121239999",
        consentVersion: "care-caregiver-request-v1",
        confirmConsent: true,
      });
      assertEquals(unmatched.status, "pending");
      const unmatchedPersisted = await admin`
        select target_account_id
        from lifemate.care_invitations
        where id=${String(unmatched.id)}::uuid
      `;
      assertEquals(unmatchedPersisted[0]?.target_account_id, null);
      await requests.cancel(caregiver.appUserId, String(unmatched.id));
      const cancelled = await admin`
        select status from lifemate.care_invitations
        where id=${String(unmatched.id)}::uuid
      `;
      assertEquals(cancelled[0]?.status, "Revoked");

      await admin`
        update identity.accounts
        set status='DeletionPending',updated_at_utc=now()
        where id=${patientMap.accountId}::uuid
      `;
      const severed = await admin`
        select target_account_id
        from lifemate.care_invitations
        where id=${String(created.id)}::uuid
      `;
      assertEquals(severed[0]?.target_account_id, null);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await admin.end({ timeout: 5 }).catch(() => undefined);
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

async function relationshipCount(
  admin: ReturnType<typeof postgres>,
  patientPersonId: string,
  caregiverPersonId: string,
): Promise<number> {
  const rows = await admin`
    select count(*)::int as count
    from lifemate.care_relationships
    where patient_person_id=${patientPersonId}::uuid
      and caregiver_person_id=${caregiverPersonId}::uuid
      and status='Active'
  `;
  return Number(rows[0]?.count ?? 0);
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
