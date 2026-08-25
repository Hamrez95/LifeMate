import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/providers/notification_provider.dart';

void main() {
  test('action payload round trips without treatment details', () {
    const target = WellMateNotificationTarget(
      type: 'medicine',
      id: 'occurrence-1',
      version: 3,
      clientRequestId: '11111111-1111-4111-8111-111111111111',
      isPersian: false,
    );

    final payload = NotificationProvider.encodeActionPayload(target);
    final decoded = NotificationProvider.decodeActionPayload(payload);

    expect(decoded, isNotNull);
    expect(decoded!.id, target.id);
    expect(decoded.version, 3);
    expect(decoded.clientRequestId, target.clientRequestId);
    expect(payload, isNot(contains('medicine name')));
  });

  test('medicine notification exposes taken, snooze and open actions', () {
    const target = WellMateNotificationTarget(
      type: 'medicine',
      id: 'occurrence-1',
      version: 1,
      clientRequestId: '11111111-1111-4111-8111-111111111111',
      isPersian: false,
    );

    final ids = NotificationProvider.actionButtonsForTarget(target)
        .map((action) => action.id)
        .toList();

    expect(ids, contains(NotificationProvider.takenActionId));
    expect(ids, contains(NotificationProvider.snoozeActionId));
    expect(ids, contains(NotificationProvider.openActionId));
    expect(ids, isNot(contains(NotificationProvider.completedActionId)));
  });

  test('single care event exposes done action', () {
    const target = WellMateNotificationTarget(
      type: 'appointment',
      id: 'event-1',
      seriesId: 'event-1',
      version: 2,
      clientRequestId: '11111111-1111-4111-8111-111111111111',
      isPersian: false,
    );

    final ids = NotificationProvider.actionButtonsForTarget(target)
        .map((action) => action.id)
        .toList();
    expect(ids, contains(NotificationProvider.completedActionId));
  });

  test('recurring care occurrence never exposes series completion action', () {
    const target = WellMateNotificationTarget(
      type: 'injection',
      id: 'event-1:2026-08-25',
      seriesId: 'event-1',
      version: 2,
      clientRequestId: '11111111-1111-4111-8111-111111111111',
      isPersian: false,
    );

    final ids = NotificationProvider.actionButtonsForTarget(target)
        .map((action) => action.id)
        .toList();
    expect(ids, isNot(contains(NotificationProvider.completedActionId)));
    expect(ids, contains(NotificationProvider.snoozeActionId));
  });
}
