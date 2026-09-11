import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'today_contract.dart';

enum NotificationSourceMode { live, synthetic, unavailable }

@immutable
class NotificationCenterItem {
  const NotificationCenterItem({
    required this.notificationId,
    required this.sourceModuleId,
    required this.owner,
    required this.display,
    required this.severity,
    required this.createdAt,
    required this.isRead,
    this.action,
  });

  final String notificationId;
  final String sourceModuleId;
  final TodayOwnerPresentation owner;
  final TodayDisplayContent display;
  final TodaySeverity severity;
  final DateTime createdAt;
  final bool isRead;
  final TodayActionIntent? action;

  NotificationCenterItem copyWith({bool? isRead}) => NotificationCenterItem(
    notificationId: notificationId,
    sourceModuleId: sourceModuleId,
    owner: owner,
    display: display,
    severity: severity,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
    action: action,
  );
}

abstract interface class NotificationCenterSource {
  NotificationSourceMode get mode;

  Future<List<NotificationCenterItem>> load();

  Future<void> setRead(String notificationId, {required bool isRead});
}

class NotificationCenterUnavailable implements Exception {
  const NotificationCenterUnavailable();
}

class UnavailableNotificationCenterSource implements NotificationCenterSource {
  const UnavailableNotificationCenterSource();

  @override
  NotificationSourceMode get mode => NotificationSourceMode.unavailable;

  @override
  Future<List<NotificationCenterItem>> load() async =>
      throw const NotificationCenterUnavailable();

  @override
  Future<void> setRead(String notificationId, {required bool isRead}) async =>
      throw const NotificationCenterUnavailable();
}

/// Explicit preview/test source. It is in-memory only and must never be treated
/// as canonical read state by a production host.
class SyntheticNotificationCenterSource implements NotificationCenterSource {
  SyntheticNotificationCenterSource(Iterable<NotificationCenterItem> items)
    : _items = <String, NotificationCenterItem>{
        for (final item in items) item.notificationId: item,
      };

  final Map<String, NotificationCenterItem> _items;

  @override
  NotificationSourceMode get mode => NotificationSourceMode.synthetic;

  @override
  Future<List<NotificationCenterItem>> load() async {
    final result = _items.values.toList(growable: false)
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return UnmodifiableListView(result);
  }

  @override
  Future<void> setRead(String notificationId, {required bool isRead}) async {
    final current = _items[notificationId];
    if (current == null) return;
    _items[notificationId] = current.copyWith(isRead: isRead);
  }
}
