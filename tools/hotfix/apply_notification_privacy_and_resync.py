from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    if old not in text:
        if new in text:
            return
        raise SystemExit(f'Expected notification snippet not found in {path}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
    'wellmate/lib/providers/notification_provider.dart',
    '    for (final dose in doses) {\n',
    '''    final pending = await _notifications.pendingNotificationRequests();
    for (final request in pending) {
      if (request.payload?.startsWith('dose:') == true) {
        await _notifications.cancel(request.id);
      }
    }

    for (final dose in doses) {
''',
)

replace_once(
    'caremate/lib/providers/care_notification_provider.dart',
    '    await _notifications.cancelAll();\n',
    '''    final pending = await _notifications.pendingNotificationRequests();
    for (final request in pending) {
      if (request.payload?.startsWith('care-dose:') == true) {
        await _notifications.cancel(request.id);
      }
    }
''',
)

for path in (
    'wellmate/lib/providers/notification_provider.dart',
    'caremate/lib/providers/care_notification_provider.dart',
):
    replace_once(
        path,
        '''            category: AndroidNotificationCategory.reminder,
          ),
''',
        '''            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.private,
          ),
''',
    )

replace_once(
    'caremate/lib/screens/dashboard_screen.dart',
    "debugPrint('CareMate notification scheduling failed: $error');",
    "debugPrint('CareMate notification scheduling failed.');",
)

print('Scoped notification resync, lock-screen privacy, and log redaction applied.')
