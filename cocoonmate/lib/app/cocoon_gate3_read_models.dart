import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:lifemate_client/lifemate_client.dart';

typedef CocoonGate3ReadLoader =
    Future<CocoonGate3ReadModels> Function({
      required DateTime now,
      required bool fa,
    });

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
  });

  final CocoonCalendarLoadState calendarState;
  final List<CocoonCalendarItem> calendarItems;
  final DateTime calendarAsOfLocalDate;
  final CocoonRecordsState recordsState;
  final List<CocoonRecordViewData> records;
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
    try {
      final page = await recordsFuture;
      records = page.items
          .map((item) => _recordItem(item, fa: fa))
          .toList(growable: false);
      recordsState = records.isEmpty
          ? CocoonRecordsState.empty
          : CocoonRecordsState.ready;
    } on Object {
      recordsState = CocoonRecordsState.error;
    }

    return CocoonGate3ReadModels(
      calendarState: calendarState,
      calendarItems: calendarItems,
      calendarAsOfLocalDate: localToday,
      recordsState: recordsState,
      records: records,
    );
  }

  void close() {
    _calendar.close();
    _records.close();
  }
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
    pendingSync: false,
  );
}

CocoonRecordViewData _recordItem(
  CocoonPregnancyRecordItem source, {
  required bool fa,
}) {
  final title = _recordTitle(source, fa: fa);
  final summary = _recordSummary(source);
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
    'pregnancy' => fa ? 'شروع بارداری' : 'Pregnancy started',
    'check_ins' => fa ? 'حال روزانه' : 'Daily check-in',
    'symptoms' => _humanCode(_string(summary['symptomCode']) ?? source.type),
    'moods' => fa ? 'حال روحی' : 'Mood',
    'measurements' => _measurementLabel(
      _string(summary['observationType']) ?? source.type,
      fa: fa,
    ),
    'appointments' => _humanCode(
      _string(summary['pregnancyClassification']) ?? source.type,
    ),
    'medications' =>
      source.type == 'dose_occurrence'
          ? (fa ? 'نوبت دارو' : 'Medication dose')
          : (fa ? 'برنامه درمانی' : 'Treatment plan'),
    _ => _humanCode(source.type),
  };
}

String? _recordSummary(CocoonPregnancyRecordItem source) {
  final summary = source.summary;
  final values = <String>[];
  switch (source.category) {
    case 'check_ins':
      _addCode(values, summary['feeling']);
      _addCode(values, summary['energy']);
      break;
    case 'symptoms':
      _addCode(values, summary['intensity']);
      break;
    case 'moods':
      _addCode(values, summary['moodCode']);
      break;
    case 'appointments':
      _addCode(values, summary['status']);
      break;
    case 'medications':
      _addCode(values, summary['status']);
      break;
    case 'measurements':
      // Values intentionally stay in the canonical detail surface; the Records
      // list only identifies the measurement kind to avoid excess health text.
      break;
    case 'pregnancy':
      _addCode(values, summary['status']);
      break;
    default:
      break;
  }
  return values.isEmpty ? null : values.join(' · ');
}

void _addCode(List<String> values, Object? raw) {
  final value = _string(raw);
  if (value != null) values.add(_humanCode(value));
}

String _measurementLabel(String raw, {required bool fa}) => switch (raw) {
  'weight' => fa ? 'وزن' : 'Weight',
  'blood_pressure' => fa ? 'فشار خون' : 'Blood pressure',
  'blood_glucose' => fa ? 'قند خون' : 'Blood glucose',
  _ => _humanCode(raw),
};

String _calendarClassificationLabel(
  CocoonPregnancyCalendarClassification value, {
  required bool fa,
}) => switch (value) {
  CocoonPregnancyCalendarClassification.prenatal =>
    fa ? 'ویزیت بارداری' : 'Prenatal appointment',
  CocoonPregnancyCalendarClassification.ultrasound =>
    fa ? 'سونوگرافی' : 'Ultrasound',
  CocoonPregnancyCalendarClassification.checkup => fa ? 'معاینه' : 'Check-up',
  CocoonPregnancyCalendarClassification.labTest => fa ? 'آزمایش' : 'Lab test',
  CocoonPregnancyCalendarClassification.injection => fa ? 'تزریق' : 'Injection',
  CocoonPregnancyCalendarClassification.other =>
    fa ? 'رویداد مراقبتی' : 'Care event',
};

String _humanCode(String value) {
  final normalized = value.trim().replaceAll('_', ' ');
  if (normalized.isEmpty) return value;
  return normalized[0].toUpperCase() + normalized.substring(1);
}

String? _string(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
