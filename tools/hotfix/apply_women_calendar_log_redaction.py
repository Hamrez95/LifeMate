from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FILES = [
    ROOT / 'wellmate/lib/screens/women_calendar/women_calendar_screen.dart',
    ROOT / 'wellmate/lib/screens/profile/care_access_settings_screen.dart',
    ROOT / 'wellmate/lib/screens/home/home_screen.dart',
    ROOT / 'wellmate/lib/screens/profile/profile_destination_screens.dart',
]
REPLACEMENTS = {
    "debugPrint('Women calendar load failed: $error');":
        "debugPrint('Women calendar load failed.');",
    "debugPrint('Care permission profile load failed: $error');":
        "debugPrint('Care permission profile load failed.');",
    "debugPrint('Care permission update failed: $error');":
        "debugPrint('Care permission update failed.');",
    "debugPrint('Women calendar navigation state failed: $error');":
        "debugPrint('Women calendar navigation state failed.');",
    "debugPrint('Subscription women calendar load failed: $error');":
        "debugPrint('Subscription women calendar load failed.');",
}

changed = 0
for path in FILES:
    text = path.read_text(encoding='utf-8')
    updated = text
    for old, new in REPLACEMENTS.items():
        updated = updated.replace(old, new)
    if updated != text:
        path.write_text(updated, encoding='utf-8')
        changed += 1

for path in FILES:
    text = path.read_text(encoding='utf-8')
    leaked = [old for old in REPLACEMENTS if old in text]
    if leaked:
        raise SystemExit(f'Unredacted diagnostic remains in {path}: {leaked}')

print(f'Women calendar diagnostic redaction applied to {changed} file(s).')
