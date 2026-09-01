import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

class _FakeLegalPrivacyApi extends LifeMateLegalPrivacyApi {
  _FakeLegalPrivacyApi({this.registrationCompleted = false})
      : super(
          baseUri: Uri.parse('https://example.test'),
          accessToken: () => 'token',
        );

  bool registrationCompleted;
  int acceptanceCalls = 0;
  final writes = <String, bool>{};

  static const requiredDocument = LifeMateLegalDocument(
    id: '11111111-1111-4111-8111-111111111111',
    purpose: 'legal_terms',
    version: '2026.08',
    title: 'شرایط استفاده LifeMate',
    documentHash: 'sha256:legal-document-hash-000001',
    contentUri: 'https://example.test/legal/terms',
    accepted: false,
  );

  @override
  Future<LifeMateRegistrationStatus> registrationStatus() async =>
      LifeMateRegistrationStatus(
        completed: registrationCompleted,
        registrationPolicyVersion:
            registrationCompleted ? 'legal_terms:2026.08' : null,
        requiredDocuments:
            registrationCompleted ? const [] : const [requiredDocument],
      );

  @override
  Future<LifeMateRegistrationStatus> acceptCurrentLegalDocuments(
    List<LifeMateLegalDocument> documents,
  ) async {
    acceptanceCalls += 1;
    registrationCompleted = true;
    return registrationStatus();
  }

  @override
  Future<List<LifeMatePrivacyPreference>> privacyPreferences() async => const [
        LifeMatePrivacyPreference(
          purpose: 'promotional_sms',
          category: 'Promotional',
          channel: 'SMS',
          policyVersion: 'v1',
          enabled: false,
          explicit: false,
          userMutable: true,
          description: 'Optional offers by SMS.',
        ),
        LifeMatePrivacyPreference(
          purpose: 'research',
          category: 'Research',
          channel: null,
          policyVersion: 'v1',
          enabled: false,
          explicit: false,
          userMutable: true,
          description: 'Optional research participation.',
        ),
      ];

  @override
  Future<void> setPrivacyPreference({
    required String purpose,
    required bool enabled,
  }) async {
    writes[purpose] = enabled;
  }
}

void main() {
  setUp(() => LifeMateRuntimeLocale.setLanguageCode('fa'));

  testWidgets('mandatory legal document is never prechecked', (tester) async {
    final api = _FakeLegalPrivacyApi();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: LifeMateLegalRegistrationGate(
          api: api,
          child: const Text('PRODUCT'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isFalse);
    expect(find.text('PRODUCT'), findsNothing);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('تأیید و ادامه'));
    await tester.pumpAndSettle();

    expect(api.acceptanceCalls, 1);
    expect(find.text('PRODUCT'), findsOneWidget);
  });

  testWidgets(
    'optional marketing and research preferences start off and mutate independently',
    (tester) async {
      final api = _FakeLegalPrivacyApi(registrationCompleted: true);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          home: LifeMatePrivacyPreferencesScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('پیشنهادها با پیامک'), findsOneWidget);
      expect(find.text('مشارکت در پژوهش'), findsOneWidget);
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches.every((item) => item.value == false), isTrue);

      await tester.tap(find.text('پیشنهادها با پیامک'));
      await tester.pumpAndSettle();

      expect(api.writes['promotional_sms'], isTrue);
      expect(api.writes.containsKey('research'), isFalse);
      expect(find.textContaining('پیام‌های ضروری'), findsOneWidget);
    },
  );
}
