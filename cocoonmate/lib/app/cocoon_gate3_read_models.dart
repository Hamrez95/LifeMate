import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:lifemate_client/lifemate_client.dart';

typedef CocoonGate3ReadLoader =
    Future<CocoonGate3ReadModels> Function({
      required DateTime now,
      required bool fa,
    });

/// Canonical source identity retained beside a presentation-only Records row.
///
/// The opaque source/deep-link values are never interpreted here. Keeping them
/// separate from the presentation id prevents a future detail action from
/// guessing a treatment, observation or care-event id from display data.
final class CocoonRecordSourceIdentity {
  const CocoonRecordSourceIdentity({
    required this.sourceKind,
    required this.sourceId,
    this.deepLink,
    this.sourceVersion,
  });

  factory CocoonRecordSourceIdentity.fromCanonical(
    CocoonPregnancyRecordItem source,
  ) {
    final deepLink = source.deepLink?.trim();
    return CocoonRecordSourceIdentity(
      sourceKind: source.sourceKind,
      sourceId: source.sourceId,
      deepLink: deepLink == null || deepLink.isEmpty ? null : deepLink,
      sourceVersion: source.sourceVersion,
    );
  }

  final String sourceKind;
  final String sourceId;
  final String? deepLink;
  final int? sourceVersion;
}

/// Presentation projection for the Gate-3 daily-use surfaces.
///
/// Every item comes from an authorized canonical API response. This class owns
/// no health truth, clinical interpretation, entitlement, or sharing authority.
final class CocoonGate3ReadModels {
  const CocoonGate3ReadModels({
    required this.calendarState,
    required this.calendarItems,
    required this.calendarAsOfLocalDate,
    required this.recordsState,
    required this.records,
    this.recordSources = const {},
  });

  final CocoonCalendarLoadState calendarState;
  final List<CocoonCalendarItem> calendarItems;
  final DateTime calendarAsOfLocalDate;
  final CocoonRecordsState recordsState;
  final List<CocoonRecordViewData> records;

  /// Canonical source identity keyed by the corresponding Records presentation
  /// id. Health payload values are deliberately not copied into this map.
  final Map<String, CocoonRecordSourceIdentity> recordSources;

  CocoonRecordSourceIdentity? sourceForRecord(String recordId) =>
      recordSources[recordId];
}

/// Loads the canonical Calendar and composed Records read models in parallel.
///
/// Failures are isolated per surface so a Calendar refresh failure does not
/// erase a valid Records response (and vice versa). No mutation is performed.
final class CocoonGate3ReadModelLoader {
  CocoonGate3ReadModelLoader({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
  }) : _calendar = CocoonPregnancyCalendarApiClient(
         baseUri: baseUri,
         accessToken: accessToken,
       ),
       _records = CocoonPregnancyRecordsApiClient(
         baseUri: baseUri,
         accessToken: accessToken,
       );

  final CocoonPregnancyCalendarApiClient _calendar;
  final CocoonPregnancyRecordsApiClient _records;

  Future<CocoonGate3ReadModels> load({
    required DateTime now,
    required bool fa,
  }) async {
    // Locale-specific copy remains presentation-owned. The seam is retained so
    // the host contract does not churn when localized read-model labels move to
    // the module catalog.
    final localToday = DateTime(now.year, now.month, now.day);
    final calendarTo = localToday.add(const Duration(days: 30));
    final recordsFrom = localToday.subtract(const Duration(days: 90));

    // Start both requests before awaiting either one.
    final calendarFuture = _calendar.list(
      fromDate: localToday,
      toDate: calendarTo,
    );
    final recordsFuture = _records.list(
      fromDate: recordsFrom,
      toDate: localToday,
      limit: 100,
    );

    CocoonCalendarLoadState calendarState = CocoonCalendarLoadState.error;
    List<CocoonCalendarItem> calendarItems = const [];
    try {
      final page = await calendarFuture;
      calendarItems = page.items
          .map((item) => _calendarItem(item, fa: fa))
          .toList(growable: false);
      calendarState = calendarItems.isEmpty
          ? CocoonCalendarLoadState.empty
          : CocoonCalendarLoadState.populated;
    } on Object {
      calendarState = CocoonCalendarLoadState.error;
    }

    CocoonRecordsState recordsState = CocoonRecordsState.error;
    List<CocoonRecordViewData> records = const [];
    Map<String, CocoonRecordSourceIdentity> recordSources = const {};
    try {
      final page = await recordsFuture;
      recordSources = _recordSourceMap(page.items);
      records = page.items
          .map((item) => _recordItem(item, fa: fa))
          .toList(growable: false);
      recordsState = records.isEmpty
          ? CocoonRecordsState.empty
          : CocoonRecordsState.ready;
    } on Object {
      recordsState = CocoonRecordsState.error;
      records = const [];
      recordSources = const {};
    }

    return CocoonGate3ReadModels(
      calendarState: calendarState,
      calendarItems: calendarItems,
      calendarAsOfLocalDate: localToday,
      recordsState: recordsState,
      records: records,
      recordSources: recordSources,
    );
  }

  void close() {
    _calendar.close();
    _records.close();
  }
}

Map<String, CocoonRecordSourceIdentity> _recordSourceMap(
  List<CocoonPregnancyRecordItem> items,
) {
  final values = <String, CocoonRecordSourceIdentity>{};
  for (final item in items) {
    if (values.containsKey(item.id)) {
      throw const FormatException(
        'Cocoon pregnancy Records returned a duplicate presentation id.',
      );
    }
    values[item.id] = CocoonRecordSourceIdentity.fromCanonical(item);
  }
  return Map<String, CocoonRecordSourceIdentity>.unmodifiable(values);
}

CocoonCalendarItem _calendarItem(
  CocoonPregnancyCalendarItem source, {
  required bool fa,
}) {
  final event = source.careEvent;
  final title =
      _string(event['title']) ??
      _calendarClassificationLabel(source.classification, fa: fa);
  final date =
      _string(event['scheduledLocalDate']) ?? _string(event['localDate']) ?? '';
  final time = _string(event['scheduledLocalTime']);
  final supportingParts = <String>[
    if (_string(event['providerName']) case final value?) value,
    if (_string(event['specialty']) case final value?) value,
  ];

  return CocoonCalendarItem(
    id: source.id,
    title: title,
    dateLabel: date,
    timeLabel: time,
    supporting: supportingParts.isEmpty ? null : supportingParts.join(' · '),
    kind: CocoonCalendarItemKind.appointment,
    appointmentKind: switch (source.classification) {
      CocoonPregnancyCalendarClassification.prenatal ||
      CocoonPregnancyCalendarClassification.checkup =>
        CocoonCalendarAppointmentKind.checkup,
      CocoonPregnancyCalendarClassification.ultrasound =>
        CocoonCalendarAppointmentKind.ultrasound,
      CocoonPregnancyCalendarClassification.labTest =>
        CocoonCalendarAppointmentKind.lab,
      CocoonPregnancyCalendarClassification.injection =>
        CocoonCalendarAppointmentKind.injection,
      CocoonPregnancyCalendarClassification.other =>
        CocoonCalendarAppointmentKind.other,
    },
    pendingSync: false,
  );
}

CocoonRecordViewData _recordItem(
  CocoonPregnancyRecordItem source, {
  required bool fa,
}) {
  final title = _recordTitle(source, fa: fa);
  final summary = _recordSummary(source, fa: fa);
  return CocoonRecordViewData(
    id: source.id,
    title: title,
    dateLabel: source.localDate,
    sectionLabel: source.localDate,
    summary: summary,
    kind: _recordKind(source.category),
    syncState: CocoonRecordSyncState.confirmed,
  );
}

CocoonRecordKind _recordKind(String category) => switch (category) {
  'appointments' => CocoonRecordKind.appointment,
  'measurements' => CocoonRecordKind.measurement,
  'medications' => CocoonRecordKind.medication,
  'pregnancy' ||
  'check_ins' ||
  'symptoms' ||
  'moods' => CocoonRecordKind.checkIn,
  _ => CocoonRecordKind.document,
};

String _recordTitle(CocoonPregnancyRecordItem source, {required bool fa}) {
  final summary = source.summary;
  return switch (source.category) {
    'pregnancy' => _copy('Pregnancy started', 'شروع بارداری', fa),
    'check_ins' => _copy('Daily check-in', 'حال روزانه', fa),
    'symptoms' => _humanCode(
      _string(summary['symptomCode']) ?? source.type,
      fa: fa,
    ),
    'moods' => _copy('Mood', 'حال روحی', fa),
    'measurements' => _measurementLabel(
      _string(summary['observationType']) ?? source.type,
      fa: fa,
    ),
    'appointments' => _humanCode(
      _string(summary['pregnancyClassification']) ?? source.type,
      fa: fa,
    ),
    'medications' =>
      source.type == 'dose_occurrence'
          ? _copy('Medication dose', 'نوبت مصرف دارو', fa)
          : _copy('Treatment plan', 'برنامه درمانی', fa),
    _ => _humanCode(source.type, fa: fa),
  };
}

String? _recordSummary(CocoonPregnancyRecordItem source, {required bool fa}) {
  final summary = source.summary;
  final values = <String>[];
  switch (source.category) {
    case 'check_ins':
      _addCode(values, summary['feeling'], fa: fa);
      _addCode(values, summary['energy'], fa: fa);
      break;
    case 'symptoms':
      _addCode(values, summary['intensity'], fa: fa);
      break;
    case 'moods':
      _addCode(values, summary['moodCode'], fa: fa);
      break;
    case 'appointments':
      _addCode(values, summary['status'], fa: fa);
      break;
    case 'medications':
      _addCode(values, summary['status'], fa: fa);
      break;
    case 'measurements':
      // Values intentionally stay in the canonical detail surface; the Records
      // list only identifies the measurement kind to avoid excess health text.
      break;
    case 'pregnancy':
      _addCode(values, summary['status'], fa: fa);
      break;
    default:
      break;
  }
  return values.isEmpty ? null : values.join(' · ');
}

void _addCode(List<String> values, Object? raw, {required bool fa}) {
  final value = _string(raw);
  if (value != null) values.add(_humanCode(value, fa: fa));
}

String _measurementLabel(String raw, {required bool fa}) => switch (raw) {
  'weight' => _copy('Weight', 'وزن', fa),
  'blood_pressure' => _copy('Blood pressure', 'فشار خون', fa),
  'blood_glucose' => _copy('Blood glucose', 'قند خون', fa),
  _ => _humanCode(raw, fa: fa),
};

String _calendarClassificationLabel(
  CocoonPregnancyCalendarClassification value, {
  required bool fa,
}) => switch (value) {
  CocoonPregnancyCalendarClassification.prenatal => _copy(
    'Prenatal appointment',
    'قرار مراقبت بارداری',
    fa,
  ),
  CocoonPregnancyCalendarClassification.ultrasound => _copy(
    'Ultrasound',
    'سونوگرافی',
    fa,
  ),
  CocoonPregnancyCalendarClassification.checkup => _copy(
    'Check-up',
    'ویزیت',
    fa,
  ),
  CocoonPregnancyCalendarClassification.labTest => _copy(
    'Lab test',
    'آزمایش',
    fa,
  ),
  CocoonPregnancyCalendarClassification.injection => _copy(
    'Injection',
    'تزریق',
    fa,
  ),
  CocoonPregnancyCalendarClassification.other => _copy(
    'Care event',
    'رویداد مراقبتی',
    fa,
  ),
};

String _humanCode(String value, {required bool fa}) {
  final localized = switch (value.trim()) {
    'comfortable' => _copy('Comfortable', 'آرام و خوب', fa),
    'steady' => _copy('Steady', 'معمولی', fa),
    'active' => _copy('Active', 'فعال', fa),
    'scheduled' => _copy('Scheduled', 'زمان‌بندی‌شده', fa),
    'completed' => _copy('Completed', 'انجام‌شده', fa),
    'pending' => _copy('Pending', 'در انتظار', fa),
    _ => null,
  };
  if (localized != null) return localized;
  final normalized = value.trim().replaceAll('_', ' ');
  if (normalized.isEmpty) return value;
  return normalized[0].toUpperCase() + normalized.substring(1);
}

String _copy(String en, String fa, bool usePersian) => usePersian ? fa : en;

String? _string(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
