from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "caremate/lib/models/care_recipient_reminder.dart"

value = PATH.read_text(encoding="utf-8")
old = """    if (!reminder.scheduledAtUtc.toUtc().isAfter(now) ||
        !reminder.triggerAtUtc.isAfter(now)) {
      continue;
    }
"""
new = """    if (!reminder.scheduledAtUtc.toUtc().isAfter(now) ||
        reminder.triggerAtUtc.isBefore(now)) {
      continue;
    }
"""

if new not in value:
    if old not in value:
        raise RuntimeError("Reminder due-now eligibility marker was not found.")
    PATH.write_text(value.replace(old, new, 1), encoding="utf-8")

print("Caregiver reminders due exactly now remain eligible.")
