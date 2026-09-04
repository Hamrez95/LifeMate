import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('bootstrap keeps enrollment and entitlement separate', () {
    final value = CocoonBootstrapSnapshot.fromJson({
      'contractVersion': 1,
      'subject': {'personId': 'person-secret'},
      'enrollmentState': 'active',
      'entitlementState': {'state': 'inactive', 'reference': null},
      'activeEpisode': null,
      'runtime': {
        'serverAuthoritativeSharing': true,
        'serverAuthoritativeEntitlementActivation': true,
        'cachedOwnerSnapshotAllowed': true,
        'cachedSharedSnapshotAllowed': false,
      },
      'futureField': {'safeToIgnore': true},
    });

    expect(value.enrollmentState, CocoonEnrollmentState.active);
    expect(value.entitlement.state, CocoonEntitlementState.inactive);
    expect(value.cachedOwnerSnapshotAllowed, isTrue);
    expect(value.cachedSharedSnapshotAllowed, isFalse);
  });

  test('DTO parsing is backward compatible with missing optional fields', () {
    final value = CocoonPregnancyEpisode.fromJson({
      'id': 'episode-secret',
      'motherPersonId': 'person-secret',
      'status': 'active',
      'dating': {'method': 'lmp'},
      'version': 2,
    });

    expect(value.status, CocoonPregnancyEpisodeStatus.active);
    expect(value.dating.estimatedDueDate, isNull);
    expect(value.updatedAtUtc, isNull);
  });

  test('diagnostics redact reproductive dates and identifiers', () {
    final value = CocoonPregnancyEpisode.fromJson({
      'id': 'episode-secret',
      'motherPersonId': 'person-secret',
      'status': 'active',
      'dating': {
        'method': 'lmp',
        'lmpDate': '2026-07-01',
        'estimatedDueDate': '2027-04-07',
      },
      'version': 1,
    });

    final episodeText = value.toString();
    final datingText = value.dating.toString();
    expect(episodeText, isNot(contains('episode-secret')));
    expect(episodeText, isNot(contains('person-secret')));
    expect(datingText, isNot(contains('2026-07-01')));
    expect(datingText, isNot(contains('2027-04-07')));
  });
}
