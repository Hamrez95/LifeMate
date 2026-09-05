import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy snoozes are preserved by semantic reminder key across ID upgrades', () {
    final provider = File(
      'lib/providers/notification_provider.dart',
    ).readAsStringSync();

    expect(provider, contains('final preservedSnoozeKeys = <String>{};'));
    expect(provider, contains('preservedSnoozeKeys.add(target.key);'));
    expect(
      provider,
      contains('if (preservedSnoozeKeys.contains(itemKey)) continue;'),
      reason:
          'A snooze created with the pre-#830 notification ID must suppress the '
          'replacement reminder by semantic key, not only by its numeric ID.',
    );
    expect(
      provider,
      contains('preservedSnoozeIds.contains(request.id)'),
      reason:
          'The already-pending snooze itself must remain protected from stale '
          'pending-notification reconciliation.',
    );
  });
}
