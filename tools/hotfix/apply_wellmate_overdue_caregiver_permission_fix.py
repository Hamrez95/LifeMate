from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, found {count}")
    file.write_text(text.replace(old, new, 1))


# Health-record permission: app_users.auth_subject is varchar. The previous
# UUID cast produced PostgreSQL `character varying = uuid` failures for real
# WellMate sessions.
replace_once(
    "supabase/functions/lifemate-care-management/index.ts",
    "where auth_subject = ${authSubject}::uuid and status = 'Active'",
    "where auth_subject = ${authSubject} and status = 'Active'",
)

# Deno 2.9 strict typing: Deno.env.get returns string | undefined while this
# helper promises string | null. Keeping this clean lets the candidate source
# pass its real type-check rather than hiding an unrelated compiler failure.
replace_once(
    "supabase/functions/lifemate-care-management/index.ts",
    'return Deno.env.get("SUPABASE_ANON_KEY");',
    'return Deno.env.get("SUPABASE_ANON_KEY") ?? null;',
)

Path("supabase/functions/lifemate-care-management/index_test.ts").write_text(
    '''import { assert, assertFalse } from "jsr:@std/assert@1";\n\nDeno.test("care-management auth lookup preserves varchar auth_subject semantics", async () => {\n  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));\n  assert(source.includes("where auth_subject = ${authSubject} and status = 'Active'"));\n  assertFalse(source.includes("auth_subject = ${authSubject}::uuid"));\n  assert(source.includes('return Deno.env.get("SUPABASE_ANON_KEY") ?? null;'));\n});\n'''
)

# Home: immediately present a scheduled occurrence as overdue after its local
# scheduled time passes, independently of the backend's later missed-status
# materialization grace period.
home = "wellmate/lib/screens/home/home_screen_content.dart"
replace_once(
    home,
    """    final secondsLeft = _calculateSecondsLeft(item);\n    if (item.type == 'medicine') {\n      return ActiveTreatmentCard(\n        key: ValueKey('home-countdown-${item.type}-${item.id}'),\n        treatmentName: item.title,\n        dose: item.dosage,\n        time: item.time,\n        assetIconPath: _getAssetPath(item.type),\n        progressValue: _progressValue(item),\n        secondsLeft: secondsLeft,\n        onTaken: _submitting.contains(item.id)\n            ? null\n            : () => _reportStatus(item, 'taken'),\n        onSkipped: _submitting.contains(item.id)\n            ? null\n            : () => _reportStatus(item, 'skipped'),\n        onEdit: widget.onOpenTreatments,\n        isSubmitting: _submitting.contains(item.id),\n        font: font,\n      );\n    }\n\n    final isAppointment = item.type == 'appointment';""",
    """    final secondsLeft = _calculateSecondsLeft(item);\n    final overdue = isHomeScheduleOverdue(item, DateTime.now());\n    if (item.type == 'medicine') {\n      const missedColor = Color(0xFFE06464);\n      return ActiveTreatmentCard(\n        key: ValueKey('home-countdown-${item.type}-${item.id}'),\n        treatmentName: item.title,\n        dose: item.dosage,\n        time: item.time,\n        assetIconPath: _getAssetPath(item.type),\n        progressValue: _progressValue(item),\n        secondsLeft: secondsLeft,\n        onTaken: _submitting.contains(item.id)\n            ? null\n            : () => _reportStatus(item, 'taken'),\n        onSkipped: _submitting.contains(item.id)\n            ? null\n            : () => _reportStatus(item, 'skipped'),\n        onEdit: widget.onOpenTreatments,\n        isSubmitting: _submitting.contains(item.id),\n        supportingText: overdue\n            ? (isPersian ? 'مصرف‌نشده • ${item.time}' : 'Missed • ${item.time}')\n            : null,\n        countdownLabel: overdue ? (isPersian ? 'گذشته' : 'Missed') : null,\n        accentColor: overdue ? missedColor : null,\n        progressColor: overdue ? missedColor : null,\n        progressBackgroundColor: overdue ? const Color(0xFFFFEEEE) : null,\n        font: font,\n      );\n    }\n\n    final isAppointment = item.type == 'appointment';""",
)

replace_once(
    home,
    """    final isPersian = Localizations.localeOf(context).languageCode == 'fa';\n    final visibleToday = scheduleList.where((item) => !item.isDone).toList()\n      ..sort(_compareOccurrence);\n    final countdownItems = _countdownOccurrences;""",
    """    final isPersian = Localizations.localeOf(context).languageCode == 'fa';\n    final now = DateTime.now();\n    final visibleToday = scheduleList.where((item) => !item.isDone).toList()\n      ..sort((left, right) => compareHomeScheduleForDisplay(left, right, now));\n    final countdownItems = _countdownOccurrences;""",
)

replace_once(
    home,
    "                                  final missed = item.status == 'missed';",
    "                                  final missed = isHomeScheduleOverdue(item, now);",
)

marker = """DateTime? _homeCountdownScheduledDateTime(ScheduleItemModel item) {\n  if (item.scheduledAtUtc != null) return item.scheduledAtUtc!.toLocal();\n  final date = item.startDate;\n  final parts = item.time.split(':');\n  if (date == null || parts.length < 2) return null;\n  final hour = int.tryParse(parts[0]);\n  final minute = int.tryParse(parts[1].split(' ').first);\n  if (hour == null || minute == null) return null;\n  return DateTime(date.year, date.month, date.day, hour, minute);\n}\n"""
addition = marker + """\n@visibleForTesting\nbool isHomeScheduleOverdue(ScheduleItemModel item, DateTime now) {\n  if (item.isDone) return false;\n  final status = item.status.trim().toLowerCase();\n  if (status == 'missed') return true;\n  if (status != 'scheduled') return false;\n  final scheduled = _homeCountdownScheduledDateTime(item);\n  return scheduled != null && scheduled.isBefore(now);\n}\n\n@visibleForTesting\nint compareHomeScheduleForDisplay(\n  ScheduleItemModel left,\n  ScheduleItemModel right,\n  DateTime now,\n) {\n  final leftOverdue = isHomeScheduleOverdue(left, now);\n  final rightOverdue = isHomeScheduleOverdue(right, now);\n  if (leftOverdue != rightOverdue) return leftOverdue ? 1 : -1;\n  final leftDate = _homeCountdownScheduledDateTime(left) ?? DateTime(2100);\n  final rightDate = _homeCountdownScheduledDateTime(right) ?? DateTime(2100);\n  return leftDate.compareTo(rightDate);\n}\n"""
replace_once(home, marker, addition)

Path("wellmate/test/home_overdue_display_test.dart").write_text(
    '''import 'package:flutter_test/flutter_test.dart';\nimport 'package:wellmate/models/schedule_item_model.dart';\nimport 'package:wellmate/screens/home/home_screen_content.dart';\n\nvoid main() {\n  test('past scheduled dose is overdue immediately for home presentation', () {\n    final now = DateTime(2026, 8, 10, 9, 49);\n    final past = _item(id: 'past', time: '09:30');\n    final future = _item(id: 'future', time: '18:30');\n    final taken = _item(id: 'taken', time: '08:00', status: 'taken', isDone: true);\n\n    expect(isHomeScheduleOverdue(past, now), isTrue);\n    expect(isHomeScheduleOverdue(future, now), isFalse);\n    expect(isHomeScheduleOverdue(taken, now), isFalse);\n  });\n\n  test('home ordering keeps upcoming items before overdue items', () {\n    final now = DateTime(2026, 8, 10, 9, 49);\n    final items = <ScheduleItemModel>[\n      _item(id: 'past', time: '09:30'),\n      _item(id: 'future-late', time: '20:00'),\n      _item(id: 'future-next', time: '18:30'),\n    ]..sort((a, b) => compareHomeScheduleForDisplay(a, b, now));\n\n    expect(items.map((item) => item.id), ['future-next', 'future-late', 'past']);\n  });\n}\n\nScheduleItemModel _item({\n  required String id,\n  required String time,\n  String status = 'scheduled',\n  bool isDone = false,\n}) => ScheduleItemModel(\n  id: id,\n  title: id,\n  time: time,\n  dosage: '',\n  type: 'medicine',\n  frequency: 'روزانه',\n  status: status,\n  isDone: isDone,\n  startDate: DateTime(2026, 8, 10),\n);\n'''
)

# Caregiver screen: the empty request state must not show decision controls;
# those controls belong only on a real future CareMate-originated request.
care = "wellmate/lib/screens/profile/care_access_screen.dart"
file = Path(care)
text = file.read_text()
start = text.index("class _NoIncomingRequestsCard extends StatelessWidget")
end = text.index("class _CaregiverCard extends StatelessWidget")
text = text[:start] + '''class _NoIncomingRequestsCard extends StatelessWidget {\n  const _NoIncomingRequestsCard();\n\n  @override\n  Widget build(BuildContext context) => Container(\n    padding: const EdgeInsets.all(16),\n    decoration: BoxDecoration(\n      color: Colors.white.withValues(alpha: 0.78),\n      borderRadius: BorderRadius.circular(22),\n      border: Border.all(color: const Color(0xFFE4EEE8)),\n    ),\n    child: const Row(\n      children: [\n        CircleAvatar(\n          radius: 21,\n          backgroundColor: Color(0xFFF0F6F3),\n          child: Icon(\n            Icons.inbox_outlined,\n            color: AppColors.textSecondary,\n            size: 21,\n          ),\n        ),\n        SizedBox(width: 12),\n        Expanded(\n          child: Text(\n            'درخواست جدیدی برای بررسی ندارید. وقتی قابلیت درخواست مراقبت از سمت CareMate فعال شود، درخواست واقعی هر فرد همین‌جا نمایش داده می‌شود.',\n            style: TextStyle(\n              height: 1.55,\n              fontSize: 12.5,\n              color: AppColors.textSecondary,\n            ),\n          ),\n        ),\n      ],\n    ),\n  );\n}\n\n''' + text[end:]
file.write_text(text)

# Active caregiver cards already receive signed photo URLs/avatar keys from the
# API; render those instead of discarding them and showing the first letter.
replace_once(
    care,
    """    final canSeeWomenCalendar = relationship['canViewWomenCalendar'] == true;\n    final initial = name.isEmpty ? 'م' : name.substring(0, 1);""",
    """    final canSeeWomenCalendar = relationship['canViewWomenCalendar'] == true;\n    final rawPhotoUrl = relationship['caregiverProfilePhotoUrl']?.toString().trim();\n    final photoUrl = rawPhotoUrl == null || rawPhotoUrl.isEmpty ? null : rawPhotoUrl;\n    final rawAvatarKey = relationship['caregiverAvatarKey']?.toString().trim();\n    final avatarKey = rawAvatarKey == null || rawAvatarKey.isEmpty\n        ? 'caregiver_teal'\n        : rawAvatarKey;""",
)

replace_once(
    care,
    """              Container(\n                width: 58,\n                height: 58,\n                decoration: BoxDecoration(\n                  gradient: LinearGradient(\n                    colors: [\n                      AppColors.primary.withValues(alpha: 0.18),\n                      const Color(0xFFEFFAF5),\n                    ],\n                  ),\n                  shape: BoxShape.circle,\n                ),\n                alignment: Alignment.center,\n                child: Text(\n                  initial,\n                  style: const TextStyle(\n                    fontSize: 21,\n                    fontWeight: FontWeight.w900,\n                    color: AppColors.primary,\n                  ),\n                ),\n              ),""",
    """              LifeMateProfileAvatar(\n                key: ValueKey('caregiver-profile-avatar-${relationship['id']}'),\n                avatarKey: avatarKey,\n                photoUrl: photoUrl,\n                radius: 29,\n              ),""",
)

visual = Path("wellmate/test/care_access_visual_contract_test.dart")
source = visual.read_text()
anchor = "    expect(source, contains('revokeCareInvitation('));\n"
if source.count(anchor) != 1:
    raise SystemExit("care access visual test anchor not found exactly once")
source = source.replace(
    anchor,
    anchor
    + '''    expect(source, contains("relationship['caregiverProfilePhotoUrl']"));\n    expect(source, contains("relationship['caregiverAvatarKey']"));\n    expect(source, contains('LifeMateProfileAvatar('));\n\n    final emptyStart = source.indexOf('class _NoIncomingRequestsCard');\n    final emptyEnd = source.indexOf('class _CaregiverCard');\n    final emptyState = source.substring(emptyStart, emptyEnd);\n    expect(emptyState, contains('Icons.inbox_outlined'));\n    expect(emptyState, isNot(contains('Icons.check_rounded')));\n    expect(emptyState, isNot(contains('Icons.close_rounded')));\n''',
    1,
)
visual.write_text(source)
