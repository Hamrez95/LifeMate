import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test(
    'bootstrap keeps application, pregnancy and Commerce state separate',
    () {
      final value = CocoonBootstrapSnapshot.fromJson({
        'contractVersion': 1,
        'subject': {'personId': 'person-secret'},
        'enrollmentState': 'active',
        'entitlementState': {'state': 'inactive', 'reference': null},
        'applicationState': {
          'availability': 'available',
          'enrollmentState': 'active',
        },
        'commerceEligibility': {
          'state': 'conversion_eligible',
          'offerAvailable': false,
          'conversionEligible': true,
        },
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
      expect(
        value.application.availability,
        CocoonApplicationAvailability.available,
      );
      expect(
        value.application.enrollmentState,
        CocoonApplicationEnrollmentState.active,
      );
      expect(
        value.commerceEligibility.state,
        CocoonCommerceEligibilityState.conversionEligible,
      );
      expect(value.commerceEligibility.conversionEligible, isTrue);
      expect(value.cachedOwnerSnapshotAllowed, isTrue);
      expect(value.cachedSharedSnapshotAllowed, isFalse);
    },
  );

  test(
    'bootstrap stays backward compatible when additive fields are missing',
    () {
      final value = CocoonBootstrapSnapshot.fromJson({
        'contractVersion': 1,
        'subject': {'personId': 'person-secret'},
        'enrollmentState': 'not_enrolled',
        'entitlementState': {'state': 'unknown'},
        'activeEpisode': null,
        'runtime': const <String, dynamic>{},
      });

      expect(
        value.application.availability,
        CocoonApplicationAvailability.unknown,
      );
      expect(
        value.application.enrollmentState,
        CocoonApplicationEnrollmentState.unknown,
      );
      expect(
        value.commerceEligibility.state,
        CocoonCommerceEligibilityState.unknown,
      );
    },
  );

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

  test('calendar read uses the episode-scoped Cocoon endpoint', () async {
    late http.Request observed;
    final client = CocoonPregnancyApiClient(
      baseUri: Uri.parse('https://api.example.test/functions/v1/lifemate-api'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'contractVersion': 1,
            'episodeId': 'episode-1',
            'careEvents': [
              {
                'id': 'event-1',
                'seriesId': 'event-1',
                'title': 'Prenatal visit',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final snapshot = await client.getCalendar(
      fromDate: DateTime(2026, 9, 1),
      toDate: DateTime(2026, 9, 30),
    );

    expect(observed.method, 'GET');
    expect(observed.url.path, contains('/api/v1/cocoon/pregnancy/calendar'));
    expect(observed.url.queryParameters['fromDate'], '2026-09-01');
    expect(observed.url.queryParameters['toDate'], '2026-09-30');
    expect(snapshot.episodeId, 'episode-1');
    expect(snapshot.careEvents.single['seriesId'], 'event-1');
    client.close();
  });

  test('care event link is idempotency protected', () async {
    late http.Request observed;
    final client = CocoonPregnancyApiClient(
      baseUri: Uri.parse('https://api.example.test/functions/v1/lifemate-api'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'contractVersion': 1,
            'episodeId': 'episode-1',
            'careEventId': '11111111-1111-4111-8111-111111111111',
            'linked': true,
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await client.linkCareEvent(
      careEventId: '11111111-1111-4111-8111-111111111111',
      idempotencyKey: 'calendar-link-request-1',
    );

    expect(observed.method, 'POST');
    expect(
      observed.url.path,
      contains(
        '/api/v1/cocoon/pregnancy/care-events/11111111-1111-4111-8111-111111111111/link',
      ),
    );
    expect(observed.headers['idempotency-key'], 'calendar-link-request-1');
    client.close();
  });
}
