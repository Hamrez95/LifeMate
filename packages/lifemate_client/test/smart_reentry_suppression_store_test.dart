import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('dismissal persists with cooldown and is isolated per account', () async {
    const storage = FlutterSecureStorage();
    final store = SmartReentrySuppressionStore(storage: storage);
    final now = DateTime(2026, 8, 29);

    await store.dismiss(
      accountId: 'owner-a',
      patternKey: 'appointment:dr-rad',
      now: now,
    );

    final ownerA = await store.read(accountId: 'owner-a');
    final ownerB = await store.read(accountId: 'owner-b');
    expect(ownerA, hasLength(1));
    expect(ownerA.single.blocks(now), isTrue);
    expect(ownerA.single.permanentlyMuted, isFalse);
    expect(ownerB, isEmpty);
  });

  test('permanent mute replaces prior cooldown for same pattern', () async {
    const storage = FlutterSecureStorage();
    final store = SmartReentrySuppressionStore(storage: storage);
    final now = DateTime(2026, 8, 29);

    await store.dismiss(
      accountId: 'owner-a',
      patternKey: 'injection:vitamin',
      now: now,
    );
    await store.mute(
      accountId: 'owner-a',
      patternKey: 'injection:vitamin',
    );

    final values = await store.read(accountId: 'owner-a');
    expect(values, hasLength(1));
    expect(values.single.permanentlyMuted, isTrue);
    expect(values.single.blocks(now.add(const Duration(days: 3650))), isTrue);
  });
}
