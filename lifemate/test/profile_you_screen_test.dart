import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/app/lifemate_app.dart';
import 'package:lifemate/shell/lifemate_shell.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  setUp(LifeMateProfileRefresh.clearCacheForTesting);

  testWidgets('You loads canonical profile and saves permitted fields', (
    tester,
  ) async {
    final requests = <http.Request>[];
    var profile = <String, dynamic>{
      'id': 'profile-1',
      'userId': 'user-1',
      'displayName': 'Owner',
      'phoneNumber': null,
      'email': 'owner@example.test',
      'locale': 'en',
      'timeZone': 'Europe/Berlin',
      'avatarKey': 'person_green',
      'profilePhotoUrl': null,
      'version': 3,
    };
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET' &&
            request.url.path == '/api/v1/me/profile') {
          return http.Response(
            jsonEncode(profile),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'PATCH' &&
            request.url.path == '/api/v1/me/profile') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          profile = <String, dynamic>{...profile, ...body, 'version': 4};
          return http.Response(
            jsonEncode(profile),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      LifeMateApp(
        home: LifeMateShell(apiClient: api),
        localeOverride: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('You'));
    await tester.pumpAndSettle();

    expect(find.text('Owner'), findsWidgets);
    expect(find.text('Europe/Berlin'), findsOneWidget);
    expect(find.text('Membership'), findsOneWidget);
    expect(find.text('Ambient audio'), findsOneWidget);
    expect(
      find.textContaining('durable preference is not available'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();

    final nameField = find.widgetWithText(TextFormField, 'Owner');
    expect(nameField, findsOneWidget);
    await tester.enterText(nameField, 'Updated Owner');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Updated Owner'), findsWidgets);
    final patch = requests.lastWhere((request) => request.method == 'PATCH');
    expect(jsonDecode(patch.body), {
      'version': 3,
      'displayName': 'Updated Owner',
      'phoneNumber': null,
      'locale': 'en',
      'timeZone': 'Europe/Berlin',
      'avatarKey': 'person_green',
    });
  });

  testWidgets('Persian You remains RTL and exposes retry on profile failure', (
    tester,
  ) async {
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      httpClient: MockClient((request) async => http.Response('{}', 503)),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      LifeMateApp(
        home: LifeMateShell(apiClient: api),
        localeOverride: const Locale('fa'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('شما'));
    await tester.pumpAndSettle();

    final directionality = tester.widget<Directionality>(
      find.byType(Directionality).first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
    expect(find.text('پروفایل در دسترس نیست'), findsOneWidget);
    expect(find.text('تلاش دوباره'), findsOneWidget);
  });
}
