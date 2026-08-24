import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('completion claim uses scoped relationship mutation and returns items', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'completionNotifications': [
              {
                'sourceKey': 'adherence:event-1',
                'sourceEventId': 'event-1',
                'patientUserId': 'patient-1',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final items = await api.claimCareCompletionNotifications(
      relationshipId: 'relationship-1',
    );

    expect(observed.method, 'PATCH');
    expect(observed.headers['authorization'], 'Bearer access-token');
    expect(
      observed.url.path,
      '/api/v1/care/relationships/relationship-1/permissions',
    );
    expect(
      jsonDecode(observed.body),
      {'claimCompletionNotifications': true},
    );
    expect(items.single['sourceEventId'], 'event-1');
  });
}
