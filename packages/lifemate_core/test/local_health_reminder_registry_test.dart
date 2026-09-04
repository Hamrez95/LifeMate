import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('notification registry reuses encrypted shared health store', () async {
    final database = sqlite3.openInMemory();
    final store = LifeMateLocalHealthStore.forTesting(
      database: database,
      keyBytes: List<int>.generate(32, (index) => index + 1),
    );
    final namespace = LifeMateLocalNamespace(
      environmentId: 'prod',
      accountId: 'account-1',
      personId: 'person-1',
    );
    final registry = LifeMateLocalHealthReminderRegistry(
      store: store,
      namespace: namespace,
    );
    final reminder = LifeMatePersistedReminder(
      scheduleKey: 'opaque-occurrence@r4',
      notificationId: 991,
      sourceRevision: 4,
      triggerUtc: DateTime.utc(2026, 9, 6, 8),
      accuracy: LifeMateReminderAccuracy.exact,
    );

    await registry.put(reminder);
    final loaded = await registry.list();

    expect(loaded, hasLength(1));
    expect(loaded.single.scheduleKey, reminder.scheduleKey);
    expect(loaded.single.notificationId, reminder.notificationId);
    expect(loaded.single.sourceRevision, 4);
    expect(loaded.single.triggerUtc, reminder.triggerUtc);
    expect(loaded.single.accuracy, LifeMateReminderAccuracy.exact);

    final raw =
        database
                .select(
                  'SELECT ciphertext FROM lifemate_local_projection_records',
                )
                .single['ciphertext']
            as List<int>;
    expect(String.fromCharCodes(raw), isNot(contains('opaque-occurrence')));
    expect(String.fromCharCodes(raw), isNot(contains('Private reminder')));

    await registry.delete(reminder.scheduleKey);
    expect(await registry.list(), isEmpty);
    store.close();
  });
}
