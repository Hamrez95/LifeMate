import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('presentation update uses dedicated route and contains no permission fields', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'id': '00000000-0000-4000-8000-000000000001',
          'presentationType': 'child_caring_for_parent',
          'patientDisplayName': 'Mum',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = LifeMateRelationshipPresentationApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: client,
    );

    await api.update(
      relationshipId: '00000000-0000-4000-8000-000000000001',
      relationshipType: 'child_caring_for_parent',
      displayName: ' Mum ',
    );

    expect(captured.method, 'PATCH');
    expect(
      captured.url.path,
      '/api/v1/care/relationships/00000000-0000-4000-8000-000000000001/presentation',
    );
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body, {
      'relationshipType': 'child_caring_for_parent',
      'displayName': 'Mum',
    });
    expect(body.keys.join(' ').toLowerCase(), isNot(contains('permission')));
    expect(body.keys.join(' ').toLowerCase(), isNot(contains('consent')));
    expect(
      captured.headers.entries.any(
        (entry) =>
            entry.key.toLowerCase() == 'idempotency-key' &&
            entry.value.isNotEmpty,
      ),
      isTrue,
    );
    api.close();
  });

  test('blank alias is intentionally cleared to null', () async {
    late Map<String, dynamic> body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{}', 200);
    });
    final api = LifeMateRelationshipPresentationApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: client,
    );

    await api.update(
      relationshipId: '00000000-0000-4000-8000-000000000001',
      relationshipType: 'unknown',
      displayName: '   ',
    );

    expect(body['displayName'], isNull);
    api.close();
  });
}
