import { assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { createCareCompletionNotificationStore } from "./care_completion_notifications.ts";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required for completion notification tests.");
}

Deno.test({
  name: "completion claims are preference aware idempotent current-state and revoked safe",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const store = createCareCompletionNotificationStore(databaseUrl);
    const patientUserId = crypto.randomUUID();
    const caregiverUserId = crypto.randomUUID();
    const patientAccountId = crypto.randomUUID();
    const caregiverAccountId = crypto.randomUUID();
    const patientPersonId = crypto.randomUUID();
    const caregiverPersonId = crypto.randomUUID();
    const relationshipId = crypto.randomUUID();
    const medicationId = crypto.randomUUID();
    const planId = crypto.randomUUID();
    const scheduleId = crypto.randomUUID();
    const occurrenceId = crypto.randomUUID();
    const eventId = crypto.randomUUID();
    const requestId = crypto.randomUUID();

    try {
      await admin.begin(async (tx) => {
        await tx`
          insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc)
          values
            (${patientUserId}::uuid,${crypto.randomUUID()},'Active',now(),now()),
            (${caregiverUserId}::uuid,${crypto.randomUUID()},'Active',now(),now())
        `;
        await tx`
          insert into identity.accounts(id,legacy_app_user_id,status)
          values
            (${patientAccountId}::uuid,${patientUserId}::uuid,'Active'),
            (${caregiverAccountId}::uuid,${caregiverUserId}::uuid,'Active')
        `;
        await tx`
          insert into core.persons(id,status,subject_category)
          values
            (${patientPersonId}::uuid,'Active','Adult'),
            (${caregiverPersonId}::uuid,'Active','Adult')
        `;
        await tx`
          insert into core.person_profiles(person_id,display_name,locale,time_zone)
          values
            (${patientPersonId}::uuid,'مامان جون','fa','Asia/Tehran'),
            (${caregiverPersonId}::uuid,'Caregiver','fa','Asia/Tehran')
        `;
        await tx`
          insert into core.account_person_links(account_id,person_id,link_type,status)
          values
            (${patientAccountId}::uuid,${patientPersonId}::uuid,'Self','Active'),
            (${caregiverAccountId}::uuid,${caregiverPersonId}::uuid,'Self','Active')
        `;
        await tx`
          insert into lifemate.care_relationships(
            id,patient_user_id,caregiver_user_id,patient_person_id,caregiver_person_id,status,
            patient_consent_version,patient_consented_at_utc,
            caregiver_consent_version,caregiver_consented_at_utc,
            caregiver_notifications_enabled,caregiver_completion_mode,
            created_at_utc,updated_at_utc
          ) values (
            ${relationshipId}::uuid,${patientUserId}::uuid,${caregiverUserId}::uuid,
            ${patientPersonId}::uuid,${caregiverPersonId}::uuid,'Active',
            'patient-v1',now(),'caregiver-v1',now(),true,'all',now(),now()
          )
        `;
        await tx`
          insert into lifemate.medications(
            id,owner_person_id,name,strength_text,form,notes,version,created_at_utc,updated_at_utc
          ) values (${medicationId}::uuid,${patientPersonId}::uuid,'Metformin','500 mg','tablet',null,1,now(),now())
        `;
        await tx`
          insert into lifemate.treatment_plans(
            id,patient_person_id,medication_id,dose_text,instructions,start_date,end_date,time_zone,
            status,version,created_at_utc,updated_at_utc
          ) values (
            ${planId}::uuid,${patientPersonId}::uuid,${medicationId}::uuid,'1 tablet',null,
            current_date,current_date,'Asia/Tehran','Active',1,now(),now()
          )
        `;
        await tx`
          insert into lifemate.treatment_schedules(id,treatment_plan_id,day_of_week,local_time,created_at_utc)
          values (${scheduleId}::uuid,${planId}::uuid,'monday','08:00',now())
        `;
        await tx`
          insert into lifemate.dose_occurrences(
            id,patient_person_id,treatment_plan_id,treatment_schedule_id,scheduled_at_utc,
            scheduled_local_date,scheduled_local_time,time_zone,status,responded_at_utc,version,
            created_at_utc,updated_at_utc
          ) values (
            ${occurrenceId}::uuid,${patientPersonId}::uuid,${planId}::uuid,${scheduleId}::uuid,
            now()-interval '5 minutes',current_date,'08:00','Asia/Tehran','Taken',now(),2,now(),now()
          )
        `;
        await tx`
          insert into lifemate.dose_adherence_events(
            id,occurrence_id,actor_user_id,client_request_id,event_type,previous_status,
            resulting_status,occurred_at_utc,recorded_at_utc
          ) values (
            ${eventId}::uuid,${occurrenceId}::uuid,${patientUserId}::uuid,${requestId}::uuid,
            'Taken','Scheduled','Taken',now()-interval '1 minute',now()
          )
        `;
      });

      final first = await store.claim(caregiverUserId, relationshipId);
      assertEquals(first.length, 1);
      assertEquals(first[0].patientDisplayName, "مامان جون");
      assertEquals(first[0].medicationName, "Metformin");
      assertEquals(first[0].evidenceClass, "self_reported");

      final duplicate = await store.claim(caregiverUserId, relationshipId);
      assertEquals(duplicate.length, 0);

      final history = await store.history(caregiverUserId, relationshipId);
      assertEquals(history.length, 1);

      await admin`
        update lifemate.dose_occurrences
        set status='Skipped',version=version+1,updated_at_utc=now()
        where id=${occurrenceId}::uuid
      `;
      assertEquals((await store.history(caregiverUserId, relationshipId)).length, 0);

      await admin`
        update lifemate.dose_occurrences set status='Taken',updated_at_utc=now()
        where id=${occurrenceId}::uuid
      `;
      await admin`
        update lifemate.care_relationships set status='Revoked',revoked_at_utc=now(),updated_at_utc=now()
        where id=${relationshipId}::uuid
      `;
      assertEquals((await store.history(caregiverUserId, relationshipId)).length, 0);
      assertEquals((await store.claim(caregiverUserId, relationshipId)).length, 0);
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      await admin.begin(async (tx) => {
        await tx`delete from lifemate.caregiver_completion_notification_receipts where relationship_id=${relationshipId}::uuid`;
        await tx`delete from lifemate.dose_adherence_events where occurrence_id=${occurrenceId}::uuid`;
        await tx`delete from lifemate.dose_occurrences where id=${occurrenceId}::uuid`;
        await tx`delete from lifemate.treatment_schedules where id=${scheduleId}::uuid`;
        await tx`delete from lifemate.treatment_plans where id=${planId}::uuid`;
        await tx`delete from lifemate.medications where id=${medicationId}::uuid`;
        await tx`delete from lifemate.care_relationships where id=${relationshipId}::uuid`;
        await tx`delete from core.account_person_links where account_id in (${patientAccountId}::uuid,${caregiverAccountId}::uuid)`;
        await tx`delete from core.person_profiles where person_id in (${patientPersonId}::uuid,${caregiverPersonId}::uuid)`;
        await tx`delete from core.persons where id in (${patientPersonId}::uuid,${caregiverPersonId}::uuid)`;
        await tx`delete from identity.accounts where id in (${patientAccountId}::uuid,${caregiverAccountId}::uuid)`;
        await tx`delete from lifemate.app_users where id in (${patientUserId}::uuid,${caregiverUserId}::uuid)`;
      }).catch(() => undefined);
      await admin.end({ timeout: 5 }).catch(() => undefined);
    }
  },
});
