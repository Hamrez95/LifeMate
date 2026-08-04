from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'supabase/functions/lifemate-api/women_calendar.ts'
TEST = ROOT / 'supabase/functions/lifemate-api/women_calendar_integration_test.ts'

old_sql = '''            then (
                select max(started_on)
                from lifemate.women_calendar_episodes
                where owner_user_id = ${userId}
              )
              else last_period_start
'''
new_sql = '''            then coalesce(
              (
                select max(started_on)
                from lifemate.women_calendar_episodes
                where owner_user_id = ${userId}
              ),
              last_period_start
            )
              else last_period_start
'''

source = SOURCE.read_text(encoding='utf-8')
if old_sql in source:
    SOURCE.write_text(source.replace(old_sql, new_sql, 1), encoding='utf-8')
elif new_sql not in source:
    raise SystemExit('Expected women calendar profile reconciliation SQL was not found.')

old_test = '''      assertEquals(
        (await women.listOwnerEpisodes(patient.appUserId)).length,
        0,
      );
'''
new_test = '''      assertEquals(
        (await women.listOwnerEpisodes(patient.appUserId)).length,
        0,
      );
      const profileAfterDelete = await women.getOwnerProfile(patient.appUserId);
      assertEquals(profileAfterDelete.enabled, true);
      assertEquals(profileAfterDelete.lastPeriodStart, "2026-08-02");
'''

test = TEST.read_text(encoding='utf-8')
if old_test in test:
    TEST.write_text(test.replace(old_test, new_test, 1), encoding='utf-8')
elif new_test not in test:
    raise SystemExit('Expected women calendar delete integration assertion was not found.')

print('Women calendar last-episode deletion keeps the active profile valid.')
