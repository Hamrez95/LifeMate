from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
path = ROOT / 'supabase/functions/lifemate-api/care_events.ts'
text = path.read_text(encoding='utf-8')
old = '''        insert into lifemate.care_events
          (id, patient_user_id, client_request_id, event_type, title,'''
new = '''        insert into lifemate.care_events
          (id, patient_user_id, created_by_user_id, client_request_id, event_type, title,'''
if text.count(old) != 1:
    raise SystemExit('care event insert columns changed unexpectedly')
text = text.replace(old, new, 1)
old = '''        values
          (${id}, ${patientUserId}, ${input.clientRequestId},'''
new = '''        values
          (${id}, ${patientUserId}, ${patientUserId}, ${input.clientRequestId},'''
if text.count(old) != 1:
    raise SystemExit('care event insert values changed unexpectedly')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
Path(__file__).unlink()
workflow = ROOT / '.github/workflows/round2-care-event-compat-one-shot.yml'
if workflow.exists(): workflow.unlink()
print('care event created_by compatibility fixed')
