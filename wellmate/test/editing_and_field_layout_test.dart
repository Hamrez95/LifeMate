import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/core/widgets/labeled_form_field.dart';
import 'package:wellmate/screens/treatments/add_treatment_screen.dart';
import 'package:wellmate/screens/treatments/edit_care_event_screen.dart';
import 'package:wellmate/screens/treatments/edit_treatment_screen.dart';

void main() {
  testWidgets('reminder labels are separate from their input boxes', (
    tester,
  ) async {
    await tester.pumpWidget(
      Provider<LifeMateApiClient>.value(
        value: _FakeLifeMateApiClient(),
        child: MaterialApp(
          locale: const Locale('fa'),
          home: Scaffold(body: TabbedAddTreatmentScreen(onCreated: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('یادآوری برای خودم'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('یادآوری برای خودم'), findsOneWidget);
    expect(find.text('یادآوری برای مراقب'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('یادآوری برای خودم'),
        matching: find.byType(WellMateLabeledField),
      ),
      findsOneWidget,
    );
    final floatingLabels = tester
        .widgetList<InputDecorator>(find.byType(InputDecorator))
        .map((widget) => widget.decoration.labelText)
        .whereType<String>();
    expect(floatingLabels, isNot(contains('یادآوری برای خودم')));
    expect(floatingLabels, isNot(contains('یادآوری برای مراقب')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('treatment edit submits optimistic versioned update', (
    tester,
  ) async {
    final editApi = _FakeEditApi();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: EditTreatmentScreen(editApi: editApi, plan: _treatmentPlan()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('save-treatment-edit')),
      700,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('save-treatment-edit')));
    await tester.pumpAndSettle();

    expect(editApi.treatmentUpdateCount, 1);
    expect(editApi.lastTreatmentVersion, 4);
    expect(editApi.lastMedicationVersion, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('appointment edit loads and saves real event fields', (
    tester,
  ) async {
    final editApi = _FakeEditApi();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: EditCareEventScreen(
          eventId: '11111111-1111-4111-8111-111111111111',
          editApi: editApi,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ویرایش ویزیت'), findsOneWidget);
    expect(find.text('دکتر سارا راد'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('save-care-event-edit')),
      700,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('save-care-event-edit')));
    await tester.pumpAndSettle();

    expect(editApi.careEventUpdateCount, 1);
    expect(editApi.lastCareEventVersion, 3);
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> _treatmentPlan() => {
  'id': '22222222-2222-4222-8222-222222222222',
  'version': 4,
  'status': 'active',
  'doseText': '۱ قرص',
  'instructions': 'بعد از غذا',
  'startDate': '2026-08-05',
  'endDate': null,
  'timeZone': 'Asia/Tehran',
  'patientReminderMinutesBefore': 30,
  'caregiverReminderMinutesBefore': 60,
  'medication': {
    'id': '33333333-3333-4333-8333-333333333333',
    'name': 'سیتریزین',
    'strengthText': '۱۰ میلی‌گرم',
    'form': 'tablet',
    'version': 2,
  },
  'schedules': [
    {'dayOfWeek': 'monday', 'localTime': '08:00'},
    {'dayOfWeek': 'wednesday', 'localTime': '20:00'},
  ],
};

class _FakeLifeMateApiClient extends LifeMateApiClient {
  _FakeLifeMateApiClient()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => const {
    'profile': {'timeZone': 'Asia/Tehran'},
  };
}

class _FakeEditApi extends LifeMateEditApi {
  _FakeEditApi()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  int treatmentUpdateCount = 0;
  int careEventUpdateCount = 0;
  int? lastTreatmentVersion;
  int? lastMedicationVersion;
  int? lastCareEventVersion;

  @override
  Future<Map<String, dynamic>> getCareEvent({required String eventId}) async =>
      const {
        'id': '11111111-1111-4111-8111-111111111111',
        'version': 3,
        'eventType': 'appointment',
        'status': 'scheduled',
        'title': 'ویزیت متخصص قلب',
        'providerName': 'دکتر سارا راد',
        'specialty': 'متخصص قلب',
        'reason': 'پیگیری',
        'centerName': 'کلینیک الوند',
        'addressLine': 'تهران',
        'phoneNumber': '02100000000',
        'instructions': 'آزمایش‌ها همراه باشد',
        'scheduledLocalDate': '2026-08-10',
        'scheduledLocalTime': '15:00',
        'timeZone': 'Asia/Tehran',
        'patientReminderMinutesBefore': 30,
        'caregiverReminderMinutesBefore': 60,
      };

  @override
  Future<Map<String, dynamic>> updateTreatmentPlan({
    required String treatmentPlanId,
    required int version,
    required int medicationVersion,
    required String medicationName,
    String? strengthText,
    String? form,
    required String doseText,
    String? instructions,
    required DateTime startDate,
    DateTime? endDate,
    required String timeZone,
    required List<Map<String, String>> schedules,
    required int patientReminderMinutesBefore,
    required int caregiverReminderMinutesBefore,
    required String status,
    String? clientRequestId,
  }) async {
    treatmentUpdateCount++;
    lastTreatmentVersion = version;
    lastMedicationVersion = medicationVersion;
    return {
      'id': treatmentPlanId,
      'version': version + 1,
      'medication': {'version': medicationVersion + 1},
    };
  }

  @override
  Future<Map<String, dynamic>> updateCareEvent({
    required String eventId,
    required int version,
    required String eventType,
    required String title,
    required DateTime scheduledLocalDate,
    required String scheduledLocalTime,
    required String timeZone,
    String? providerName,
    String? specialty,
    String? medicationName,
    String? doseText,
    String? administrationRoute,
    String? reason,
    String? instructions,
    String? centerName,
    String? addressLine,
    String? phoneNumber,
    required int patientReminderMinutesBefore,
    required int caregiverReminderMinutesBefore,
    required String status,
  }) async {
    careEventUpdateCount++;
    lastCareEventVersion = version;
    return {'id': eventId, 'version': version + 1};
  }
}
