import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/care_daily_summary.dart';

class CareDailySummaryCopy {
  const CareDailySummaryCopy({required this.title, required this.body});

  final String title;
  final String body;
}

class CareDailySummaryNotificationService {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final Set<String> _shownKeys = <String>{};
  bool _initialized = false;

  Future<void> sync({
    required LifeMateApiClient apiClient,
    required Iterable<CareDailySummary> summaries,
    required String timeZone,
    required bool isPersian,
    DateTime? nowUtc,
  }) async {
    await _initialize();
    try {
      tz.setLocalLocation(tz.getLocation(timeZone));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
    }

    final relationships = await apiClient.getCareRelationships();
    final now = tz.TZDateTime.from(nowUtc ?? DateTime.now().toUtc(), tz.local);
    final dateKey =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';

    for (final summary in summaries) {
      final relationship = _relationshipForPatient(
        relationships,
        summary.patientUserId,
      );
      final preferences = _preferences(relationship);
      if (relationship == null ||
          preferences['enabled'] == false ||
          preferences['dailySummaryEnabled'] != true) {
        continue;
      }
      final preferredTime = preferences['dailySummaryLocalTime']?.toString();
      if (!isDue(now, preferredTime)) continue;

      final key = '${summary.patientUserId}:$dateKey';
      if (!_shownKeys.add(key)) continue;
      final copy = buildCopy(summary, isPersian: isPersian);
      try {
        await _notifications.show(
          _notificationId(key),
          copy.title,
          copy.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'caremate_daily_summary',
              LifeMateRuntimeLocale.select(
                fa: 'خلاصه روزانه مراقبت',
                en: 'Daily care summary',
              ),
              channelDescription: LifeMateRuntimeLocale.select(
                fa: 'خلاصه ثبت‌های درمانی امروز برای هر فرد، مطابق تنظیمات شما',
                en: 'A per-person summary of today’s recorded care activity, according to your preferences',
              ),
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              category: AndroidNotificationCategory.status,
              visibility: _visibilityForDetail(
                preferences['lockScreenDetail']?.toString(),
              ),
              onlyAlertOnce: true,
            ),
          ),
          payload: 'care-daily-summary:${summary.patientUserId}:$dateKey',
        );
      } catch (error) {
        _shownKeys.remove(key);
        debugPrint('CareMate daily summary failed safely: $error');
      }
    }
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(settings);
    _initialized = true;
  }

  static bool isDue(DateTime now, String? preferredTime) {
    final match = RegExp(r'^(\d{2}):(\d{2})').firstMatch(
      preferredTime?.trim() ?? '',
    );
    if (match == null) return false;
    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return false;
    }
    return now.hour * 60 + now.minute >= hour * 60 + minute;
  }

  static CareDailySummaryCopy buildCopy(
    CareDailySummary summary, {
    required bool isPersian,
  }) {
    final title = isPersian
        ? '☀️ وضعیت امروز ${summary.patientDisplayName}'
        : '☀️ Today for ${summary.patientDisplayName}';
    final progress = isPersian
        ? '${summary.completed} از ${summary.total} درمان ثبت‌شده انجام شد.'
        : '${summary.completed} of ${summary.total} recorded treatments were completed.';
    final status = summary.unresolved == 0
        ? (isPersian
              ? 'مورد درمانی پیگیری‌نشده‌ای در برنامه امروز باقی نمانده.'
              : 'No recorded treatment item remains unresolved in today’s plan.')
        : summary.alerts > 0
        ? (isPersian
              ? '${summary.alerts} مورد missed/skipped و ${summary.pending} مورد در انتظار پیگیری است.'
              : '${summary.alerts} item(s) are missed/skipped and ${summary.pending} remain pending.')
        : (isPersian
              ? '${summary.pending} مورد هنوز در انتظار پیگیری است.'
              : '${summary.pending} item(s) remain pending.');
    return CareDailySummaryCopy(title: title, body: '$progress $status');
  }

  static Map<String, dynamic>? _relationshipForPatient(
    Iterable<Map<String, dynamic>> relationships,
    String patientUserId,
  ) {
    for (final relationship in relationships) {
      if (relationship['patientUserId']?.toString() == patientUserId &&
          relationship['status']?.toString().toLowerCase() == 'active') {
        return relationship;
      }
    }
    return null;
  }

  static Map<String, dynamic> _preferences(Map<String, dynamic>? relationship) {
    final value = relationship?['notificationPreferences'];
    return value is Map<String, dynamic> ? value : const <String, dynamic>{};
  }

  static NotificationVisibility _visibilityForDetail(String? detail) {
    return switch (detail?.toLowerCase()) {
      'full' => NotificationVisibility.public,
      'hidden' => NotificationVisibility.secret,
      _ => NotificationVisibility.private,
    };
  }

  static int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in 'care-summary:$value'.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
