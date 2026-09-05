import 'package:flutter/material.dart';

/// A local-only presentation occurrence derived from a pending durable
/// treatment-create mutation. This is deliberately not a server treatment or
/// dose occurrence and must never be used as an occurrence ID for adherence.
final class PendingTreatmentCreateOccurrence {
  const PendingTreatmentCreateOccurrence({
    required this.localPresentationKey,
    required this.clientRequestId,
    required this.localDate,
    required this.localTime,
    required this.doseText,
  });

  final String localPresentationKey;
  final String clientRequestId;
  final DateTime localDate;
  final String localTime;
  final String doseText;
}

List<PendingTreatmentCreateOccurrence> projectPendingTreatmentCreates({
  required Iterable<Map<String, dynamic>> pendingCreates,
  required DateTime fromDate,
  required DateTime toDate,
}) {
  final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
  final to = DateTime(toDate.year, toDate.month, toDate.day);
  if (to.isBefore(from)) return const <PendingTreatmentCreateOccurrence>[];

  final result = <PendingTreatmentCreateOccurrence>[];
  final seenKeys = <String>{};
  for (final raw in pendingCreates) {
    if (raw['pendingSync'] != true) continue;
    final requestId = raw['clientRequestId']?.toString().trim() ?? '';
    final doseText = raw['doseText']?.toString().trim() ?? '';
    final start = _parseLocalDate(raw['startDate']);
    final end = raw['endDate'] == null ? null : _parseLocalDate(raw['endDate']);
    final recurrence = raw['recurrence'];
    if (requestId.isEmpty ||
        doseText.isEmpty ||
        start == null ||
        (end != null && end.isBefore(start)) ||
        recurrence is! Map ||
        recurrence['enabled'] != false) {
      continue;
    }

    final schedules = _parseSchedules(raw['schedules']);
    if (schedules == null || schedules.isEmpty) continue;

    final firstDate = start.isAfter(from) ? start : from;
    final lastDate = end != null && end.isBefore(to) ? end : to;
    if (lastDate.isBefore(firstDate)) continue;

    for (var date = firstDate;
        !date.isAfter(lastDate);
        date = date.add(const Duration(days: 1))) {
      for (final schedule in schedules) {
        if (_weekdayName(date.weekday) != schedule.dayOfWeek) continue;
        final key = 'local-pending:$requestId:${_dateText(date)}:${schedule.localTime}';
        if (!seenKeys.add(key)) continue;
        result.add(
          PendingTreatmentCreateOccurrence(
            localPresentationKey: key,
            clientRequestId: requestId,
            localDate: date,
            localTime: schedule.localTime,
            doseText: doseText,
          ),
        );
      }
    }
  }

  result.sort((left, right) {
    final dateCompare = left.localDate.compareTo(right.localDate);
    if (dateCompare != 0) return dateCompare;
    final timeCompare = left.localTime.compareTo(right.localTime);
    if (timeCompare != 0) return timeCompare;
    return left.localPresentationKey.compareTo(right.localPresentationKey);
  });
  return List<PendingTreatmentCreateOccurrence>.unmodifiable(result);
}

final class _PendingSchedule {
  const _PendingSchedule({required this.dayOfWeek, required this.localTime});

  final String dayOfWeek;
  final String localTime;
}

List<_PendingSchedule>? _parseSchedules(Object? raw) {
  if (raw is! List || raw.isEmpty) return null;
  final result = <_PendingSchedule>[];
  final seen = <String>{};
  for (final item in raw) {
    if (item is! Map) return null;
    final day = item['dayOfWeek']?.toString().trim().toLowerCase() ?? '';
    final time = item['localTime']?.toString().trim() ?? '';
    if (!_weekdays.contains(day) || !_localTime.hasMatch(time)) return null;
    if (seen.add('$day|$time')) {
      result.add(_PendingSchedule(dayOfWeek: day, localTime: time));
    }
  }
  return result;
}

DateTime? _parseLocalDate(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

String _weekdayName(int weekday) => switch (weekday) {
  DateTime.monday => 'monday',
  DateTime.tuesday => 'tuesday',
  DateTime.wednesday => 'wednesday',
  DateTime.thursday => 'thursday',
  DateTime.friday => 'friday',
  DateTime.saturday => 'saturday',
  DateTime.sunday => 'sunday',
  _ => '',
};

String _dateText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

final _localTime = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');
const _weekdays = <String>{
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
};

class PendingTreatmentCreateCard extends StatelessWidget {
  const PendingTreatmentCreateCard({
    super.key,
    required this.occurrence,
    required this.pendingCount,
    required this.font,
    required this.isPersian,
  });

  final PendingTreatmentCreateOccurrence occurrence;
  final int pendingCount;
  final TextStyle font;
  final bool isPersian;

  @override
  Widget build(BuildContext context) {
    final date = _dateText(occurrence.localDate);
    return Container(
      key: ValueKey('home-pending-treatment-create-${occurrence.localPresentationKey}'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPersian ? 'درمان ذخیره‌شده روی دستگاه' : 'Treatment saved on this device',
                  style: font.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${occurrence.doseText} • $date • ${occurrence.localTime}',
                  style: font.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  isPersian
                      ? 'در انتظار همگام‌سازی با سرور${pendingCount > 1 ? ' • $pendingCount نوبت محلی' : ''}'
                      : 'Pending server sync${pendingCount > 1 ? ' • $pendingCount local times' : ''}',
                  style: font.copyWith(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
