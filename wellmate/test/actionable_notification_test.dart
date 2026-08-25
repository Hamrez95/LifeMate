import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/providers/notification_provider.dart';

void main() {
  test('action payload round-trips mutation identity and version', () {
    const target = WellMateNotificationTarget(
      type: 'medicine',
      id: 'dose-occurrence-1',
      version: 4,
      clientRequestId: '123e4567-e89b-12d3-a456-426614174000',
      isPersian: false,
    );

    final payload = NotificationProvider.encodeActionPayload(target);
    final decoded = NotificationProvider.decodeActionPayload(payload);

    expect(decoded, isNotNull);
    expect(decoded!.type, target.type);
    expect(decoded.id, target.id);
    expect(decoded.version, target.version);
    expect(decoded.clientRequestId, target.clientRequestId);
  });

  test('medicine notification exposes taken, snooze and open actions', () {
    const target = WellMateNotificationTarget(
      type: 'medicine',
      id: 'dose-1',
      version: 1,
      clientRequestId: 'request-1',
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

  test('single care event exposes completion action', () {
    const target = WellMateNotificationTarget(
      type: 'appointment',
      id: 'event-1',
      seriesId: 'event-1',
      version: 2,
      clientRequestId: 'request-2',
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
      id: 'event-1:2026-08-26',
      seriesId: 'event-1',
      version: 2,
      clientRequestId: 'request-3',
      isPersian: false,
    );
    expect(target.isRecurringCareInstance, isTrue);
    final ids = NotificationProvider.actionButtonsForTarget(target)
        .map((action) => action.id)
        .toList();
    expect(ids, isNot(contains(NotificationProvider.completedActionId)));
    expect(ids, contains(NotificationProvider.snoozeActionId));
  });

  test('invalid or legacy payload fails closed', () {
    expect(NotificationProvider.decodeActionPayload(null), isNull);
    expect(NotificationProvider.decodeActionPayload('dose:legacy'), isNull);
    expect(
      NotificationProvider.decodeActionPayload('lifemate-reminder:not-base64'),
      isNull,
    );
  });
}
