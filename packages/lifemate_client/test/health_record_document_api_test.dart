import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('Health Record uploads use raw bytes and narrow context headers', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': '018f5e6a-7e91-4c26-8e18-a83c5531d111',
            'contentType': 'image/jpeg',
            'byteSize': 4,
            'category': 'prescription',
            'capturedOn': '2026-09-05',
            'createdAtUtc': '2026-09-05T12:00:00.000Z',
            'links': [
              {
                'contextType': 'treatment_plan',
                'contextId': '118f5e6a-7e91-4c26-8e18-a83c5531d111',
              },
            ],
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final document = await api.uploadHealthDocument(
      bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0x00]),
      contentType: 'image/jpeg',
      category: LifeMateHealthDocumentCategory.prescription,
      capturedOn: DateTime(2026, 9, 5),
      contextType: LifeMateHealthDocumentContextType.treatmentPlan,
      contextId: '118f5e6a-7e91-4c26-8e18-a83c5531d111',
    );

    expect(observed.method, 'PUT');
    expect(observed.url.path, '/api/v1/health-record/documents');
    expect(observed.headers['authorization'], 'Bearer access-token');
    expect(observed.headers['content-type'], 'image/jpeg');
    expect(observed.headers['x-health-document-category'], 'prescription');
    expect(observed.headers['x-health-document-context-type'], 'treatment_plan');
    expect(observed.headers['x-health-document-context-id'],
        '118f5e6a-7e91-4c26-8e18-a83c5531d111');
    expect(observed.bodyBytes, Uint8List.fromList([0xff, 0xd8, 0xff, 0x00]));
    expect(document.category, LifeMateHealthDocumentCategory.prescription);
    expect(document.links.single['contextType'], 'treatment_plan');
  });

  test('Health Record context must be a complete pair', () async {
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((_) async => http.Response('', 500)),
    );

    await expectLater(
      api.uploadHealthDocument(
        bytes: Uint8List.fromList([1]),
        contentType: 'image/jpeg',
        category: LifeMateHealthDocumentCategory.other,
        contextType: LifeMateHealthDocumentContextType.careEvent,
      ),
      throwsArgumentError,
    );
  });
}
