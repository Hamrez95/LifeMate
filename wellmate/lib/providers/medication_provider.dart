import 'package:flutter/material.dart';

import '../../models/schedule_item_model.dart';

class MedicationProvider extends ChangeNotifier {
  List<ScheduleItemModel> _scheduleItems = const [];

  List<ScheduleItemModel> get allMedications => _scheduleItems
      .where((item) => item.type == 'medicine')
      .toList(growable: false);

  List<ScheduleItemModel> get allScheduleItems =>
      List<ScheduleItemModel>.unmodifiable(_scheduleItems);

  /// Returns every actionable occurrence that was missed today, including
  /// medicines, doctor appointments and injections.
  List<ScheduleItemModel> get missedItems {
    final now = DateTime.now();
    final items = _scheduleItems
        .where((item) => _isMissed(item, now))
        .toList(growable: false);
    return items..sort(_compareOccurrence);
  }

  bool _isMissed(ScheduleItemModel item, DateTime now) {
    if (item.isDone) return false;

    final status = item.status.toLowerCase();
    if (status == 'missed') return true;

    // Care events are promoted to `missed` by the API/home mapper. Do not
    // infer a missed visit merely from a malformed/local time value.
    if (item.type != 'medicine' || status != 'scheduled') return false;

    final scheduled = _scheduledDateTime(item, now);
    return scheduled != null && scheduled.isBefore(now);
  }

  DateTime? _scheduledDateTime(ScheduleItemModel item, DateTime now) {
    final scheduledAtUtc = item.scheduledAtUtc;
    if (scheduledAtUtc != null) return scheduledAtUtc.toLocal();

    final parts = item.time.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1].split(' ').first);
    if (hour == null || minute == null) return null;

    final date = item.startDate ?? now;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  int _compareOccurrence(ScheduleItemModel left, ScheduleItemModel right) {
    final now = DateTime.now();
    final leftDate = _scheduledDateTime(left, now) ?? DateTime(2100);
    final rightDate = _scheduledDateTime(right, now) ?? DateTime(2100);
    return leftDate.compareTo(rightDate);
  }

  /// Replaces the complete schedule snapshot used by the notification bell.
  void setScheduleItems(List<ScheduleItemModel> items) {
    _scheduleItems = List<ScheduleItemModel>.unmodifiable(items);
    notifyListeners();
  }

  /// Backwards-compatible medication-only update for older call sites.
  void setMedications(List<ScheduleItemModel> items) {
    final careItems = _scheduleItems.where((item) => item.type != 'medicine');
    setScheduleItems(<ScheduleItemModel>[...careItems, ...items]);
  }

  void markAsDone(String id) {
    final index = _scheduleItems.indexWhere((item) => item.id == id);
    if (index == -1) return;

    _scheduleItems = List<ScheduleItemModel>.of(_scheduleItems)
      ..[index] = _scheduleItems[index].copyWith(isDone: true, status: 'taken');
    notifyListeners();
  }
}
