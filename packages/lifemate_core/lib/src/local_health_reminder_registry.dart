import 'local_health_store.dart';
import 'local_reminder_scheduler.dart';

/// Persists only non-content reminder execution metadata in the protected
/// local-health store. Notification title/body/payload are deliberately not
/// duplicated into this registry.
final class LifeMateLocalHealthReminderRegistry
    implements LifeMateReminderRegistry {
  LifeMateLocalHealthReminderRegistry({
    required LifeMateLocalHealthStore store,
    required LifeMateLocalNamespace namespace,
  }) : _store = store,
       _namespace = namespace;

  final LifeMateLocalHealthStore _store;
  final LifeMateLocalNamespace _namespace;

  @override
  Future<List<LifeMatePersistedReminder>> list() async {
    final records = await _store.listDomain(
      namespace: _namespace,
      domain: LifeMateLocalProjectionDomain.notificationSchedule,
    );
    final values = <LifeMatePersistedReminder>[];
    for (final record in records) {
      final payload = record.payload;
      final notificationId = int.tryParse(
        payload['notificationId']?.toString() ?? '',
      );
      final sourceRevision = int.tryParse(
        payload['sourceRevision']?.toString() ?? '',
      );
      final triggerUtc = DateTime.tryParse(
        payload['triggerUtc']?.toString() ?? '',
      );
      final rawAccuracy = payload['accuracy']?.toString();
      if (notificationId == null ||
          sourceRevision == null ||
          sourceRevision < 0 ||
          triggerUtc == null ||
          rawAccuracy == null) {
        throw const LifeMateLocalStoreCorruptionException();
      }
      final accuracy = switch (rawAccuracy) {
        'exact' => LifeMateReminderAccuracy.exact,
        'inexact' => LifeMateReminderAccuracy.inexact,
        _ => throw const LifeMateLocalStoreCorruptionException(),
      };
      values.add(
        LifeMatePersistedReminder(
          scheduleKey: record.recordKey,
          notificationId: notificationId,
          sourceRevision: sourceRevision,
          triggerUtc: triggerUtc.toUtc(),
          accuracy: accuracy,
        ),
      );
    }
    return List<LifeMatePersistedReminder>.unmodifiable(values);
  }

  @override
  Future<void> put(LifeMatePersistedReminder reminder) => _store.putProjection(
    namespace: _namespace,
    domain: LifeMateLocalProjectionDomain.notificationSchedule,
    recordKey: reminder.scheduleKey,
    sourceRevision: reminder.sourceRevision.toString(),
    payload: <String, dynamic>{
      'notificationId': reminder.notificationId,
      'sourceRevision': reminder.sourceRevision,
      'triggerUtc': reminder.triggerUtc.toUtc().toIso8601String(),
      'accuracy': reminder.accuracy.name,
    },
  );

  @override
  Future<void> delete(String scheduleKey) => _store.deleteProjection(
    namespace: _namespace,
    domain: LifeMateLocalProjectionDomain.notificationSchedule,
    recordKey: scheduleKey,
  );
}
