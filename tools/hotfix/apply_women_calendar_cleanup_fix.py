from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / 'supabase/functions/lifemate-api/women_calendar_integration_test.ts'


def replace_once(old: str, new: str) -> None:
    text = TARGET.read_text(encoding='utf-8')
    if old not in text:
        if new in text:
            return
        raise SystemExit(
            'Expected women calendar integration cleanup snippet was not found.'
        )
    TARGET.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
    r'''    } finally {
      await admin`
        delete from lifemate.app_users
        where auth_subject in ${admin([
          patientAuth.id,
          caregiverAuth.id,
          unrelatedAuth.id,
        ])}
      `;
      await admin.end({ timeout: 5 });
    }
''',
    r'''    } finally {
      const authSubjects = [
        patientAuth.id,
        caregiverAuth.id,
        unrelatedAuth.id,
      ];
      try {
        await cleanupWomenCalendarRun(admin, authSubjects);
        // A second pass makes idempotency part of the integration contract.
        await cleanupWomenCalendarRun(admin, authSubjects);
      } finally {
        await admin.end({ timeout: 5 });
      }
    }
''',
)

replace_once(
    '\nfunction auth(id: string, email: string): AuthUser {\n',
    r'''
type AdminSql = ReturnType<typeof postgres>;

async function cleanupWomenCalendarRun(
  admin: AdminSql,
  authSubjects: string[],
): Promise<void> {
  const userRows = await admin`
    select id
    from lifemate.app_users
    where auth_subject in ${admin(authSubjects)}
  `;
  const userIds = userRows.map((row) => String(row.id));
  if (userIds.length === 0) {
    return;
  }

  await admin.begin(async (tx: any) => {
    await tx`
      delete from lifemate.women_calendar_support_actions
      where patient_user_id in ${tx(userIds)}
         or caregiver_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.women_calendar_episodes
      where owner_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.women_calendar_profiles
      where owner_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.care_events
      where patient_user_id in ${tx(userIds)}
         or created_by_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.dose_adherence_events
      where actor_user_id in ${tx(userIds)}
         or occurrence_id in (
           select id
           from lifemate.dose_occurrences
           where patient_user_id in ${tx(userIds)}
         )
    `;
    await tx`
      delete from lifemate.dose_occurrences
      where patient_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.treatment_schedules
      where treatment_plan_id in (
        select id
        from lifemate.treatment_plans
        where patient_user_id in ${tx(userIds)}
      )
    `;
    await tx`
      delete from lifemate.treatment_plans
      where patient_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.medications
      where owner_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.care_relationships
      where patient_user_id in ${tx(userIds)}
         or caregiver_user_id in ${tx(userIds)}
         or revoked_by_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.care_invitations
      where inviter_user_id in ${tx(userIds)}
         or responded_by_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.privacy_consents
      where user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.audit_logs
      where actor_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.user_profiles
      where user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.app_users
      where id in ${tx(userIds)}
    `;
  });
}

function auth(id: string, email: string): AuthUser {
''',
)

print('Dependency-safe women calendar integration cleanup patch applied.')
