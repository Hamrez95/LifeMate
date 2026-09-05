import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import postgres from "postgres";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for deletion integration tests.",
  );
}

const sql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

Deno.test({
  name:
    "retention-v3.1 deletes owner health data, anonymizes identity, and preserves another patient's data",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const accountId = crypto.randomUUID();
    const appUserId = crypto.randomUUID();
    const authSubject = crypto.randomUUID();
    const personId = crypto.randomUUID();
    const survivorUserId = crypto.randomUUID();
    const survivorAuthSubject = crypto.randomUUID();
    const survivorPersonId = crypto.randomUUID();
    const survivorAccountId = crypto.randomUUID();
    const medicationId = crypto.randomUUID();
    const planId = crypto.randomUUID();
    const scheduleId = crypto.randomUUID();
    const occurrenceId = crypto.randomUUID();
    const ownRelationshipId = crypto.randomUUID();
    const survivorRelationshipId = crypto.randomUUID();
    const survivorCareEventId = crypto.randomUUID();
    const survivorInvitationId = crypto.randomUUID();

    const sourceApplicationRows = await sql`
      select id from ecosystem.applications where code='wellmate' limit 1
    `;
    const sourceApplicationId = String(sourceApplicationRows[0].id);

    try {
      await sql`
        insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc)
        values
          (${appUserId}::uuid,${authSubject},'Active',now(),now()),
          (${survivorUserId}::uuid,${survivorAuthSubject},'Active',now(),now())
      `;

      // The bootstrap compatibility trigger intentionally creates same-ID
      // Account/Person rows for a brand-new legacy user. Remove those generated
      // rows and install explicit mappings so this test proves every deletion
      // path works when Account != AppUser != Person.
      await sql`
        delete from commerce.entitlements
        where grantee_account_id in (${appUserId}::uuid,${survivorUserId}::uuid)
           or beneficiary_person_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `;
      await sql`
        delete from ecosystem.app_enrollments
        where account_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `;
      await sql`
        delete from identity.external_identities
        where account_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `;
      await sql`
        delete from core.account_person_links
        where account_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `;
      await sql`
        delete from identity.accounts
        where id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `;
      await sql`
        delete from core.persons
        where id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `;

      await sql`
        insert into identity.accounts(id,status,home_region,legacy_app_user_id)
        values
          (${accountId}::uuid,'Active','IR-THR',${appUserId}::uuid),
          (${survivorAccountId}::uuid,'Active','IR-THR',${survivorUserId}::uuid)
      `;
      await sql`
        insert into core.persons(id,status,subject_category,home_region,birth_date)
        values
          (${personId}::uuid,'Active','Adult','IR-THR','1990-01-01'),
          (${survivorPersonId}::uuid,'Active','Adult','IR-THR','1991-01-01')
      `;
      await sql`
        insert into core.account_person_links(account_id,person_id,link_type,status)
        values
          (${accountId}::uuid,${personId}::uuid,'Self','Active'),
          (${survivorAccountId}::uuid,${survivorPersonId}::uuid,'Self','Active')
      `;

      await sql`
        insert into lifemate.user_profiles(
          id,user_id,display_name,phone_number,email,locale,time_zone,avatar_key,
          profile_photo_path,created_at_utc,updated_at_utc
        ) values (
          ${crypto.randomUUID()}::uuid,${appUserId}::uuid,'Delete Me',
          '+989121234567','delete-me@example.test','fa','Asia/Tehran','person_green',
          ${`${appUserId}/${crypto.randomUUID()}.jpg`},now(),now()
        )
      `;

      await sql`
        insert into lifemate.medications(
          id,owner_user_id,owner_person_id,name,version,created_at_utc,updated_at_utc
        ) values (
          ${medicationId}::uuid,${appUserId}::uuid,${personId}::uuid,
          'private-medication',1,now(),now()
        )
      `;
      await sql`
        insert into lifemate.treatment_plans(
          id,patient_user_id,patient_person_id,medication_id,dose_text,start_date,
          time_zone,status,version,created_at_utc,updated_at_utc
        ) values (
          ${planId}::uuid,${appUserId}::uuid,${personId}::uuid,
          ${medicationId}::uuid,'1 tablet',current_date,'Asia/Tehran',
          'Active',1,now(),now()
        )
      `;
      await sql`
        insert into lifemate.treatment_schedules(
          id,treatment_plan_id,day_of_week,local_time,created_at_utc
        ) values (${scheduleId}::uuid,${planId}::uuid,'Daily','08:00',now())
      `;
      await sql`
        insert into lifemate.dose_occurrences(
          id,patient_user_id,patient_person_id,treatment_plan_id,treatment_schedule_id,
          scheduled_at_utc,scheduled_local_date,scheduled_local_time,time_zone,status,
          version,created_at_utc,updated_at_utc
        ) values (
          ${occurrenceId}::uuid,${appUserId}::uuid,${personId}::uuid,
          ${planId}::uuid,${scheduleId}::uuid,now(),current_date,'08:00',
          'Asia/Tehran','scheduled',1,now(),now()
        )
      `;
      await sql`
        insert into lifemate.dose_adherence_events(
          id,occurrence_id,actor_user_id,client_request_id,event_type,
          previous_status,resulting_status,occurred_at_utc,recorded_at_utc
        ) values (
          ${crypto.randomUUID()}::uuid,${occurrenceId}::uuid,${appUserId}::uuid,
          ${crypto.randomUUID()}::uuid,'Taken','scheduled','taken',now(),now()
        )
      `;

      // recorded_by_account_id is deliberately omitted. The provenance trigger
      // must map the legacy AppUser actor to the provider-agnostic Account.
      await sql`
        insert into lifemate.health_observations(
          id,owner_user_id,person_id,client_request_id,observation_type,
          value_primary,unit_primary,observed_at_utc,observed_local_date,time_zone,
          source_category,source_provider,source_application_id
        ) values (
          ${crypto.randomUUID()}::uuid,${appUserId}::uuid,${personId}::uuid,
          ${crypto.randomUUID()}::uuid,'weight',81.5,'kg',now(),current_date,
          'Asia/Tehran','FirstPartyUserInput','wellmate',${sourceApplicationId}::uuid
        )
      `;

      await sql`
        insert into lifemate.care_events(
          id,patient_user_id,patient_person_id,created_by_user_id,client_request_id,
          event_type,title,scheduled_local_date,scheduled_local_time,time_zone,
          created_at_utc,updated_at_utc
        ) values (
          ${crypto.randomUUID()}::uuid,${appUserId}::uuid,${personId}::uuid,
          ${appUserId}::uuid,${crypto.randomUUID()}::uuid,'Appointment','private visit',
          current_date,'10:00','Asia/Tehran',now(),now()
        ),(
          ${survivorCareEventId}::uuid,${survivorUserId}::uuid,${survivorPersonId}::uuid,
          ${appUserId}::uuid,${crypto.randomUUID()}::uuid,'Appointment','survivor visit',
          current_date,'11:00','Asia/Tehran',now(),now()
        )
      `;

      await sql`
        insert into lifemate.care_relationships(
          id,patient_user_id,caregiver_user_id,status,
          patient_consent_version,patient_consented_at_utc,
          caregiver_consent_version,caregiver_consented_at_utc,
          created_at_utc,updated_at_utc
        ) values
          (${ownRelationshipId}::uuid,${appUserId}::uuid,${survivorUserId}::uuid,'Active',
           'patient-v1',now(),'caregiver-v1',now(),now(),now()),
          (${survivorRelationshipId}::uuid,${survivorUserId}::uuid,${appUserId}::uuid,'Active',
           'patient-v1',now(),'caregiver-v1',now(),now(),now())
      `;

      await sql`
        insert into lifemate.women_calendar_profiles(
          owner_user_id,owner_person_id,enabled,last_period_start,created_at_utc,updated_at_utc
        ) values (
          ${appUserId}::uuid,${personId}::uuid,true,current_date,now(),now()
        )
      `;
      await sql`
        insert into lifemate.women_calendar_episodes(
          id,owner_user_id,owner_person_id,started_on,created_at_utc,updated_at_utc
        ) values (
          ${crypto.randomUUID()}::uuid,${appUserId}::uuid,${personId}::uuid,
          current_date,now(),now()
        )
      `;
      await sql`
        insert into lifemate.women_calendar_daily_logs(
          id,owner_user_id,owner_person_id,logged_on,mood,energy_level,pain_level,
          created_at_utc,updated_at_utc
        ) values (
          ${crypto.randomUUID()}::uuid,${appUserId}::uuid,${personId}::uuid,
          current_date,'Neutral',3,2,now(),now()
        )
      `;
      await sql`
        insert into lifemate.women_calendar_support_actions(
          id,patient_user_id,patient_person_id,caregiver_user_id,relationship_id,
          action_type,performed_at_utc,created_at_utc
        ) values (
          ${crypto.randomUUID()}::uuid,${appUserId}::uuid,${personId}::uuid,
          ${survivorUserId}::uuid,${ownRelationshipId}::uuid,'CheckIn',now(),now()
        )
      `;

      await sql`
        insert into lifemate.care_invitations(
          id,inviter_user_id,contact_type,contact_hash,contact_hint,token_hash,
          patient_consent_version,status,expires_at_utc,created_at_utc
        ) values (
          ${crypto.randomUUID()}::uuid,${appUserId}::uuid,'email','private-contact-hash',
          'd***@example.test','private-token-hash','patient-v1','Pending',
          now()+interval '10 minutes',now()
        )
      `;
      await sql`
        insert into lifemate.care_invitations(
          id,inviter_user_id,contact_type,contact_hash,contact_hint,token_hash,
          patient_consent_version,status,expires_at_utc,responded_by_user_id,
          responded_at_utc,created_at_utc
        ) values (
          ${survivorInvitationId}::uuid,${survivorUserId}::uuid,'email','survivor-hash',
          's***@example.test','survivor-token','patient-v1','Accepted',
          now()+interval '10 minutes',${appUserId}::uuid,now(),now()
        )
      `;

      await sql`
        insert into lifemate.idempotency_keys(
          actor_auth_subject,operation,idempotency_key,request_hash,status,
          response_status,response_body,created_at_utc,updated_at_utc,expires_at_utc
        ) values (
          ${authSubject}::uuid,'dose-report','delete-me-request',
          '0000000000000000000000000000000000000000000000000000000000000000',
          'Completed',200,'{"private":"health-response"}',now(),now(),
          now()+interval '1 day'
        )
      `;
      await sql`
        insert into lifemate.audit_logs(
          id,actor_user_id,action,resource_type,metadata_json,created_at_utc
        ) values (
          ${crypto.randomUUID()}::uuid,${appUserId}::uuid,'profile.updated','profile',
          '{"private":"delete-me@example.test"}'::jsonb,now()
        )
      `;
      await sql`
        insert into care.daily_adherence_summary(person_id,summary_date)
        values (${personId}::uuid,current_date)
      `;
      await sql`
        insert into network.person_relationships(
          source_person_id,target_person_id,relationship_type,status
        ) values (${personId}::uuid,${survivorPersonId}::uuid,'Parent','Active')
      `;

      const requested = await sql`
        select identity.request_account_deletion(${accountId}::uuid) as id
      `;
      const requestId = String(requested[0].id);

      const preFinalize = await sql`
        select r.retention_policy_version,
               a.status as account_status,
               u.status as user_status,
               n.status as network_status,
               (select count(*)::int
                  from security.access_grants g
                 where g.context_type='care_relationship'
                   and g.context_id in (
                     ${ownRelationshipId}::uuid,
                     ${survivorRelationshipId}::uuid
                   )
                   and g.status='Active') as active_grants,
               (select count(*)::int
                  from lifemate.care_relationships cr
                 where cr.id in (
                   ${ownRelationshipId}::uuid,
                   ${survivorRelationshipId}::uuid
                 ) and cr.status='Active') as active_relationships
        from identity.account_deletion_requests r
        join identity.accounts a on a.id=r.account_id
        join lifemate.app_users u on u.id=${appUserId}::uuid
        join network.person_relationships n
          on n.source_person_id=${personId}::uuid
         and n.target_person_id=${survivorPersonId}::uuid
        where r.id=${requestId}::uuid
      `;
      assertEquals(preFinalize[0].retention_policy_version, "retention-v3.1");
      assertEquals(preFinalize[0].account_status, "DeletionPending");
      assertEquals(preFinalize[0].user_status, "Disabled");
      assertEquals(preFinalize[0].network_status, "Ended");
      assertEquals(Number(preFinalize[0].active_grants), 0);
      assertEquals(Number(preFinalize[0].active_relationships), 0);

      assertEquals(
        (await sql`
          select has_table_privilege(
            'lifemate_worker_runtime','lifemate.medications','DELETE'
          ) as allowed
        `)[0].allowed,
        false,
      );
      assertEquals(
        (await sql`
          select has_function_privilege(
            'lifemate_worker_runtime',
            'identity.finalize_account_deletion(uuid)',
            'EXECUTE'
          ) as allowed
        `)[0].allowed,
        true,
      );

      await sql.unsafe("set role lifemate_worker_runtime");
      try {
        const finalized = await sql`
          select identity.finalize_account_deletion(${requestId}::uuid) as ok
        `;
        assertEquals(finalized[0].ok, true);
      } finally {
        await sql.unsafe("reset role");
      }

      const deletionProof = await sql`
        select
          (select count(*)::int from lifemate.medications
            where owner_user_id=${appUserId}::uuid) as medications,
          (select count(*)::int from lifemate.treatment_plans
            where patient_user_id=${appUserId}::uuid) as plans,
          (select count(*)::int from lifemate.dose_occurrences
            where patient_user_id=${appUserId}::uuid) as occurrences,
          (select count(*)::int from lifemate.dose_adherence_events
            where occurrence_id=${occurrenceId}::uuid) as adherence_events,
          (select count(*)::int from lifemate.health_observations
            where owner_user_id=${appUserId}::uuid) as health_observations,
          (select count(*)::int from lifemate.care_events
            where patient_user_id=${appUserId}::uuid) as own_care_events,
          (select count(*)::int from lifemate.women_calendar_profiles
            where owner_user_id=${appUserId}::uuid) as women_profiles,
          (select count(*)::int from lifemate.women_calendar_episodes
            where owner_user_id=${appUserId}::uuid) as women_episodes,
          (select count(*)::int from lifemate.women_calendar_daily_logs
            where owner_user_id=${appUserId}::uuid) as women_logs,
          (select count(*)::int from lifemate.women_calendar_support_actions
            where patient_user_id=${appUserId}::uuid) as women_support_actions,
          (select count(*)::int from care.daily_adherence_summary
            where person_id=${personId}::uuid) as adherence_summaries,
          (select count(*)::int from lifemate.care_events
            where id=${survivorCareEventId}::uuid
              and patient_user_id=${survivorUserId}::uuid) as survivor_care_events,
          (select count(*)::int from lifemate.idempotency_keys
            where actor_auth_subject=${authSubject}::uuid) as idempotency_keys,
          (select count(*)::int from lifemate.care_invitations
            where inviter_user_id=${appUserId}::uuid) as own_invitations
      `;

      assertEquals(Number(deletionProof[0].medications), 0);
      assertEquals(Number(deletionProof[0].plans), 0);
      assertEquals(Number(deletionProof[0].occurrences), 0);
      assertEquals(Number(deletionProof[0].adherence_events), 0);
      assertEquals(Number(deletionProof[0].health_observations), 0);
      assertEquals(Number(deletionProof[0].own_care_events), 0);
      assertEquals(Number(deletionProof[0].women_profiles), 0);
      assertEquals(Number(deletionProof[0].women_episodes), 0);
      assertEquals(Number(deletionProof[0].women_logs), 0);
      assertEquals(Number(deletionProof[0].women_support_actions), 0);
      assertEquals(Number(deletionProof[0].adherence_summaries), 0);
      assertEquals(Number(deletionProof[0].survivor_care_events), 1);
      assertEquals(Number(deletionProof[0].idempotency_keys), 0);
      assertEquals(Number(deletionProof[0].own_invitations), 0);

      const tombstone = await sql`
        select a.status as account_status,
               a.home_region,
               u.status as user_status,
               u.auth_subject,
               p.display_name,
               p.phone_number,
               p.email,
               p.profile_photo_path,
               person.status as person_status,
               person.subject_category,
               person.home_region as person_region,
               person.birth_date,
               l.status as link_status,
               l.revoked_at_utc,
               r.status as deletion_status,
               r.retention_policy_version
        from identity.accounts a
        join lifemate.app_users u on u.id=${appUserId}::uuid
        join lifemate.user_profiles p on p.user_id=u.id
        join core.account_person_links l
          on l.account_id=a.id and l.link_type='Self'
        join core.persons person on person.id=l.person_id
        join identity.account_deletion_requests r on r.account_id=a.id
        where a.id=${accountId}::uuid
      `;
      assertEquals(tombstone[0].account_status, "Deleted");
      assertEquals(tombstone[0].home_region, null);
      assertEquals(tombstone[0].user_status, "Deleted");
      assert(String(tombstone[0].auth_subject).startsWith("deleted:"));
      assertEquals(tombstone[0].display_name, "Deleted user");
      assertEquals(tombstone[0].phone_number, null);
      assertEquals(tombstone[0].email, null);
      assertEquals(tombstone[0].profile_photo_path, null);
      assertEquals(tombstone[0].person_status, "Deleted");
      assertEquals(tombstone[0].subject_category, "Unknown");
      assertEquals(tombstone[0].person_region, null);
      assertEquals(tombstone[0].birth_date, null);
      assertEquals(tombstone[0].link_status, "Revoked");
      assert(tombstone[0].revoked_at_utc !== null);
      assertEquals(tombstone[0].deletion_status, "Completed");
      assertEquals(tombstone[0].retention_policy_version, "retention-v3.1");

      const audit = await sql`
        select actor_user_id,metadata_json
        from lifemate.audit_logs
        where action='profile.updated' and resource_type='profile'
        order by created_at_utc desc
        limit 1
      `;
      assertEquals(audit[0].actor_user_id, null);
      assertEquals(audit[0].metadata_json.redacted, "account_deleted");

      const survivorInvitation = await sql`
        select responded_by_user_id
        from lifemate.care_invitations
        where id=${survivorInvitationId}::uuid
      `;
      assertEquals(survivorInvitation[0].responded_by_user_id, null);
    } finally {
      await sql.unsafe("reset role").catch(() => undefined);

      await sql`
        delete from lifemate.women_calendar_support_actions
        where patient_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
           or caregiver_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.women_calendar_daily_logs
        where owner_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.women_calendar_episodes
        where owner_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.women_calendar_profiles
        where owner_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.care_events
        where patient_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
           or created_by_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.dose_adherence_events
        where occurrence_id=${occurrenceId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from lifemate.dose_occurrences
        where patient_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.treatment_plans
        where patient_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.medications
        where owner_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.health_observations
        where owner_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from care.daily_adherence_summary
        where person_id in (${personId}::uuid,${survivorPersonId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.idempotency_keys
        where actor_auth_subject in (${authSubject}::uuid,${survivorAuthSubject}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.care_invitations
        where inviter_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.care_relationships
        where patient_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
           or caregiver_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from consent.consent_events
        where consent_record_id in (
          select id from consent.consent_records
          where scope_key in (
            ${`care_relationship:${ownRelationshipId}`},
            ${`care_relationship:${survivorRelationshipId}`}
          )
        )
      `.catch(() => undefined);
      await sql`
        delete from consent.consent_records
        where scope_key in (
          ${`care_relationship:${ownRelationshipId}`},
          ${`care_relationship:${survivorRelationshipId}`}
        )
      `.catch(() => undefined);
      await sql`
        delete from security.access_grants
        where context_id in (${ownRelationshipId}::uuid,${survivorRelationshipId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from integration.outbox_messages
        where aggregate_id=${accountId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from identity.account_deletion_requests
        where account_id=${accountId}::uuid
      `.catch(() => undefined);
      await sql`
        delete from lifemate.audit_logs
        where actor_user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
           or actor_user_id is null
      `.catch(() => undefined);
      await sql`
        delete from network.person_relationships
        where source_person_id in (${personId}::uuid,${survivorPersonId}::uuid)
           or target_person_id in (${personId}::uuid,${survivorPersonId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from commerce.entitlements
        where grantee_account_id in (${accountId}::uuid,${survivorAccountId}::uuid)
           or beneficiary_person_id in (${personId}::uuid,${survivorPersonId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from ecosystem.app_enrollments
        where account_id in (${accountId}::uuid,${survivorAccountId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from identity.contact_points
        where account_id in (${accountId}::uuid,${survivorAccountId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from identity.external_identities
        where account_id in (${accountId}::uuid,${survivorAccountId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.user_profiles
        where user_id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from core.person_profiles
        where person_id in (${personId}::uuid,${survivorPersonId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from core.account_person_links
        where account_id in (${accountId}::uuid,${survivorAccountId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from identity.accounts
        where id in (${accountId}::uuid,${survivorAccountId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from core.persons
        where id in (${personId}::uuid,${survivorPersonId}::uuid)
      `.catch(() => undefined);
      await sql`
        delete from lifemate.app_users
        where id in (${appUserId}::uuid,${survivorUserId}::uuid)
      `.catch(() => undefined);
    }
  },
});
