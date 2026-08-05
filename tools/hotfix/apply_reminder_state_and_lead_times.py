from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, value: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(value, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    value = read(path)
    if new in value:
        return
    if old not in value:
        raise RuntimeError(f"Expected marker not found in {path}: {old[:120]!r}")
    write(path, value.replace(old, new, 1))


# Shared reminder presets used by both apps.
write(
    "packages/lifemate_client/lib/src/reminder_lead_time.dart",
    """abstract final class LifeMateReminderLeadTimes {
  static const int minimumMinutes = 0;
  static const int maximumMinutes = 10080;
  static const int defaultPatientMinutes = 30;
  static const int defaultCaregiverMinutes = 60;

  static const List<int> presets = <int>[
    0,
    5,
    10,
    15,
    30,
    60,
    120,
    1440,
  ];

  static int normalize(
    Object? value, {
    required int fallback,
  }) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed < minimumMinutes || parsed > maximumMinutes) {
      return fallback;
    }
    return parsed;
  }

  static String label(int minutes) {
    if (minutes <= 0) return 'در زمان برنامه';
    if (minutes < 60) return '$minutes دقیقه قبل';
    if (minutes == 60) return '۱ ساعت قبل';
    if (minutes < 1440 && minutes % 60 == 0) {
      return '${minutes ~/ 60} ساعت قبل';
    }
    if (minutes == 1440) return '۱ روز قبل';
    if (minutes % 1440 == 0) return '${minutes ~/ 1440} روز قبل';
    return '$minutes دقیقه قبل';
  }
}
""",
)
replace_once(
    "packages/lifemate_client/lib/lifemate_client.dart",
    "export 'src/profile_avatar.dart';\n",
    "export 'src/profile_avatar.dart';\nexport 'src/reminder_lead_time.dart';\n",
)

# API payloads now carry patient/caregiver reminder lead times.
replace_once(
    "packages/lifemate_client/lib/src/lifemate_api_client.dart",
    "import 'package:http/http.dart' as http;\n",
    "import 'package:http/http.dart' as http;\n\nimport 'reminder_lead_time.dart';\n",
)
replace_once(
    "packages/lifemate_client/lib/src/lifemate_api_client.dart",
    """    required List<Map<String, String>> schedules,
    String? instructions,
  }) async => _asObject(""",
    """    required List<Map<String, String>> schedules,
    String? instructions,
    int patientReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultPatientMinutes,
    int caregiverReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultCaregiverMinutes,
  }) async => _asObject(""",
)
replace_once(
    "packages/lifemate_client/lib/src/lifemate_api_client.dart",
    """        'timeZone': timeZone,
        'schedules': schedules,
      },""",
    """        'timeZone': timeZone,
        'schedules': schedules,
        'patientReminderMinutesBefore': patientReminderMinutesBefore,
        'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
      },""",
)
replace_once(
    "packages/lifemate_client/lib/src/lifemate_api_client.dart",
    """    String? addressLine,
    String? phoneNumber,
  }) async => _asObject(""",
    """    String? addressLine,
    String? phoneNumber,
    int patientReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultPatientMinutes,
    int caregiverReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultCaregiverMinutes,
  }) async => _asObject(""",
)
replace_once(
    "packages/lifemate_client/lib/src/lifemate_api_client.dart",
    """        'scheduledLocalTime': scheduledLocalTime.trim(),
        'timeZone': timeZone.trim(),
      },""",
    """        'scheduledLocalTime': scheduledLocalTime.trim(),
        'timeZone': timeZone.trim(),
        'patientReminderMinutesBefore': patientReminderMinutesBefore,
        'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
      },""",
)

# Schedule view model carries the reminder policy end-to-end.
path = "wellmate/lib/models/schedule_item_model.dart"
value = read(path)
if "patientReminderMinutesBefore" not in value:
    value = value.replace(
        "  final int? intervalDays;\n",
        "  final int? intervalDays;\n  final int patientReminderMinutesBefore;\n  final int caregiverReminderMinutesBefore;\n",
    )
    value = value.replace(
        "    this.intervalDays,\n    required this.frequency,\n",
        "    this.intervalDays,\n    this.patientReminderMinutesBefore = 30,\n    this.caregiverReminderMinutesBefore = 60,\n    required this.frequency,\n",
    )
    value = value.replace(
        "      intervalDays: json['intervalDays'],\n",
        "      intervalDays: json['intervalDays'],\n      patientReminderMinutesBefore: int.tryParse(\n            json['patientReminderMinutesBefore']?.toString() ?? '',\n          ) ??\n          30,\n      caregiverReminderMinutesBefore: int.tryParse(\n            json['caregiverReminderMinutesBefore']?.toString() ?? '',\n          ) ??\n          60,\n",
    )
    value = value.replace(
        "      'intervalDays': intervalDays,\n",
        "      'intervalDays': intervalDays,\n      'patientReminderMinutesBefore': patientReminderMinutesBefore,\n      'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,\n",
    )
    value = value.replace(
        "    int? intervalDays,\n  }) {\n",
        "    int? intervalDays,\n    int? patientReminderMinutesBefore,\n    int? caregiverReminderMinutesBefore,\n  }) {\n",
    )
    value = value.replace(
        "      intervalDays: intervalDays ?? this.intervalDays,\n",
        "      intervalDays: intervalDays ?? this.intervalDays,\n      patientReminderMinutesBefore:\n          patientReminderMinutesBefore ?? this.patientReminderMinutesBefore,\n      caregiverReminderMinutesBefore:\n          caregiverReminderMinutesBefore ?? this.caregiverReminderMinutesBefore,\n",
    )
    write(path, value)

# Notification scheduling is based on the selected lead time and supports all care items.
write(
    "wellmate/lib/providers/notification_provider.dart",
    """import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/utils/string_extensions.dart';
import '../models/schedule_item_model.dart';

class NotificationProvider extends ChangeNotifier {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _hasUnread = false;
  bool _initialized = false;
  bool _permissionRequested = false;

  bool get hasUnread => _hasUnread;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (_) => setUnread(true),
    );
    _initialized = true;
  }

  Future<void> syncReminders(
    List<ScheduleItemModel> items, {
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
      final android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
      _permissionRequested = true;
    }

    final pending = await _notifications.pendingNotificationRequests();
    for (final request in pending) {
      if (request.payload?.startsWith('lifemate-reminder:') == true ||
          request.payload?.startsWith('dose:') == true) {
        await _notifications.cancel(request.id);
      }
    }

    final nowUtc = DateTime.now().toUtc();
    for (final item in items) {
      final scheduledUtc = _scheduledUtc(item);
      if (scheduledUtc == null ||
          !scheduledUtc.isAfter(nowUtc) ||
          item.status != 'scheduled') {
        continue;
      }
      final triggerUtc = scheduledUtc.subtract(
        Duration(minutes: item.patientReminderMinutesBefore),
      );
      if (!triggerUtc.isAfter(nowUtc)) continue;

      final notificationId = _notificationId('${item.type}:${item.id}');
      await _notifications.cancel(notificationId);
      final title = _title(item, isPersian);
      final detail = _detail(item, isPersian);
      await _notifications.zonedSchedule(
        notificationId,
        title.toPersianDigit(isPersian),
        detail.toPersianDigit(isPersian),
        tz.TZDateTime.from(triggerUtc, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'wellmate_treatment_reminders',
            'یادآور برنامه درمان و مراقبت',
            channelDescription: 'یادآورهای دارو، ویزیت و تزریق WellMate',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.private,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'lifemate-reminder:${item.type}:${item.id}',
      );
    }
  }

  DateTime? _scheduledUtc(ScheduleItemModel item) {
    if (item.scheduledAtUtc != null) return item.scheduledAtUtc!.toUtc();
    final date = item.startDate;
    final parts = item.time.split(':');
    if (date == null || parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1].split(' ').first);
    if (hour == null || minute == null) return null;
    return tz.TZDateTime(tz.local, date.year, date.month, date.day, hour, minute)
        .toUtc();
  }

  static String _title(ScheduleItemModel item, bool persian) {
    if (!persian) {
      return switch (item.type) {
        'appointment' => 'Upcoming appointment',
        'injection' => 'Upcoming injection',
        _ => 'Time for ${item.title}',
      };
    }
    return switch (item.type) {
      'appointment' => 'یادآوری ویزیت ${item.title}',
      'injection' => 'یادآوری تزریق ${item.title}',
      _ => 'زمان مصرف ${item.title}',
    };
  }

  static String _detail(ScheduleItemModel item, bool persian) {
    final lead = item.patientReminderMinutesBefore;
    final leadText = lead <= 0
        ? (persian ? 'اکنون' : 'now')
        : (persian ? '$lead دقیقه پیش از برنامه' : '$lead minutes before');
    final detail = item.dosage.trim();
    if (detail.isEmpty) return leadText;
    return '$detail — $leadText';
  }

  static int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  void setUnread(bool value) {
    _hasUnread = value;
    notifyListeners();
  }
}
""",
)

# CareMate chooses the earliest trigger (not merely the earliest treatment time).
write(
    "caremate/lib/models/care_recipient_reminder.dart",
    """class CareRecipientReminder {
  const CareRecipientReminder({
    required this.patientUserId,
    required this.patientName,
    required this.doseId,
    required this.medicationName,
    required this.doseText,
    required this.scheduledAtUtc,
    this.reminderMinutesBefore = 60,
    this.kind = 'medicine',
  });

  final String patientUserId;
  final String patientName;
  final String doseId;
  final String medicationName;
  final String doseText;
  final DateTime scheduledAtUtc;
  final int reminderMinutesBefore;
  final String kind;

  DateTime get triggerAtUtc => scheduledAtUtc.toUtc().subtract(
        Duration(minutes: reminderMinutesBefore),
      );
}

List<CareRecipientReminder> selectEarliestReminderPerPatient(
  Iterable<CareRecipientReminder> reminders, {
  DateTime? nowUtc,
}) {
  final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
  final selected = <String, CareRecipientReminder>{};
  for (final reminder in reminders) {
    if (!reminder.scheduledAtUtc.toUtc().isAfter(now) ||
        !reminder.triggerAtUtc.isAfter(now)) {
      continue;
    }
    final existing = selected[reminder.patientUserId];
    if (existing == null || _compareReminder(reminder, existing) < 0) {
      selected[reminder.patientUserId] = reminder;
    }
  }
  final result = selected.values.toList(growable: false)
    ..sort(_compareReminder);
  return result;
}

int _compareReminder(CareRecipientReminder left, CareRecipientReminder right) {
  final byTrigger = left.triggerAtUtc.compareTo(right.triggerAtUtc);
  if (byTrigger != 0) return byTrigger;
  final byTime = left.scheduledAtUtc.toUtc().compareTo(
        right.scheduledAtUtc.toUtc(),
      );
  if (byTime != 0) return byTime;
  final byPatient = left.patientUserId.compareTo(right.patientUserId);
  if (byPatient != 0) return byPatient;
  return left.doseId.compareTo(right.doseId);
}
""",
)
write(
    "caremate/lib/providers/care_notification_provider.dart",
    """import 'package:flutter/foundation.dart';
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
      final android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
      _permissionRequested = true;
    }

    final pending = await _notifications.pendingNotificationRequests();
    for (final request in pending) {
      if (request.payload?.startsWith('care-reminder:') == true ||
          request.payload?.startsWith('care-dose:') == true) {
        await _notifications.cancel(request.id);
      }
    }
    final reminders = selectEarliestReminderPerPatient(candidates);
    for (final reminder in reminders) {
      final localTime = tz.TZDateTime.from(reminder.scheduledAtUtc, tz.local);
      final triggerTime = tz.TZDateTime.from(reminder.triggerAtUtc, tz.local);
      final timeText =
          '${localTime.hour.toString().padLeft(2, '0')}:'
                  '${localTime.minute.toString().padLeft(2, '0')}'
              .toPersianDigit(isPersian);
      final title = isPersian
          ? '${_kindTitle(reminder.kind)} ${reminder.patientName.toPersianDigit(true)}'
          : '${reminder.patientName} upcoming ${reminder.kind}';
      final detail = [
        reminder.medicationName,
        if (reminder.doseText.trim().isNotEmpty) reminder.doseText.trim(),
        timeText,
      ].join(' • ').toPersianDigit(isPersian);

      await _notifications.zonedSchedule(
        _notificationId(reminder.patientUserId),
        title,
        detail,
        triggerTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'caremate_next_treatment',
            'برنامه بعدی افراد تحت مراقبت',
            channelDescription:
                'نزدیک‌ترین یادآور دارو، ویزیت یا تزریق هر فرد در CareMate',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.private,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload:
            'care-reminder:${reminder.patientUserId}:${reminder.kind}:${reminder.doseId}',
      );
    }
  }

  static String _kindTitle(String kind) => switch (kind) {
        'appointment' => 'ویزیت بعدی',
        'injection' => 'تزریق بعدی',
        _ => 'داروی بعدی',
      };

  static int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in 'care:$value'.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
""",
)

# Bell action reports to the real API through HomeScreen instead of changing local state only.
replace_once(
    "wellmate/lib/core/widgets/wellmate_app_header.dart",
    "class WellMateAppHeader extends StatelessWidget {\n",
    "typedef MissedMedicationReporter = Future<bool> Function(\n  ScheduleItemModel item,\n);\n\nclass WellMateAppHeader extends StatelessWidget {\n",
)
replace_once(
    "wellmate/lib/core/widgets/wellmate_app_header.dart",
    "  final VoidCallback? onNotificationTap;\n",
    "  final VoidCallback? onNotificationTap;\n  final MissedMedicationReporter? onMissedMedicationTaken;\n",
)
replace_once(
    "wellmate/lib/core/widgets/wellmate_app_header.dart",
    """    required this.onProfileTap,
    this.onNotificationTap,
  }) : super(key: key);""",
    """    required this.onProfileTap,
    this.onNotificationTap,
    this.onMissedMedicationTaken,
  }) : super(key: key);""",
)
replace_once(
    "wellmate/lib/core/widgets/wellmate_app_header.dart",
    """            onTap: () {
              context.read<MedicationProvider>().markAsDone(item.id);
            },""",
    """            onTap: () async {
              final reporter = onMissedMedicationTaken;
              if (reporter == null) return;
              final success = await reporter(item);
              if (success && context.mounted) {
                context.read<MedicationProvider>().markAsDone(item.id);
              }
            },""",
)

replace_once(
    "wellmate/lib/screens/home/home_screen.dart",
    "import '../calendar/calendar_screen.dart';\n",
    "import '../../models/schedule_item_model.dart';\nimport '../calendar/calendar_screen.dart';\n",
)
replace_once(
    "wellmate/lib/screens/home/home_screen.dart",
    """  void _treatmentCreated() {
    setState(() {
      _refreshToken++;
      _currentIndex = 4;
    });
  }
""",
    """  void _treatmentCreated() {
    setState(() {
      _refreshToken++;
      _currentIndex = 4;
    });
  }

  Future<bool> _reportMissedDoseFromHeader(ScheduleItemModel item) async {
    try {
      await context.read<LifeMateApiClient>().reportDose(
        occurrenceId: item.id,
        clientRequestId: LifeMateApiClient.createClientRequestId(),
        version: item.version,
        status: 'taken',
        occurredAtUtc: DateTime.now().toUtc(),
      );
      if (!mounted) return true;
      setState(() => _refreshToken++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.title} به عنوان مصرف‌شده ثبت شد.')),
      );
      return true;
    } on LifeMateApiException catch (error) {
      if (!mounted) return false;
      final message = error.code == 'stale_dose_occurrence'
          ? 'وضعیت دارو تغییر کرده است؛ برنامه تازه‌سازی شد.'
          : 'ثبت مصرف انجام نشد؛ دوباره تلاش کنید.';
      setState(() => _refreshToken++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return false;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ثبت مصرف انجام نشد؛ اتصال را بررسی کنید.')),
        );
      }
      return false;
    }
  }
""",
)
replace_once(
    "wellmate/lib/screens/home/home_screen.dart",
    """            WellMateAppHeader(
              onProfileTap: () async {""",
    """            WellMateAppHeader(
              onMissedMedicationTaken: _reportMissedDoseFromHeader,
              onProfileTap: () async {""",
)

# Home timeline: generic overdue state, real care-event fallback, and reminder policy.
path = "wellmate/lib/screens/home/home_screen_content.dart"
value = read(path)
if "patientReminderMinutesBefore:" not in value:
    value = value.replace(
        """            intervalDays: 1,
          );
        }),
        ...careEvents.map((event) {""",
        """            intervalDays: 1,
            patientReminderMinutesBefore:
                LifeMateReminderLeadTimes.normalize(
                  dose['patientReminderMinutesBefore'],
                  fallback: LifeMateReminderLeadTimes.defaultPatientMinutes,
                ),
            caregiverReminderMinutesBefore:
                LifeMateReminderLeadTimes.normalize(
                  dose['caregiverReminderMinutesBefore'],
                  fallback: LifeMateReminderLeadTimes.defaultCaregiverMinutes,
                ),
          );
        }),
        ...careEvents.map((event) {""",
    )
    value = value.replace(
        """          final status =
              event['status']?.toString().toLowerCase() ?? 'scheduled';
          final details = <String>[""",
        """          final rawStatus =
              event['status']?.toString().toLowerCase() ?? 'scheduled';
          final status = rawStatus == 'scheduled' && _isPastCareEvent(event)
              ? 'missed'
              : rawStatus;
          final details = <String>[""",
    )
    value = value.replace(
        """            startDate: DateTime.tryParse(
              event['scheduledLocalDate']?.toString() ?? '',
            ),
            intervalDays: 1,
          );""",
        """            startDate: DateTime.tryParse(
              event['scheduledLocalDate']?.toString() ?? '',
            ),
            intervalDays: 1,
            patientReminderMinutesBefore:
                LifeMateReminderLeadTimes.normalize(
                  event['patientReminderMinutesBefore'],
                  fallback: LifeMateReminderLeadTimes.defaultPatientMinutes,
                ),
            caregiverReminderMinutesBefore:
                LifeMateReminderLeadTimes.normalize(
                  event['caregiverReminderMinutesBefore'],
                  fallback: LifeMateReminderLeadTimes.defaultCaregiverMinutes,
                ),
          );""",
        1,
    )
    value = value.replace(
        """      final missedMedicine = actionable.where(
        (item) => item.type == 'medicine' && item.status == 'missed',
      );
      final nextOccurrence = future.isNotEmpty
          ? future.first
          : (missedMedicine.isNotEmpty ? missedMedicine.first : null);""",
        """      final missedOccurrences = actionable
          .where((item) => item.status == 'missed')
          .toList(growable: false)
        ..sort(_compareOccurrence);
      final nextOccurrence = future.isNotEmpty
          ? future.first
          : (missedOccurrences.isNotEmpty ? missedOccurrences.first : null);""",
    )
    value = value.replace(
        """      final medicineReminderWindow = allItems
          .where(
            (item) =>
                item.type == 'medicine' &&
                item.status == 'scheduled' &&
                item.scheduledAtUtc?.isAfter(DateTime.now().toUtc()) == true,
          )
          .toList(growable: false);""",
        """      final reminderWindow = allItems
          .where((item) {
            if (item.status != 'scheduled') return false;
            final scheduled = _scheduledDateTime(item);
            return scheduled != null && scheduled.isAfter(DateTime.now());
          })
          .toList(growable: false);""",
    )
    value = value.replace(
        """        await context.read<NotificationProvider>().syncDoseReminders(
          medicineReminderWindow,""",
        """        await context.read<NotificationProvider>().syncReminders(
          reminderWindow,""",
    )
    value = value.replace(
        """                                  final missed =
                                      item.type == 'medicine' &&
                                      item.status == 'missed';""",
        """                                  final missed = item.status == 'missed';""",
    )
    value = value.replace(
        """                  : _UpcomingCareEventCard(
                      item: nextItem,
                      secondsLeft: _calculateSecondsLeft(nextItem),""",
        """                  : _UpcomingCareEventCard(
                      item: nextItem,
                      isMissed: nextItem.status == 'missed',
                      secondsLeft: _calculateSecondsLeft(nextItem),""",
    )
    value = value.replace(
        """  static String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
""",
        """  static String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static bool _isPastCareEvent(Map<String, dynamic> event) {
    final date = DateTime.tryParse(
      event['scheduledLocalDate']?.toString() ?? '',
    );
    final parts = event['scheduledLocalTime']?.toString().split(':') ?? const [];
    if (date == null || parts.length < 2) return false;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return false;
    return DateTime(date.year, date.month, date.day, hour, minute)
        .isBefore(DateTime.now());
  }
""",
    )
    value = value.replace(
        """    required this.item,
    required this.secondsLeft,""",
        """    required this.item,
    required this.isMissed,
    required this.secondsLeft,""",
    )
    value = value.replace(
        """  final ScheduleItemModel item;
  final int secondsLeft;""",
        """  final ScheduleItemModel item;
  final bool isMissed;
  final int secondsLeft;""",
    )
    value = value.replace(
        """        color: Colors.white,
        borderRadius: BorderRadius.circular(28),""",
        """        color: isMissed ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: isMissed ? Border.all(color: Colors.red.shade200) : null,""",
        1,
    )
    value = value.replace(
        """                Text(
                  '${item.time} • ${_countdown(persian)}'.toPersianDigit(
                    persian,
                  ),""",
        """                Text(
                  (isMissed
                          ? '${item.time} • زمان برنامه گذشته است'
                          : '${item.time} • ${_countdown(persian)}')
                      .toPersianDigit(persian),""",
    )
    write(path, value)

# Calendar missed styling applies to appointments and injections as well.
path = "wellmate/lib/screens/calendar/calendar_screen.dart"
value = read(path)
if "final isMissed = item.status == 'missed'" not in value:
    value = value.replace(
        """      if (item.type == 'medicine' &&
          (item.status == 'missed' ||
              (!item.isDone && _isTimePassed(item.time, day)))) {
        types.add('missed');
      }""",
        """      if (item.status == 'missed' ||
          (!item.isDone && _isTimePassed(item.time, day))) {
        types.add('missed');
      }""",
    )
    value = value.replace(
        """    final isMedicine = item.type == 'medicine';
    final isMissed =
        isMedicine &&
        (item.status == 'missed' ||
            (!item.isDone && _isTimePassed(item.time, _selectedDate)));""",
        """    final isMedicine = item.type == 'medicine';
    final isMissed = item.status == 'missed' ||
        (!item.isDone && _isTimePassed(item.time, _selectedDate));""",
    )
    value = value.replace(
        """    final status = event['status']?.toString().toLowerCase() ?? 'scheduled';
    final details = <String>[""",
        """    final rawStatus =
        event['status']?.toString().toLowerCase() ?? 'scheduled';
    final status = rawStatus == 'scheduled' && _isTimePassed(
          rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
          date,
        )
        ? 'missed'
        : rawStatus;
    final details = <String>[""",
    )
    value = value.replace(
        """      intervalDays: 1,
    );
  }

  static String? _nonEmpty""",
        """      intervalDays: 1,
      patientReminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
        event['patientReminderMinutesBefore'],
        fallback: LifeMateReminderLeadTimes.defaultPatientMinutes,
      ),
      caregiverReminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
        event['caregiverReminderMinutesBefore'],
        fallback: LifeMateReminderLeadTimes.defaultCaregiverMinutes,
      ),
    );
  }

  static String? _nonEmpty""",
    )
    value = value.replace(
        """      intervalDays: 1,
    );
  }

  ScheduleItemModel _scheduleItemFromCareEvent""",
        """      intervalDays: 1,
      patientReminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
        dose['patientReminderMinutesBefore'],
        fallback: LifeMateReminderLeadTimes.defaultPatientMinutes,
      ),
      caregiverReminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
        dose['caregiverReminderMinutesBefore'],
        fallback: LifeMateReminderLeadTimes.defaultCaregiverMinutes,
      ),
    );
  }

  ScheduleItemModel _scheduleItemFromCareEvent""",
    )
    write(path, value)

# Forms expose independent patient and caregiver lead times.
path = "wellmate/lib/screens/treatments/add_treatment_screen.dart"
value = read(path)
if "_patientReminderMinutesBefore" not in value:
    value = value.replace(
        "  String _frequency = 'daily';\n",
        "  String _frequency = 'daily';\n  int _patientReminderMinutesBefore =\n      LifeMateReminderLeadTimes.defaultPatientMinutes;\n  int _caregiverReminderMinutesBefore =\n      LifeMateReminderLeadTimes.defaultCaregiverMinutes;\n",
    )
    value = value.replace(
        """        schedules: schedules,
      );""",
        """        schedules: schedules,
        patientReminderMinutesBefore: _patientReminderMinutesBefore,
        caregiverReminderMinutesBefore: _caregiverReminderMinutesBefore,
      );""",
    )
    value = value.replace(
        """      _frequency = 'daily';
      _selectedWeekdays""",
        """      _frequency = 'daily';
      _patientReminderMinutesBefore =
          LifeMateReminderLeadTimes.defaultPatientMinutes;
      _caregiverReminderMinutesBefore =
          LifeMateReminderLeadTimes.defaultCaregiverMinutes;
      _selectedWeekdays""",
    )
    value = value.replace(
        """              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _timeZone,""",
        """              const SizedBox(height: 16),
              const Text(
                'زمان یادآوری',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                key: const ValueKey('patient-reminder-lead'),
                initialValue: _patientReminderMinutesBefore,
                isExpanded: true,
                decoration: _decoration(
                  label: 'یادآوری برای خودم',
                  icon: Icons.notifications_active_rounded,
                ),
                items: [
                  for (final minutes in LifeMateReminderLeadTimes.presets)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(LifeMateReminderLeadTimes.label(minutes)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                          _patientReminderMinutesBefore = value ??
                              _patientReminderMinutesBefore;
                        }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: const ValueKey('caregiver-reminder-lead'),
                initialValue: _caregiverReminderMinutesBefore,
                isExpanded: true,
                decoration: _decoration(
                  label: 'یادآوری برای مراقب',
                  icon: Icons.family_restroom_rounded,
                ),
                items: [
                  for (final minutes in LifeMateReminderLeadTimes.presets)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(LifeMateReminderLeadTimes.label(minutes)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                          _caregiverReminderMinutesBefore = value ??
                              _caregiverReminderMinutesBefore;
                        }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _timeZone,""",
    )
    write(path, value)

path = "wellmate/lib/screens/treatments/care_plan_hub_screen.dart"
value = read(path)
if "_patientReminderMinutesBefore" not in value:
    value = value.replace(
        "  String _administrationRoute = 'intramuscular';\n",
        "  String _administrationRoute = 'intramuscular';\n  int _patientReminderMinutesBefore =\n      LifeMateReminderLeadTimes.defaultPatientMinutes;\n  int _caregiverReminderMinutesBefore =\n      LifeMateReminderLeadTimes.defaultCaregiverMinutes;\n",
    )
    value = value.replace(
        """        scheduledLocalTime: _timeValue,
        timeZone: _timeZone,
      );""",
        """        scheduledLocalTime: _timeValue,
        timeZone: _timeZone,
        patientReminderMinutesBefore: _patientReminderMinutesBefore,
        caregiverReminderMinutesBefore: _caregiverReminderMinutesBefore,
      );""",
    )
    value = value.replace(
        """      _administrationRoute = 'intramuscular';
      _clientRequestId""",
        """      _administrationRoute = 'intramuscular';
      _patientReminderMinutesBefore =
          LifeMateReminderLeadTimes.defaultPatientMinutes;
      _caregiverReminderMinutesBefore =
          LifeMateReminderLeadTimes.defaultCaregiverMinutes;
      _clientRequestId""",
    )
    value = value.replace(
        """              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('care-event-timezone'),""",
        """              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                key: const ValueKey('care-event-patient-reminder-lead'),
                initialValue: _patientReminderMinutesBefore,
                isExpanded: true,
                decoration: _decoration(
                  label: 'یادآوری برای خودم',
                  icon: Icons.notifications_active_rounded,
                ),
                items: [
                  for (final minutes in LifeMateReminderLeadTimes.presets)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(LifeMateReminderLeadTimes.label(minutes)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                          _patientReminderMinutesBefore = value ??
                              _patientReminderMinutesBefore;
                        }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: const ValueKey('care-event-caregiver-reminder-lead'),
                initialValue: _caregiverReminderMinutesBefore,
                isExpanded: true,
                decoration: _decoration(
                  label: 'یادآوری برای مراقب',
                  icon: Icons.family_restroom_rounded,
                ),
                items: [
                  for (final minutes in LifeMateReminderLeadTimes.presets)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(LifeMateReminderLeadTimes.label(minutes)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                          _caregiverReminderMinutesBefore = value ??
                              _caregiverReminderMinutesBefore;
                        }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('care-event-timezone'),""",
    )
    write(path, value)

# CareMate includes future appointments/injections in the same earliest reminder selection.
path = "caremate/lib/screens/dashboard_screen.dart"
value = read(path)
if "caregiverReminderMinutesBefore" not in value:
    value = value.replace(
        """              scheduledAtUtc: scheduled,
            ),""",
        """              scheduledAtUtc: scheduled,
              reminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
                dose['caregiverReminderMinutesBefore'],
                fallback: LifeMateReminderLeadTimes.defaultCaregiverMinutes,
              ),
            ),""",
    )
    value = value.replace(
        """        for (final dose in doses) {
          if (dose['status']?.toString() != 'scheduled') continue;""",
        """        for (final dose in doses) {
          if (dose['status']?.toString() != 'scheduled') continue;""",
    )
    marker = """        }
      } catch (_) {
        debugPrint('CareMate notification patient sync failed.');
      }
"""
    replacement = """        }
        final careEvents = await context
            .read<LifeMateApiClient>()
            .getCareRecipientCareEvents(
              patientUserId: patientUserId,
              fromDate: now,
              toDate: toDate,
            );
        for (final event in careEvents) {
          if (event['status']?.toString() != 'scheduled') continue;
          final scheduled = DateTime.tryParse(
            event['scheduledAtUtc']?.toString() ?? '',
          )?.toUtc();
          if (scheduled == null || !scheduled.isAfter(DateTime.now().toUtc())) {
            continue;
          }
          final kind = event['eventType']?.toString().toLowerCase() == 'injection'
              ? 'injection'
              : 'appointment';
          candidates.add(
            CareRecipientReminder(
              patientUserId: patientUserId,
              patientName: patientName,
              doseId: event['id'].toString(),
              medicationName: event['title']?.toString() ??
                  (kind == 'injection' ? 'تزریق' : 'ویزیت'),
              doseText: event['centerName']?.toString() ?? '',
              scheduledAtUtc: scheduled,
              reminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
                event['caregiverReminderMinutesBefore'],
                fallback: LifeMateReminderLeadTimes.defaultCaregiverMinutes,
              ),
              kind: kind,
            ),
          );
        }
      } catch (_) {
        debugPrint('CareMate notification patient sync failed.');
      }
"""
    if marker not in value:
        raise RuntimeError("CareMate notification loop marker missing")
    value = value.replace(marker, replacement, 1)
    write(path, value)

# Database migration.
write(
    "supabase/migrations/20260805013000_add_reminder_lead_times.sql",
    """begin;

alter table lifemate.treatment_plans
  add column if not exists patient_reminder_minutes_before integer not null default 30,
  add column if not exists caregiver_reminder_minutes_before integer not null default 60;

alter table lifemate.care_events
  add column if not exists patient_reminder_minutes_before integer not null default 30,
  add column if not exists caregiver_reminder_minutes_before integer not null default 60;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'ck_treatment_plans_patient_reminder_lead'
      and conrelid = 'lifemate.treatment_plans'::regclass
  ) then
    alter table lifemate.treatment_plans
      add constraint ck_treatment_plans_patient_reminder_lead
      check (patient_reminder_minutes_before between 0 and 10080);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'ck_treatment_plans_caregiver_reminder_lead'
      and conrelid = 'lifemate.treatment_plans'::regclass
  ) then
    alter table lifemate.treatment_plans
      add constraint ck_treatment_plans_caregiver_reminder_lead
      check (caregiver_reminder_minutes_before between 0 and 10080);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'ck_care_events_patient_reminder_lead'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      add constraint ck_care_events_patient_reminder_lead
      check (patient_reminder_minutes_before between 0 and 10080);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'ck_care_events_caregiver_reminder_lead'
      and conrelid = 'lifemate.care_events'::regclass
  ) then
    alter table lifemate.care_events
      add constraint ck_care_events_caregiver_reminder_lead
      check (caregiver_reminder_minutes_before between 0 and 10080);
  end if;
end $$;

commit;
""",
)

# Edge treatment persistence and DTO mapping.
path = "supabase/functions/lifemate-api/database.ts"
value = read(path)
if "patient_reminder_minutes_before" not in value:
    value = value.replace(
        """    const schedules = normalizeSchedules(body.schedules);
    const now = new Date();""",
        """    const schedules = normalizeSchedules(body.schedules);
    const patientReminderMinutesBefore = reminderMinutes(
      body.patientReminderMinutesBefore,
      'patientReminderMinutesBefore',
      30,
    );
    const caregiverReminderMinutesBefore = reminderMinutes(
      body.caregiverReminderMinutesBefore,
      'caregiverReminderMinutesBefore',
      60,
    );
    const now = new Date();""",
    )
    value = value.replace(
        """           start_date, end_date, time_zone, status, version,
           created_at_utc, updated_at_utc)""",
        """           start_date, end_date, time_zone,
           patient_reminder_minutes_before,
           caregiver_reminder_minutes_before,
           status, version, created_at_utc, updated_at_utc)""",
    )
    value = value.replace(
        """           ${startDate}, ${endDate}, ${timeZone}, 'Active', 1, ${now}, ${now})""",
        """           ${startDate}, ${endDate}, ${timeZone},
           ${patientReminderMinutesBefore}, ${caregiverReminderMinutesBefore},
           'Active', 1, ${now}, ${now})""",
    )
    value = value.replace(
        """    const rows = await sql`
      select *
      from lifemate.dose_occurrences""",
        """    const rows = await sql`
      select o.*, p.patient_reminder_minutes_before,
             p.caregiver_reminder_minutes_before
      from lifemate.dose_occurrences o
      join lifemate.treatment_plans p on p.id = o.treatment_plan_id""",
    )
    value = value.replace(
        """      where patient_user_id = ${patientUserId}
        and scheduled_local_date""",
        """      where o.patient_user_id = ${patientUserId}
        and o.scheduled_local_date""",
        1,
    )
    value = value.replace(
        """      order by scheduled_at_utc, id
    `;""",
        """      order by o.scheduled_at_utc, o.id
    `;""",
        1,
    )
    value = value.replace(
        """      select o.*, m.name as medication_name, p.dose_text""",
        """      select o.*, m.name as medication_name, p.dose_text,
             p.patient_reminder_minutes_before,
             p.caregiver_reminder_minutes_before""",
    )
    value = value.replace(
        """    status: String(row.status).toLowerCase(),
    version: row.version,""",
        """    status: String(row.status).toLowerCase(),
    patientReminderMinutesBefore:
      Number(row.patient_reminder_minutes_before ?? 30),
    caregiverReminderMinutesBefore:
      Number(row.caregiver_reminder_minutes_before ?? 60),
    version: row.version,""",
        1,
    )
    value = value.replace(
        """    respondedAtUtc: row.responded_at_utc == null
      ? null
      : iso(row.responded_at_utc),
    version: row.version,""",
        """    respondedAtUtc: row.responded_at_utc == null
      ? null
      : iso(row.responded_at_utc),
    patientReminderMinutesBefore:
      Number(row.patient_reminder_minutes_before ?? 30),
    caregiverReminderMinutesBefore:
      Number(row.caregiver_reminder_minutes_before ?? 60),
    version: row.version,""",
    )
    value = value.replace(
        """function mapCurrentUser(user: Row, profile: Row): Record<string, unknown> {""",
        """function reminderMinutes(
  value: unknown,
  field: string,
  fallback: number,
): number {
  if (value == null || value === '') return fallback;
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0 || number > 10080) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} must be an integer between 0 and 10080.`,
    );
  }
  return number;
}

function mapCurrentUser(user: Row, profile: Row): Record<string, unknown> {""",
    )
    write(path, value)

# Care event persistence derives effective missed state for both WellMate and CareMate.
path = "supabase/functions/lifemate-api/care_events.ts"
value = read(path)
if "patientReminderMinutesBefore" not in value:
    value = value.replace(
        """  scheduledLocalTime: string;
  timeZone: string;
};""",
        """  scheduledLocalTime: string;
  timeZone: string;
  patientReminderMinutesBefore: number;
  caregiverReminderMinutesBefore: number;
};""",
    )
    value = value.replace(
        """          time_zone,
          status,""",
        """          time_zone,
          patient_reminder_minutes_before,
          caregiver_reminder_minutes_before,
          status,""",
    )
    value = value.replace(
        """          ${input.timeZone},
          'Scheduled',""",
        """          ${input.timeZone},
          ${input.patientReminderMinutesBefore},
          ${input.caregiverReminderMinutesBefore},
          'Scheduled',""",
    )
    value = value.replace(
        """    scheduledLocalTime,
    timeZone: requiredTimeZone(body.timeZone),
  };""",
        """    scheduledLocalTime,
    timeZone: requiredTimeZone(body.timeZone),
    patientReminderMinutesBefore: reminderMinutes(
      body.patientReminderMinutesBefore,
      'patientReminderMinutesBefore',
      30,
    ),
    caregiverReminderMinutesBefore: reminderMinutes(
      body.caregiverReminderMinutesBefore,
      'caregiverReminderMinutesBefore',
      60,
    ),
  };""",
    )
    value = value.replace(
        """    select *
    from lifemate.care_events""",
        """    select *,
      case
        when status = 'Scheduled'
          and ((scheduled_local_date + scheduled_local_time) at time zone time_zone) < now()
        then 'Missed'
        else status
      end as effective_status,
      ((scheduled_local_date + scheduled_local_time) at time zone time_zone)
        as scheduled_at_utc
    from lifemate.care_events""",
    )
    value = value.replace(
        """    row.time_zone === input.timeZone;
}""",
        """    row.time_zone === input.timeZone &&
    Number(row.patient_reminder_minutes_before ?? 30) ===
      input.patientReminderMinutesBefore &&
    Number(row.caregiver_reminder_minutes_before ?? 60) ===
      input.caregiverReminderMinutesBefore;
}""",
    )
    value = value.replace(
        """    timeZone: row.time_zone,
    status: String(row.status).toLowerCase(),""",
        """    timeZone: row.time_zone,
    scheduledAtUtc: row.scheduled_at_utc == null
      ? null
      : iso(row.scheduled_at_utc),
    status: String(row.effective_status ?? row.status).toLowerCase(),
    patientReminderMinutesBefore:
      Number(row.patient_reminder_minutes_before ?? 30),
    caregiverReminderMinutesBefore:
      Number(row.caregiver_reminder_minutes_before ?? 60),""",
    )
    value = value.replace(
        """function normalizeEventType(value: unknown): \"Appointment\" | \"Injection\" {""",
        """function reminderMinutes(
  value: unknown,
  field: string,
  fallback: number,
): number {
  if (value == null || value === '') return fallback;
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0 || number > 10080) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} must be an integer between 0 and 10080.`,
    );
  }
  return number;
}

function normalizeEventType(value: unknown): \"Appointment\" | \"Injection\" {""",
    )
    write(path, value)

# Integration workflows must apply the additive migration.
for workflow in [
    ".github/workflows/edge-api.yml",
    ".github/workflows/women-calendar-pilot-audit.yml",
]:
    if (ROOT / workflow).exists():
        value = read(workflow)
        marker = "supabase/migrations/20260804213000_add_profile_avatar_key.sql"
        addition = marker + " \\\n            supabase/migrations/20260805013000_add_reminder_lead_times.sql"
        if "20260805013000_add_reminder_lead_times.sql" not in value and marker in value:
            value = value.replace(marker, addition)
            write(workflow, value)

# Tests for the shared policy and trigger ordering.
write(
    "packages/lifemate_client/test/reminder_lead_time_test.dart",
    """import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('reminder lead normalization is bounded and deterministic', () {
    expect(
      LifeMateReminderLeadTimes.normalize('30', fallback: 60),
      30,
    );
    expect(
      LifeMateReminderLeadTimes.normalize(-1, fallback: 60),
      60,
    );
    expect(LifeMateReminderLeadTimes.label(60), '۱ ساعت قبل');
    expect(LifeMateReminderLeadTimes.label(1440), '۱ روز قبل');
  });
}
""",
)

# Extend existing CareMate reminder test with a trigger-order regression test.
path = "caremate/test/care_recipient_reminder_test.dart"
value = read(path)
if "orders by reminder trigger" not in value:
    insert = """

  test('orders by reminder trigger rather than scheduled time', () {
    final now = DateTime.utc(2026, 8, 5, 8);
    final reminders = selectEarliestReminderPerPatient(
      [
        CareRecipientReminder(
          patientUserId: 'p1',
          patientName: 'A',
          doseId: 'later-with-long-lead',
          medicationName: 'Visit',
          doseText: '',
          scheduledAtUtc: DateTime.utc(2026, 8, 5, 12),
          reminderMinutesBefore: 180,
          kind: 'appointment',
        ),
        CareRecipientReminder(
          patientUserId: 'p1',
          patientName: 'A',
          doseId: 'earlier-with-short-lead',
          medicationName: 'Medicine',
          doseText: '',
          scheduledAtUtc: DateTime.utc(2026, 8, 5, 10),
          reminderMinutesBefore: 30,
        ),
      ],
      nowUtc: now,
    );

    expect(reminders.single.doseId, 'later-with-long-lead');
    expect(reminders.single.triggerAtUtc, DateTime.utc(2026, 8, 5, 9));
  });
"""
    index = value.rfind("}")
    if index < 0:
        raise RuntimeError("care_recipient_reminder_test.dart missing closing brace")
    value = value[:index] + insert + value[index:]
    write(path, value)

print("Reminder state and lead-time changes materialized.")
