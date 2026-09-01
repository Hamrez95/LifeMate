import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

class _FakeOnboardingApi extends LifeMateAccountOnboardingApi {
  _FakeOnboardingApi(this.snapshot)
      : super(
          baseUri: Uri.parse('https://example.test'),
          accessToken: () => 'test-token',
        );

  LifeMateAccountOnboardingSnapshot snapshot;
  int completeCalls = 0;
  String? savedName;
  LifeMatePresentationIntent? savedIntent;

  @override
  Future<LifeMateAccountOnboardingSnapshot> getSnapshot() async => snapshot;

  @override
  Future<LifeMateAccountOnboardingSnapshot> complete({
    required LifeMateAccountOnboardingSnapshot current,
    required String displayName,
    required LifeMatePresentationIntent intent,
  }) async {
    completeCalls += 1;
    savedName = displayName.trim();
    savedIntent = intent;
    snapshot = LifeMateAccountOnboardingSnapshot(
      version: current.version + 1,
      displayName: savedName!,
      phoneNumber: current.phoneNumber,
      locale: current.locale,
      timeZone: current.timeZone,
      avatarKey: current.avatarKey,
      presentationIntent: intent,
      completed: true,
    );
    return snapshot;
  }
}

class _FakeLegalApi extends LifeMateLegalPrivacyApi {
  _FakeLegalApi({this.completed = true})
      : super(
          baseUri: Uri.parse('https://example.test'),
          accessToken: () => 'test-token',
        );

  bool completed;
  int acceptanceCalls = 0;

  LifeMateLegalDocument get document => const LifeMateLegalDocument(
        id: '11111111-1111-4111-8111-111111111111',
        purpose: 'legal_terms',
        version: 'v1',
        title: 'شرایط استفاده',
        documentHash: 'sha256:test-document-hash-0001',
        contentUri: 'https://example.test/terms',
        accepted: false,
      );

  @override
  Future<LifeMateRegistrationStatus> registrationStatus() async =>
      LifeMateRegistrationStatus(
        completed: completed,
        registrationPolicyVersion: completed ? 'legal_terms:v1' : null,
        requiredDocuments: completed ? const [] : [document],
      );

  @override
  Future<LifeMateRegistrationStatus> acceptCurrentLegalDocuments(
    List<LifeMateLegalDocument> documents,
  ) async {
    acceptanceCalls += 1;
    completed = true;
    return registrationStatus();
  }
}

LifeMateAccountOnboardingSnapshot _snapshot({required bool completed}) =>
    LifeMateAccountOnboardingSnapshot(
      version: 2,
      displayName: 'bootstrap-placeholder',
      phoneNumber: null,
      locale: 'fa',
      timeZone: 'Asia/Tehran',
      avatarKey: 'person_blue',
      presentationIntent: null,
      completed: completed,
    );

void main() {
  setUp(() => LifeMateRuntimeLocale.setLanguageCode('fa'));

  Future<void> configureView(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
  }

  Future<void> pumpGate(
    WidgetTester tester,
    _FakeOnboardingApi api, {
    _FakeLegalApi? legalApi,
    Size size = const Size(390, 844),
  }) async {
    await configureView(tester, size: size);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: LifeMateAccountOnboardingGate(
          api: api,
          legalPrivacyApi: legalApi ?? _FakeLegalApi(),
          enableDemographics: false,
          child: const Scaffold(body: Text('PRODUCT_HOME')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('completed existing user bypasses account onboarding when legal is current', (
    tester,
  ) async {
    final api = _FakeOnboardingApi(_snapshot(completed: true));
    await pumpGate(tester, api);

    expect(find.text('PRODUCT_HOME'), findsOneWidget);
    expect(find.text('نام نمایشی'), findsNothing);
    expect(api.completeCalls, 0);
  });

  testWidgets('completed account cannot enter product until current legal version is accepted', (
    tester,
  ) async {
    final api = _FakeOnboardingApi(_snapshot(completed: true));
    final legal = _FakeLegalApi(completed: false);
    await pumpGate(tester, api, legalApi: legal);

    expect(find.text('PRODUCT_HOME'), findsNothing);
    expect(find.text('شرایط استفاده'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('تأیید و ادامه'));
    await tester.pumpAndSettle();

    expect(legal.acceptanceCalls, 1);
    expect(find.text('PRODUCT_HOME'), findsOneWidget);
  });

  testWidgets('incomplete account uses two-step no-scroll flow with no birth year', (
    tester,
  ) async {
    final api = _FakeOnboardingApi(_snapshot(completed: false));
    await pumpGate(tester, api);

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('نام نمایشی'), findsOneWidget);
    expect(find.textContaining('سال تولد'), findsNothing);

    await tester.enterText(find.byType(TextField), 'حمید');
    await tester.tap(find.text('ادامه'));
    await tester.pumpAndSettle();

    expect(find.text('برای خودم'), findsOneWidget);
    expect(find.text('برای مراقبت از دیگری'), findsOneWidget);
    expect(find.text('هر دو'), findsOneWidget);
    expect(find.textContaining('هیچ دسترسی درمانی'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Both completes canonical account then enters product after legal gate', (
    tester,
  ) async {
    final api = _FakeOnboardingApi(_snapshot(completed: false));
    await pumpGate(tester, api);

    await tester.enterText(find.byType(TextField), 'حمید');
    await tester.tap(find.text('ادامه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('هر دو'));
    await tester.pump();
    await tester.tap(find.text('ورود به LifeMate'));
    await tester.pumpAndSettle();

    expect(api.completeCalls, 1);
    expect(api.savedName, 'حمید');
    expect(api.savedIntent, LifeMatePresentationIntent.both);
    expect(find.text('PRODUCT_HOME'), findsOneWidget);
  });

  testWidgets('representative smaller viewport stays no-scroll and buildable', (
    tester,
  ) async {
    final api = _FakeOnboardingApi(_snapshot(completed: false));
    await pumpGate(tester, api, size: const Size(360, 760));

    await tester.enterText(find.byType(TextField), 'کاربر');
    await tester.tap(find.text('ادامه'));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('هر دو'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
