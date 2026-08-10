import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:lifemate_client/lifemate_client.dart';

const String _androidWidgetProviderName = 'MedicationWidgetProvider';
const String _androidWidgetProviderQualifiedName =
    'com.lifemate.wellmate.MedicationWidgetProvider';

const String _hasDataKey = 'wm_widget_has_data';
const String _occurrenceIdKey = 'wm_widget_occurrence_id';
const String _versionKey = 'wm_widget_version';
const String _treatmentNameKey = 'wm_widget_treatment_name';
const String _descriptionKey = 'wm_widget_description';
const String _doseKey = 'wm_widget_dose';
const String _quantityKey = 'wm_widget_quantity';
const String _timeKey = 'wm_widget_time';
const String _scheduledAtEpochMsKey = 'wm_widget_scheduled_at_epoch_ms';
const String _overdueKey = 'wm_widget_overdue';
const String _actionMessageKey = 'wm_widget_action_message';

/// Small, intentionally Android-only bridge between WellMate's reviewed API
/// boundary and the native home-screen medication widget.
///
/// The widget never receives database credentials. Its interactive "مصرف کردم"
/// action reuses the authenticated [LifeMateApiClient] dose-report endpoint.
abstract final class MedicationHomeWidgetService {
  static bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> initializeInteractivity() async {
    if (!isSupportedPlatform) return;
    await HomeWidget.registerInteractivityCallback(
      medicationHomeWidgetBackgroundCallback,
    );
  }

  static Future<bool> hasInstalledWidget() async {
    if (!isSupportedPlatform) return false;
    final installed = await HomeWidget.getInstalledWidgets();
    return installed.isNotEmpty;
  }

  static Future<bool> requestPin() async {
    if (!isSupportedPlatform) return false;
    final supported = await HomeWidget.isRequestPinWidgetSupported();
    if (supported != true) return false;
    await HomeWidget.requestPinWidget(
      name: _androidWidgetProviderName,
      androidName: _androidWidgetProviderName,
      qualifiedAndroidName: _androidWidgetProviderQualifiedName,
    );
    return true;
  }

  static Future<void> refreshFromApi(
    LifeMateApiClient api, {
    DateTime? now,
  }) async {
    if (!isSupportedPlatform) return;
    final reference = now ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final snapshot = await api.getHomeSnapshot(
      fromDate: today,
      toDate: today.add(const Duration(days: 7)),
    );
    final treatmentPlans = _objects(snapshot['treatmentPlans']);
    final doseOccurrences = _objects(snapshot['doseOccurrences']);
    await sync(
      treatmentPlans: treatmentPlans,
      doseOccurrences: doseOccurrences,
      now: reference,
    );
  }

  static Future<void> sync({
    required List<Map<String, dynamic>> treatmentPlans,
    required List<Map<String, dynamic>> doseOccurrences,
    DateTime? now,
  }) async {
    if (!isSupportedPlatform) return;
    final reference = now ?? DateTime.now();
    final data = selectMedicationWidgetData(
      treatmentPlans: treatmentPlans,
      doseOccurrences: doseOccurrences,
      now: reference,
    );

    if (data == null) {
      await HomeWidget.saveWidgetData<bool>(_hasDataKey, false);
      await HomeWidget.saveWidgetData<String>(_occurrenceIdKey, '');
      await HomeWidget.saveWidgetData<int>(_versionKey, 0);
      await HomeWidget.saveWidgetData<String>(_treatmentNameKey, '');
      await HomeWidget.saveWidgetData<String>(_descriptionKey, '');
      await HomeWidget.saveWidgetData<String>(_doseKey, '');
      await HomeWidget.saveWidgetData<String>(_quantityKey, '');
      await HomeWidget.saveWidgetData<String>(_timeKey, '');
      await HomeWidget.saveWidgetData<int>(_scheduledAtEpochMsKey, 0);
      await HomeWidget.saveWidgetData<bool>(_overdueKey, false);
      await HomeWidget.saveWidgetData<String>(_actionMessageKey, '');
    } else {
      await HomeWidget.saveWidgetData<bool>(_hasDataKey, true);
      await HomeWidget.saveWidgetData<String>(
        _occurrenceIdKey,
        data.occurrenceId,
      );
      await HomeWidget.saveWidgetData<int>(_versionKey, data.version);
      await HomeWidget.saveWidgetData<String>(
        _treatmentNameKey,
        data.treatmentName,
      );
      await HomeWidget.saveWidgetData<String>(
        _descriptionKey,
        data.description,
      );
      await HomeWidget.saveWidgetData<String>(_doseKey, data.dose);
      await HomeWidget.saveWidgetData<String>(_quantityKey, data.quantity);
      await HomeWidget.saveWidgetData<String>(_timeKey, data.time);
      await HomeWidget.saveWidgetData<int>(
        _scheduledAtEpochMsKey,
        data.scheduledAt.millisecondsSinceEpoch,
      );
      await HomeWidget.saveWidgetData<bool>(
        _overdueKey,
        data.scheduledAt.isBefore(reference),
      );
      await HomeWidget.saveWidgetData<String>(_actionMessageKey, '');
    }

    await _update();
  }

  static Future<void> _update() => HomeWidget.updateWidget(
    name: _androidWidgetProviderName,
    androidName: _androidWidgetProviderName,
    qualifiedAndroidName: _androidWidgetProviderQualifiedName,
  );

  static List<Map<String, dynamic>> _objects(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map<Map<String, dynamic>>(
          (item) => <String, dynamic>{
            for (final entry in item.entries)
              entry.key.toString(): entry.value,
          },
        )
        .toList(growable: false);
  }
}

class MedicationWidgetData {
  const MedicationWidgetData({
    required this.occurrenceId,
    required this.version,
    required this.treatmentName,
    required this.description,
    required this.dose,
    required this.quantity,
    required this.time,
    required this.scheduledAt,
  });

  final String occurrenceId;
  final int version;
  final String treatmentName;
  final String description;
  final String dose;
  final String quantity;
  final String time;
  final DateTime scheduledAt;
}

@visibleForTesting
MedicationWidgetData? selectMedicationWidgetData({
  required List<Map<String, dynamic>> treatmentPlans,
  required List<Map<String, dynamic>> doseOccurrences,
  required DateTime now,
}) {
  final plansById = <String, Map<String, dynamic>>{
    for (final plan in treatmentPlans)
      if (_text(plan['id']) case final id?) id: plan,
  };

  final candidates = <_MedicationWidgetCandidate>[];
  for (final occurrence in doseOccurrences) {
    final status = (_text(occurrence['status']) ?? 'scheduled').toLowerCase();
    if (status != 'scheduled' && status != 'missed') continue;

    final occurrenceId = _text(occurrence['id']);
    final planId = _text(occurrence['treatmentPlanId']);
    if (occurrenceId == null || planId == null) continue;

    final plan = plansById[planId];
    if (plan == null) continue;
    final scheduledAt = _scheduledAt(occurrence);
    if (scheduledAt == null) continue;

    final medication = _object(plan['medication']);
    final treatmentName = _text(medication['name']) ?? 'دارو';
    final description =
        _text(plan['instructions']) ??
        _text(medication['notes']) ??
        'طبق برنامه درمان';
    final dose = _text(medication['strengthText']) ?? 'دوز ثبت نشده';
    final quantity = _text(plan['doseText']) ?? '۱ نوبت';
    final rawTime = _text(occurrence['scheduledLocalTime']) ?? '--:--';
    final normalizedTime = rawTime.length >= 5
        ? rawTime.substring(0, 5)
        : rawTime;
    final version = occurrence['version'] is int
        ? occurrence['version'] as int
        : int.tryParse(occurrence['version']?.toString() ?? '') ?? 1;

    candidates.add(
      _MedicationWidgetCandidate(
        data: MedicationWidgetData(
          occurrenceId: occurrenceId,
          version: version,
          treatmentName: treatmentName,
          description: description,
          dose: toPersianDigits(dose),
          quantity: toPersianDigits(quantity),
          time: toPersianDigits(normalizedTime),
          scheduledAt: scheduledAt,
        ),
      ),
    );
  }

  if (candidates.isEmpty) return null;

  final future = candidates
      .where((candidate) => !candidate.data.scheduledAt.isBefore(now))
      .toList()
    ..sort(
      (left, right) =>
          left.data.scheduledAt.compareTo(right.data.scheduledAt),
    );
  if (future.isNotEmpty) return future.first.data;

  // If the API has not yet rolled a past scheduled occurrence to `missed`,
  // keep the newest overdue dose actionable instead of making the widget empty.
  final overdue = List<_MedicationWidgetCandidate>.from(candidates)
    ..sort(
      (left, right) =>
          right.data.scheduledAt.compareTo(left.data.scheduledAt),
    );
  return overdue.first.data;
}

@visibleForTesting
String toPersianDigits(String value) {
  const western = '0123456789';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final index = western.indexOf(character);
    buffer.write(index < 0 ? character : persian[index]);
  }
  return buffer.toString();
}

class _MedicationWidgetCandidate {
  const _MedicationWidgetCandidate({required this.data});

  final MedicationWidgetData data;
}

Map<String, dynamic> _object(dynamic value) {
  if (value is! Map) return const <String, dynamic>{};
  return <String, dynamic>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

String? _text(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _scheduledAt(Map<String, dynamic> occurrence) {
  final utc = DateTime.tryParse(
    occurrence['scheduledAtUtc']?.toString() ?? '',
  );
  if (utc != null) return utc.toLocal();

  final date = DateTime.tryParse(
    occurrence['scheduledLocalDate']?.toString() ?? '',
  );
  final parts =
      occurrence['scheduledLocalTime']?.toString().split(':') ?? const [];
  if (date == null || parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return DateTime(date.year, date.month, date.day, hour, minute);
}

@pragma('vm:entry-point')
FutureOr<void> medicationHomeWidgetBackgroundCallback(Uri? data) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (data == null || data.host.toLowerCase() != 'taken') return;

  final occurrenceId = data.queryParameters['id']?.trim();
  final version = int.tryParse(data.queryParameters['version'] ?? '');
  if (occurrenceId == null || occurrenceId.isEmpty || version == null) {
    await _setWidgetActionError('اطلاعات نوبت کامل نیست');
    return;
  }

  LifeMateApiClient? api;
  try {
    final config = AppConfig.fromEnvironment();
    if (!config.isConfigured) {
      await _setWidgetActionError('تنظیمات WellMate کامل نیست');
      return;
    }

    await LifeMateBootstrap.initialize(config);
    final accessToken = await LifeMateAuth.getValidAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      await _setWidgetActionError('برای ثبت مصرف وارد WellMate شوید');
      return;
    }

    api = LifeMateApiClient(
      baseUri: config.apiBaseUri,
      accessToken: () => LifeMateAuth.currentAccessToken,
    );
    await api.reportDose(
      occurrenceId: occurrenceId,
      clientRequestId: LifeMateApiClient.createClientRequestId(),
      version: version,
      status: 'taken',
      occurredAtUtc: DateTime.now().toUtc(),
    );
    await MedicationHomeWidgetService.refreshFromApi(api);
  } on LifeMateApiException catch (error) {
    if (error.statusCode == 409) {
      if (api != null) {
        try {
          await MedicationHomeWidgetService.refreshFromApi(api);
          return;
        } catch (_) {
          // Fall through to the retry message below.
        }
      }
    }
    await _setWidgetActionError(
      error.isUnauthorized
          ? 'برای ثبت مصرف وارد WellMate شوید'
          : 'ثبت نشد؛ دوباره لمس کنید',
    );
  } catch (_) {
    await _setWidgetActionError('ثبت نشد؛ دوباره لمس کنید');
  } finally {
    api?.close();
  }
}

Future<void> _setWidgetActionError(String message) async {
  if (!MedicationHomeWidgetService.isSupportedPlatform) return;
  await HomeWidget.saveWidgetData<String>(
    _actionMessageKey,
    toPersianDigits(message),
  );
  await HomeWidget.updateWidget(
    name: _androidWidgetProviderName,
    androidName: _androidWidgetProviderName,
    qualifiedAndroidName: _androidWidgetProviderQualifiedName,
  );
}
