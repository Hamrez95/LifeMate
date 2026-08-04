from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    if old not in text:
        if new in text:
            return
        raise SystemExit(f'Expected snippet not found in {path}: {old[:140]!r}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


write(
    'caremate/lib/models/care_recipient_reminder.dart',
    r'''class CareRecipientReminder {
  const CareRecipientReminder({
    required this.patientUserId,
    required this.patientName,
    required this.doseId,
    required this.medicationName,
    required this.doseText,
    required this.scheduledAtUtc,
  });

  final String patientUserId;
  final String patientName;
  final String doseId;
  final String medicationName;
  final String doseText;
  final DateTime scheduledAtUtc;
}

List<CareRecipientReminder> selectEarliestReminderPerPatient(
  Iterable<CareRecipientReminder> reminders, {
  DateTime? nowUtc,
}) {
  final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
  final selected = <String, CareRecipientReminder>{};
  for (final reminder in reminders) {
    final scheduled = reminder.scheduledAtUtc.toUtc();
    if (!scheduled.isAfter(now)) continue;
    final existing = selected[reminder.patientUserId];
    if (existing == null ||
        scheduled.isBefore(existing.scheduledAtUtc.toUtc())) {
      selected[reminder.patientUserId] = reminder;
    }
  }
  final result = selected.values.toList(growable: false)
    ..sort((a, b) => a.scheduledAtUtc.compareTo(b.scheduledAtUtc));
  return result;
}
''',
)

write(
    'caremate/lib/providers/care_notification_provider.dart',
    r'''import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/utils/string_extensions.dart';
import '../models/care_recipient_reminder.dart';

class CareNotificationProvider extends ChangeNotifier {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionRequested = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(settings);
    _initialized = true;
  }

  Future<void> syncEarliestPerRecipient(
    Iterable<CareRecipientReminder> candidates, {
    required String timeZone,
    required bool isPersian,
  }) async {
    await initialize();
    try {
      tz.setLocalLocation(tz.getLocation(timeZone));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
    }

    if (!_permissionRequested) {
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
      _permissionRequested = true;
    }

    await _notifications.cancelAll();
    final reminders = selectEarliestReminderPerPatient(candidates);
    for (final reminder in reminders) {
      final localTime = tz.TZDateTime.from(reminder.scheduledAtUtc, tz.local);
      final timeText =
          '${localTime.hour.toString().padLeft(2, '0')}:'
                  '${localTime.minute.toString().padLeft(2, '0')}'
              .toPersianDigit(isPersian);
      final title = isPersian
          ? 'داروی بعدی ${reminder.patientName.toPersianDigit(true)}'
          : '${reminder.patientName} next medicine';
      final detail = [
        reminder.medicationName,
        if (reminder.doseText.trim().isNotEmpty) reminder.doseText.trim(),
        timeText,
      ].join(' • ').toPersianDigit(isPersian);

      await _notifications.zonedSchedule(
        _notificationId(reminder.patientUserId),
        title,
        detail,
        localTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'caremate_next_dose',
            'داروی بعدی افراد تحت مراقبت',
            channelDescription:
                'فقط نزدیک‌ترین داروی هر فرد تحت مراقبت در CareMate',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload:
            'care-dose:${reminder.patientUserId}:${reminder.doseId}',
      );
    }
  }

  static int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in 'care:$value'.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
''',
)

write(
    'caremate/lib/screens/women_calendar/care_women_calendar_screen.dart',
    r'''import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/persian_date_utils.dart';

class CareWomenCalendarScreen extends StatefulWidget {
  const CareWomenCalendarScreen({
    super.key,
    required this.patientUserId,
    required this.patientName,
  });

  final String patientUserId;
  final String patientName;

  @override
  State<CareWomenCalendarScreen> createState() =>
      _CareWomenCalendarScreenState();
}

class _CareWomenCalendarScreenState extends State<CareWomenCalendarScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _summary = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await context
          .read<LifeMateApiClient>()
          .getCareRecipientWomenCalendar(
            patientUserId: widget.patientUserId,
          );
      if (mounted) setState(() => _summary = summary);
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          'women_calendar_access_denied' =>
            'دسترسی تقویم بانوان برای شما فعال نیست.',
          'women_calendar_not_active' =>
            'تقویم بانوان برای ${widget.patientName} فعال نیست.',
          'women_calendar_feature_disabled' =>
            'این قابلیت در Build فعلی فعال نیست.',
          _ => 'وضعیت تقویم بانوان دریافت نشد.',
        };
      });
    } catch (error) {
      debugPrint('Care women calendar load failed: $error');
      if (mounted) setState(() => _error = 'وضعیت تقویم بانوان دریافت نشد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recordAction(String actionType, String label) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context
          .read<LifeMateApiClient>()
          .recordCareRecipientWomenSupportAction(
            patientUserId: widget.patientUserId,
            actionType: actionType,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label ثبت شد.')),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('تقویم بانوان ${widget.patientName}'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      _EstimateCard(summary: _summary),
                      const SizedBox(height: 18),
                      _SupportActions(
                        saving: _saving,
                        onAction: _recordAction,
                      ),
                      const SizedBox(height: 18),
                      _RecentActions(summary: _summary),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5E6),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Text(
                          'این صفحه فقط خلاصه‌ای را نشان می‌دهد که صاحب حساب صریحاً اجازه داده است. یادداشت‌های خصوصی نمایش داده نمی‌شوند و زمان‌ها تخمینی‌اند. برای نگرانی پزشکی، خون‌ریزی غیرعادی یا درد شدید با پزشک تماس بگیرید.',
                          style: TextStyle(height: 1.7),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final estimate = summary['estimate'] as Map<String, dynamic>? ?? const {};
    final phase = estimate['phase']?.toString();
    final phaseLabel = switch (phase) {
      'period' => 'دوره احتمالی',
      'pre_period' => 'نزدیک دوره احتمالی',
      'post_period' => 'پس از دوره',
      'cycle' => 'میانه چرخه',
      _ => 'اطلاعات ناکافی',
    };
    final cycleDay = localizeDigits(context, estimate['cycleDay'] ?? '—');
    final next = DateTime.tryParse(
      estimate['nextPeriodStart']?.toString() ?? '',
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFEAF4), Color(0xFFF0ECFF)],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: Colors.white,
            child: Text(
              cycleDay,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Color(0xFF8B4A7B),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'وضعیت امروز',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                Text(phaseLabel),
                if (next != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    'شروع تخمینی بعدی: ${formatAppDate(context, next)}',
                    style: const TextStyle(color: AppColors.secondaryText),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportActions extends StatelessWidget {
  const _SupportActions({required this.saving, required this.onAction});
  final bool saving;
  final Future<void> Function(String, String) onAction;

  @override
  Widget build(BuildContext context) {
    const actions = <(String, String, IconData)>[
      ('hydration', 'آب و نوشیدنی آماده کردم', Icons.local_drink_rounded),
      ('rest', 'زمان استراحت فراهم کردم', Icons.bedtime_rounded),
      ('warmth', 'کیسه آب گرم آماده کردم', Icons.device_thermostat_rounded),
      ('chores', 'بخشی از کارهای خانه را انجام دادم', Icons.home_work_rounded),
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'حمایت‌های غیرپزشکی',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'فقط کارهایی را ثبت کنید که واقعاً انجام داده‌اید.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 12),
          for (final action in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: saving
                      ? null
                      : () => onAction(action.$1, action.$2),
                  icon: Icon(action.$3),
                  label: Text(action.$2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentActions extends StatelessWidget {
  const _RecentActions({required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final actions = (summary['supportActions'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final labels = <String, String>{
      'hydration': 'آب و نوشیدنی',
      'rest': 'فراهم‌کردن استراحت',
      'warmth': 'آماده‌کردن گرما',
      'chores': 'کمک در کارهای خانه',
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'حمایت‌های اخیر',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          if (actions.isEmpty)
            const Text('هنوز حمایتی ثبت نشده است.')
          else
            ...actions.take(8).map((action) {
              final performedAt = DateTime.tryParse(
                action['performedAtUtc']?.toString() ?? '',
              )?.toLocal();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.volunteer_activism_rounded),
                title: Text(
                  labels[action['actionType']?.toString()] ?? 'حمایت ثبت‌شده',
                ),
                subtitle: performedAt == null
                    ? null
                    : Text(formatAppDate(context, performedAt)),
              );
            }),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 52),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('تلاش دوباره'),
              ),
            ],
          ),
        ),
      );
}
''',
)

write(
    'caremate/test/care_recipient_reminder_test.dart',
    r'''import 'package:caremate/models/care_recipient_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects only earliest future medicine per care recipient', () {
    final now = DateTime.utc(2026, 8, 4, 10);
    final result = selectEarliestReminderPerPatient(
      [
        CareRecipientReminder(
          patientUserId: 'p1',
          patientName: 'ریحانه',
          doseId: 'late-p1',
          medicationName: 'دارو دوم',
          doseText: '۱ قرص',
          scheduledAtUtc: DateTime.utc(2026, 8, 4, 18),
        ),
        CareRecipientReminder(
          patientUserId: 'p1',
          patientName: 'ریحانه',
          doseId: 'first-p1',
          medicationName: 'دارو اول',
          doseText: '۱ قرص',
          scheduledAtUtc: DateTime.utc(2026, 8, 4, 12),
        ),
        CareRecipientReminder(
          patientUserId: 'p2',
          patientName: 'مادر',
          doseId: 'first-p2',
          medicationName: 'متفورمین',
          doseText: '۵۰۰',
          scheduledAtUtc: DateTime.utc(2026, 8, 4, 11),
        ),
        CareRecipientReminder(
          patientUserId: 'p2',
          patientName: 'مادر',
          doseId: 'past-p2',
          medicationName: 'گذشته',
          doseText: '',
          scheduledAtUtc: DateTime.utc(2026, 8, 4, 9),
        ),
      ],
      nowUtc: now,
    );

    expect(result, hasLength(2));
    expect(result[0].doseId, 'first-p2');
    expect(result[1].doseId, 'first-p1');
  });
}
''',
)

replace_once(
    'caremate/pubspec.yaml',
    "  mobile_scanner: ^7.4.0\n",
    "  mobile_scanner: ^7.4.0\n  flutter_local_notifications: ^19.5.0\n  timezone: ^0.10.1\n",
)
replace_once(
    'caremate/android/app/src/main/AndroidManifest.xml',
    '    <uses-permission android:name="android.permission.INTERNET"/>\n',
    '    <uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>\n    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n',
)

replace_once(
    'caremate/lib/main.dart',
    "import 'core/localization/locale_provider.dart';\n",
    "import 'core/localization/locale_provider.dart';\nimport 'providers/care_notification_provider.dart';\n",
)
replace_once(
    'caremate/lib/main.dart',
    '''  runApp(\n    ChangeNotifierProvider(\n      create: (_) => LocaleProvider(),\n      child: CareMateApp(\n        config: config,\n        authInitialized: authInitialized,\n      ),\n    ),\n  );\n''',
    r'''  final notificationProvider = CareNotificationProvider();
  try {
    await notificationProvider.initialize();
  } catch (error, stackTrace) {
    debugPrint('CareMate notification initialization failed: $error\n$stackTrace');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider.value(value: notificationProvider),
      ],
      child: CareMateApp(
        config: config,
        authInitialized: authInitialized,
      ),
    ),
  );
''',
)

replace_once(
    'caremate/lib/screens/dashboard_screen.dart',
    "import '../core/utils/string_extensions.dart';\n",
    "import '../core/utils/string_extensions.dart';\nimport '../models/care_recipient_reminder.dart';\nimport '../providers/care_notification_provider.dart';\n",
)
replace_once(
    'caremate/lib/screens/dashboard_screen.dart',
    "import 'profile_destination_screens.dart';\n",
    "import 'profile_destination_screens.dart';\nimport 'women_calendar/care_women_calendar_screen.dart';\n",
)
replace_once(
    'caremate/lib/screens/dashboard_screen.dart',
    '''      await _loadSelectedDoses();\n''',
    '''      await _loadSelectedDoses();\n      await _syncCareRecipientNotifications();\n''',
)
replace_once(
    'caremate/lib/screens/dashboard_screen.dart',
    '''  Map<String, dynamic>? get _selectedRelationship {\n''',
    r'''  Future<void> _syncCareRecipientNotifications() async {
    final now = DateTime.now();
    final toDate = now.add(const Duration(days: 7));
    final candidates = <CareRecipientReminder>[];
    for (final relationship in _relationships) {
      try {
        final patientUserId = relationship['patientUserId'].toString();
        final patientName =
            relationship['patientDisplayName']?.toString() ?? 'فرد تحت مراقبت';
        final doses = await context
            .read<LifeMateApiClient>()
            .getCareRecipientDoseOccurrences(
              patientUserId: patientUserId,
              fromDate: now,
              toDate: toDate,
            );
        for (final dose in doses) {
          if (dose['status']?.toString() != 'scheduled') continue;
          final scheduled = DateTime.tryParse(
            dose['scheduledAtUtc']?.toString() ?? '',
          )?.toUtc();
          if (scheduled == null || !scheduled.isAfter(DateTime.now().toUtc())) {
            continue;
          }
          candidates.add(
            CareRecipientReminder(
              patientUserId: patientUserId,
              patientName: patientName,
              doseId: dose['id'].toString(),
              medicationName:
                  dose['medicationName']?.toString() ?? 'دارو',
              doseText: dose['doseText']?.toString() ?? '',
              scheduledAtUtc: scheduled,
            ),
          );
        }
      } catch (error) {
        debugPrint('CareMate notification patient sync failed: $error');
      }
    }
    if (!mounted) return;
    final profile =
        _currentUser['profile'] as Map<String, dynamic>? ?? const {};
    final isPersian =
        context.read<LocaleProvider>().locale.languageCode == 'fa';
    try {
      await context.read<CareNotificationProvider>().syncEarliestPerRecipient(
            candidates,
            timeZone: profile['timeZone']?.toString() ?? 'Asia/Tehran',
            isPersian: isPersian,
          );
    } catch (error) {
      debugPrint('CareMate notification scheduling failed: $error');
    }
  }

  Map<String, dynamic>? get _selectedRelationship {
''',
)
replace_once(
    'caremate/lib/screens/dashboard_screen.dart',
    r'''                      const SizedBox(height: 24),
                      _SectionTitle(
                        title: 'خلاصه امروز',
''',
    r'''                      if (selected?['canViewWomenCalendar'] == true) ...[
                        const SizedBox(height: 24),
                        _WomenCalendarAccessCard(
                          patientName: patientName,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CareWomenCalendarScreen(
                                patientUserId:
                                    selected!['patientUserId'].toString(),
                                patientName: patientName,
                              ),
                            ),
                          ),
                          font: mainFont,
                        ),
                      ],
                      const SizedBox(height: 24),
                      _SectionTitle(
                        title: 'خلاصه امروز',
''',
)
replace_once(
    'caremate/lib/screens/dashboard_screen.dart',
    '''class _SectionTitle extends StatelessWidget {\n''',
    r'''class _WomenCalendarAccessCard extends StatelessWidget {
  const _WomenCalendarAccessCard({
    required this.patientName,
    required this.onTap,
    required this.font,
  });

  final String patientName;
  final VoidCallback onTap;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFEDF6), Color(0xFFF2EDFF)],
            ),
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.water_drop_rounded,
                  color: Color(0xFFD95B93),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تقویم بانوان $patientName',
                      style: font.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'مشاهده خلاصه مجاز و ثبت حمایت‌های غیرپزشکی',
                      style: font.copyWith(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
''',
)

replace_once(
    'wellmate/lib/providers/notification_provider.dart',
    "import '../models/schedule_item_model.dart';\n",
    "import '../core/utils/string_extensions.dart';\nimport '../models/schedule_item_model.dart';\n",
)
replace_once(
    'wellmate/lib/providers/notification_provider.dart',
    '''    required String timeZone,\n  }) async {\n''',
    '''    required String timeZone,\n    required bool isPersian,\n  }) async {\n''',
)
replace_once(
    'wellmate/lib/providers/notification_provider.dart',
    r'''        'زمان مصرف ${dose.title}',
        dose.dosage.isEmpty
            ? 'برای ثبت مصرف، WellMate را باز کنید.'
            : '${dose.dosage} — پس از مصرف در WellMate ثبت کنید.',
''',
    r'''        (isPersian ? 'زمان مصرف ${dose.title}' : 'Time for ${dose.title}')
            .toPersianDigit(isPersian),
        (dose.dosage.isEmpty
                ? (isPersian
                    ? 'برای ثبت مصرف، WellMate را باز کنید.'
                    : 'Open WellMate to record this dose.')
                : (isPersian
                    ? '${dose.dosage} — پس از مصرف در WellMate ثبت کنید.'
                    : '${dose.dosage} — record it in WellMate after taking it.'))
            .toPersianDigit(isPersian),
''',
)

replace_once(
    'wellmate/lib/screens/home/home_screen_content.dart',
    '''      final medicineToday = todayItems\n          .where((item) => item.type == 'medicine')\n          .toList(growable: false);\n      context.read<MedicationProvider>().setMedications(medicineToday);\n      try {\n        await context.read<NotificationProvider>().syncDoseReminders(\n          medicineToday,\n          timeZone: profile['timeZone']?.toString() ?? 'Asia/Tehran',\n        );\n''',
    r'''      final medicineToday = todayItems
          .where((item) => item.type == 'medicine')
          .toList(growable: false);
      final medicineReminderWindow = allItems
          .where(
            (item) =>
                item.type == 'medicine' &&
                item.status == 'scheduled' &&
                item.scheduledAtUtc?.isAfter(DateTime.now().toUtc()) == true,
          )
          .toList(growable: false);
      context.read<MedicationProvider>().setMedications(medicineToday);
      try {
        await context.read<NotificationProvider>().syncDoseReminders(
          medicineReminderWindow,
          timeZone: profile['timeZone']?.toString() ?? 'Asia/Tehran',
          isPersian:
              Localizations.localeOf(context).languageCode == 'fa',
        );
''',
)

replace_once(
    'wellmate/pubspec.yaml',
    'version: 0.9.0-internal.3+14',
    'version: 0.9.0-internal.4+15',
)
replace_once(
    'caremate/pubspec.yaml',
    'version: 0.9.0-internal.3+14',
    'version: 0.9.0-internal.4+15',
)
replace_once(
    'wellmate/lib/core/constants/app_version.dart',
    "const String wellMateAppVersion = '0.9.0-internal.3+14';",
    "const String wellMateAppVersion = '0.9.0-internal.4+15';",
)
replace_once(
    'caremate/lib/core/constants/app_version.dart',
    "const String careMateAppVersion = '0.9.0-internal.3+14';",
    "const String careMateAppVersion = '0.9.0-internal.4+15';",
)

print('CareMate women summary and local medication notification patch applied.')
