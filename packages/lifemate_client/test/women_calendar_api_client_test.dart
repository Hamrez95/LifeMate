import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test(
    'women calendar episode edit sends owner-only correction payload',
    () async {
      late http.Request observed;
      final api = LifeMateApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'access-token',
        httpClient: MockClient((request) async {
          observed = request;
          return http.Response(
            jsonEncode({
              'id': 'episode-1',
              'startedOn': '2026-08-02',
              'endedOn': '2026-08-06',
              'privateNotes': 'یادداشت خصوصی اصلاح‌شده',
              'version': 4,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await api.updateWomenCalendarEpisode(
        episodeId: 'episode-1',
        version: 3,
        startedOn: DateTime(2026, 8, 2),
        endedOn: DateTime(2026, 8, 6),
        privateNotes: '  یادداشت خصوصی اصلاح‌شده  ',
      );

      expect(observed.method, 'PATCH');
      expect(observed.url.path, '/api/v1/women-calendar/episodes/episode-1');
      expect(observed.headers['authorization'], 'Bearer access-token');
      expect(jsonDecode(observed.body), {
        'version': 3,
        'startedOn': '2026-08-02',
        'endedOn': '2026-08-06',
        'privateNotes': 'یادداشت خصوصی اصلاح‌شده',
      });
      expect(result['version'], 4);
    },
  );

  test(
    'women calendar episode edit can reopen an episode and clear notes',
    () async {
      late http.Request observed;
      final api = LifeMateApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'access-token',
        httpClient: MockClient((request) async {
          observed = request;
          return http.Response(
            jsonEncode({
              'id': 'episode-1',
              'startedOn': '2026-08-02',
              'endedOn': null,
              'privateNotes': null,
              'version': 5,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await api.updateWomenCalendarEpisode(
        episodeId: 'episode-1',
        version: 4,
        startedOn: DateTime(2026, 8, 2),
        endedOn: null,
        privateNotes: '   ',
      );

      expect(jsonDecode(observed.body), {
        'version': 4,
        'startedOn': '2026-08-02',
        'endedOn': null,
        'privateNotes': null,
      });
    },
  );
}
