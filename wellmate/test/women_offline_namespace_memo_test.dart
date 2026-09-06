import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';
import 'package:wellmate/screens/women_calendar/women_offline_namespace_memo.dart';

void main() {
  setUp(WomenOfflineNamespaceMemo.clearForTest);
  tearDown(WomenOfflineNamespaceMemo.clearForTest);

  test('reuses only the same authenticated account and environment', () {
    const environment = 'https://api.example.test';
    const legacyAccount = 'legacy-account-a';
    const namespace = LifeMateLocalNamespace(
      environmentId: environment,
      accountId: 'canonical-account-a',
      personId: 'person-a',
    );

    WomenOfflineNamespaceMemo.remember(
      legacyAccountId: legacyAccount,
      namespace: namespace,
    );

    expect(
      WomenOfflineNamespaceMemo.lookup(
        environmentId: environment,
        legacyAccountId: legacyAccount,
      ),
      same(namespace),
    );
    expect(
      WomenOfflineNamespaceMemo.lookup(
        environmentId: environment,
        legacyAccountId: 'legacy-account-b',
      ),
      isNull,
    );
    expect(
      WomenOfflineNamespaceMemo.lookup(
        environmentId: 'https://staging.example.test',
        legacyAccountId: legacyAccount,
      ),
      isNull,
    );
  });

  test('forget removes only the scoped authenticated identity', () {
    const environment = 'https://api.example.test';
    const first = LifeMateLocalNamespace(
      environmentId: environment,
      accountId: 'canonical-account-a',
      personId: 'person-a',
    );
    const second = LifeMateLocalNamespace(
      environmentId: environment,
      accountId: 'canonical-account-b',
      personId: 'person-b',
    );

    WomenOfflineNamespaceMemo.remember(
      legacyAccountId: 'legacy-account-a',
      namespace: first,
    );
    WomenOfflineNamespaceMemo.remember(
      legacyAccountId: 'legacy-account-b',
      namespace: second,
    );

    WomenOfflineNamespaceMemo.forget(
      environmentId: environment,
      legacyAccountId: 'legacy-account-a',
    );

    expect(
      WomenOfflineNamespaceMemo.lookup(
        environmentId: environment,
        legacyAccountId: 'legacy-account-a',
      ),
      isNull,
    );
    expect(
      WomenOfflineNamespaceMemo.lookup(
        environmentId: environment,
        legacyAccountId: 'legacy-account-b',
      ),
      same(second),
    );
  });

  test('rejects incomplete namespace identity', () {
    expect(
      () => WomenOfflineNamespaceMemo.remember(
        legacyAccountId: 'legacy-account-a',
        namespace: const LifeMateLocalNamespace(
          environmentId: 'https://api.example.test',
          accountId: '',
          personId: 'person-a',
        ),
      ),
      throwsArgumentError,
    );
  });
}
