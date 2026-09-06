from pathlib import Path

path = Path("supabase/functions/lifemate-api/person_women_calendar.ts")
text = path.read_text()
old = '''              private_notes = ${privateNotes},
              share_summary_with_companion = ${shareSummaryWithCompanion},
              version = version + 1, updated_at_utc = ${now}'''
new = '''              private_notes = ${privateNotes},
              share_summary_with_companion = case
                when ${shareSummaryProvided}
                  then ${shareSummaryWithCompanion}
                else share_summary_with_companion
              end,
              version = version + 1, updated_at_utc = ${now}'''
if old not in text:
    raise SystemExit("person update sharing seam changed")
text = text.replace(old, new, 1)
path.write_text(text)

path = Path("supabase/functions/lifemate-api/women_calendar_integration_test.ts")
text = path.read_text()
old = '''      const privateReplay = await women.upsertOwnerDailyLog(
        patient.appUserId,
        {
          version: privateReplay.version,'''
new = '''      const privateReplay = await women.upsertOwnerDailyLog(
        patient.appUserId,
        {
          version: privateDailyLog.version,'''
if old not in text:
    raise SystemExit("private replay version seam changed")
text = text.replace(old, new, 1)
old = '''        ownerDailyLogs[0].privateNotes,
        "daily note that must remain owner only",'''
new = '''        ownerDailyLogs[0].privateNotes,
        "offline owner replay stays private",'''
if old not in text:
    raise SystemExit("owner replay expectation seam changed")
text = text.replace(old, new, 1)
old = '''      const sharedDailyLog = await women.upsertOwnerDailyLog(
        patient.appUserId,
        {
          version: privateDailyLog.version,'''
new = '''      const sharedDailyLog = await women.upsertOwnerDailyLog(
        patient.appUserId,
        {
          version: privateReplay.version,'''
if old not in text:
    raise SystemExit("shared daily log version seam changed")
text = text.replace(old, new, 1)
path.write_text(text)
