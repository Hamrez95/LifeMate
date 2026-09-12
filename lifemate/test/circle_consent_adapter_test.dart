import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/app/lifemate_app.dart';
import 'package:lifemate/circle/api_camp_companion_selection_source.dart';
import 'package:lifemate/navigation/shell_navigation.dart';
import 'package:lifemate/shell/lifemate_shell.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  Map<String, dynamic> relationship({
    String id = 'r1',
    String viewerRole = 'caregiver',
    String name = 'Alex',
    String presentationType = 'family',
    String access = 'connected',
    bool eligible = true,
  }) => <String, dynamic>{
    'id': id,
    'viewerRole': viewerRole,
    'counterpartDisplayName': name,
    'presentationType': presentationType,
    'circleAccessPresentation': access,
    'campPresentationEligible': eligible,
    // Raw consent/account identifiers may coexist in the legacy response, but
    // the adapter intentionally does not consume or expose them.
    'patientConsentedAtUtc': '2026-09-01T10:00:00Z',
    'caregiverConsentedAtUtc': '2026-09-01T10:01:00Z',
    'patientUserId': 'legacy-patient-id',
  };

  late List<Map<String, dynamic>> rows;
  late LifeMateApiClient client;

  setUp(() {
    rows = <Map<String, dynamic>>[];
    client = LifeMateApiClient(
      baseUri: Uri.parse('https://lifemate.test'),
      accessToken: () => 'test-token',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/care/relationships');
        expect(request.headers['authorization'], 'Bearer test-token');
        return http.Response(
          jsonEncode(rows),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
  });

  tearDown(() => client.close());

  test('normalized connected relationship is eligible without raw consent inference', () async {
    rows = [relationship()];
    final source = ApiCampCompanionSelectionSource(
      apiClient: client,
      isPersian: false,
    );

    final snapshot = await source.load();

    expect(snapshot.candidates, hasLength(1));
    expect(snapshot.candidates.single.presentationId, 'care:r1');
    expect(snapshot.candidates.single.displayName, 'Alex');
    expect(snapshot.candidates.single.relationshipLabel, 'Family');
    expect(snapshot.candidates.single.isEligible, isTrue);
    expect(snapshot.candidates.single.ineligibleReason, isNull);
  });

  test('permission-required and revoked states remain visible but ineligible', () async {
    rows = [
      relationship(
        id: 'pending',
        access: 'permission_required',
        eligible: false,
      ),
      relationship(
        id: 'revoked',
        name: 'Sam',
        access: 'access_unavailable',
        eligible: false,
      ),
    ];
    final source = ApiCampCompanionSelectionSource(
      apiClient: client,
      isPersian: false,
    );

    final snapshot = await source.load();

    expect(snapshot.candidates, hasLength(2));
    expect(snapshot.candidates[0].isEligible, isFalse);
    expect(snapshot.candidates[0].ineligibleReason, 'Permission required');
    expect(snapshot.candidates[1].isEligible, isFalse);
    expect(snapshot.candidates[1].ineligibleReason, 'Access unavailable');
  });

  test('revocation or person switch removes stale Camp selection', () async {
    rows = [relationship()];
    final source = ApiCampCompanionSelectionSource(
      apiClient: client,
      isPersian: false,
    );

    await source.setSelectedPresentationIds({'care:r1'});
    expect((await source.load()).selectedPresentationIds, {'care:r1'});

    rows = [
      relationship(access: 'access_unavailable', eligible: false),
    ];
    expect((await source.load()).selectedPresentationIds, isEmpty);

    rows = <Map<String, dynamic>>[];
    expect((await source.load()).selectedPresentationIds, isEmpty);
  });

  test('cross-user or unknown viewer role fails closed', () async {
    rows = [relationship(viewerRole: 'unknown')];
    final source = ApiCampCompanionSelectionSource(
      apiClient: client,
      isPersian: false,
    );

    expect((await source.load()).candidates, isEmpty);
    await expectLater(
      source.setSelectedPresentationIds({'care:r1'}),
      throwsA(isA<StateError>()),
    );
  });

  test('server eligibility and configured capacity are revalidated on mutation', () async {
    rows = [relationship(id: 'a'), relationship(id: 'b', name: 'Sam')];
    final source = ApiCampCompanionSelectionSource(
      apiClient: client,
      isPersian: false,
      capacity: 1,
    );

    await expectLater(
      source.setSelectedPresentationIds({'care:a', 'care:b'}),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      source.setSelectedPresentationIds({'care:foreign'}),
      throwsA(isA<StateError>()),
    );
  });

  test('relationship labels localize without changing stable presentation IDs', () async {
    rows = [relationship(presentationType: 'partner')];
    final source = ApiCampCompanionSelectionSource(
      apiClient: client,
      isPersian: true,
    );

    var snapshot = await source.load();
    expect(snapshot.candidates.single.presentationId, 'care:r1');
    expect(snapshot.candidates.single.relationshipLabel, 'پارتنر');

    source.updateLocale(isPersian: false);
    snapshot = await source.load();
    expect(snapshot.candidates.single.presentationId, 'care:r1');
    expect(snapshot.candidates.single.relationshipLabel, 'Partner');
  });

  testWidgets('production shell mounts API-backed Circle source', (tester) async {
    rows = [relationship(name: 'Live Alex')];

    await tester.pumpWidget(
      LifeMateApp(
        localeOverride: const Locale('en'),
        home: LifeMateShell(
          apiClient: client,
          initialDestination: ShellDestination.circle,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Camp companions'), findsOneWidget);
    expect(find.text('Live Alex'), findsOneWidget);
    expect(
      find.text('Preview data — not live relationship or consent state'),
      findsNothing,
    );
  });
}
