import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('phone invitation carries canonical type and owner nickname only', () async {
    late Map<String, dynamic> body;
    final api = LifeMateCareRelationshipInvitationApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/care/invitations');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 'invite-1', 'relationshipType': 'family'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.createPhoneInvitation(
      phone: '09121234567',
      relationshipType: 'family',
      caregiverDisplayName: 'مامان جون',
    );

    expect(body['relationshipType'], 'family');
    expect(body['displayName'], 'مامان جون');
    expect(body['confirmConsent'], true);
    expect(body.containsKey('canViewWomenCalendar'), false);
    expect(body.containsKey('permissions'), false);
    expect(body.containsKey('fertility'), false);
    api.close();
  });

  test('legacy type is canonicalized before transport', () async {
    late Map<String, dynamic> body;
    final api = LifeMateCareRelationshipInvitationApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 201);
      }),
    );

    await api.createPhoneInvitation(
      phone: '09121234567',
      relationshipType: 'child_caring_for_parent',
    );
    expect(body['relationshipType'], 'child');
    api.close();
  });

  test('preview uses token only and never accepts or requests health scopes', () async {
    late Map<String, dynamic> body;
    final api = LifeMateCareRelationshipInvitationApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/care/invitations/accept');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'inviterDisplayName': 'Hamidreza',
            'relationshipType': 'family',
          }),
          200,
        );
      }),
    );

    final preview = await api.preview(token: '1234567890');
    expect(body, {'token': '1234567890', 'previewOnly': true});
    expect(preview['inviterDisplayName'], 'Hamidreza');
    expect(body.containsKey('confirmConsent'), false);
    api.close();
  });
}
