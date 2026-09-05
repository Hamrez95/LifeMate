import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/screens/treatments/care_event_form.dart';
import 'package:wellmate/screens/treatments/offline_care_event_create.dart';

void main() {
  test('only bounded transport failures are eligible for offline care-event queue', () {
    for (final code in <String>[
      'network_unavailable',
      'network_timeout',
      'retry_budget_exhausted',
    ]) {
      expect(
        canQueueCareEventCreateOffline(
          LifeMateApiException(statusCode: 0, code: code, message: 'offline'),
        ),
        isTrue,
      );
    }

    for (final error in <LifeMateApiException>[
      const LifeMateApiException(
        statusCode: 401,
        code: 'unauthorized',
        message: 'expired',
      ),
      const LifeMateApiException(
        statusCode: 403,
        code: 'forbidden',
        message: 'forbidden',
      ),
      const LifeMateApiException(
        statusCode: 409,
        code: 'idempotency_key_reused',
        message: 'conflict',
      ),
      const LifeMateApiException(
        statusCode: 400,
        code: 'invalid_eventType',
        message: 'invalid',
      ),
    ]) {
      expect(canQueueCareEventCreateOffline(error), isFalse);
    }
  });

  testWidgets('non-recurring appointment queues exact request after transient failure', (
    tester,
  ) async {
    final api = _CareEventApi(
      createError: const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'offline',
      ),
    );
    WellMateOfflineCareEventCreateRequest? queued;
    WellMateCareEventSaveState? saveState;
    var created = 0;

    await tester.pumpWidget(
      Provider<LifeMateApiClient>.value(
        value: api,
        child: MaterialApp(
          locale: const Locale('en'),
          home: Scaffold(
            body: CareEventForm(
              kind: CarePlanKind.appointment,
              onCreated: () => created += 1,
              offlineEnqueuer: (request) async => queued = request,
              onSaveStateChanged: (value) => saveState = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    expect(fields, findsWidgets);
    await tester.enterText(fields.at(0), 'Cardiology visit');
    await tester.enterText(fields.at(1), 'Dr Example');

    final submit = find.byKey(const ValueKey<String>('care-event-submit'));
    await tester.scrollUntilVisible(
      submit,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(submit, findsOneWidget);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(created, 1);
    expect(saveState, WellMateCareEventSaveState.pendingSync);
    expect(queued, isNotNull);
    expect(queued!.eventType, 'appointment');
    expect(queued!.title, 'Cardiology visit');
    expect(queued!.providerName, 'Dr Example');
    expect(queued!.medicationName, isNull);
    expect(queued!.doseText, isNull);
    expect(queued!.administrationRoute, isNull);
    expect(queued!.timeZone, 'Asia/Tehran');
    expect(queued!.scheduledLocalTime, matches(RegExp(r'^\d{2}:\d{2}$')));
    expect(queued!.clientRequestId, isNotEmpty);
  });

  testWidgets('authorization failure never enters offline enqueue path', (
    tester,
  ) async {
    final api = _CareEventApi(
      createError: const LifeMateApiException(
        statusCode: 403,
        code: 'forbidden',
        message: 'forbidden',
      ),
    );
    var enqueueCalls = 0;
    WellMateCareEventSaveState? saveState;

    await tester.pumpWidget(
      Provider<LifeMateApiClient>.value(
        value: api,
        child: MaterialApp(
          locale: const Locale('en'),
          home: Scaffold(
            body: CareEventForm(
              kind: CarePlanKind.appointment,
              onCreated: () {},
              offlineEnqueuer: (_) async => enqueueCalls += 1,
              onSaveStateChanged: (value) => saveState = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Cardiology visit');
    await tester.enterText(fields.at(1), 'Dr Example');
    final submit = find.byKey(const ValueKey<String>('care-event-submit'));
    await tester.scrollUntilVisible(
      submit,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(submit, findsOneWidget);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    // A server authorization denial must never be represented as locally
    // saved/pending and must never enter the durable offline queue.
    expect(enqueueCalls, 0);
    expect(saveState, isNull);
  });
}

class _CareEventApi extends LifeMateApiClient {
  _CareEventApi({required this.createError})
    : super(
        baseUri: Uri.parse('https://api.example.test'),
        accessToken: () => 'token',
      );

  final LifeMateApiException createError;

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => const {
    'profile': {'timeZone': 'Asia/Tehran'},
  };

  @override
  Future<List<Map<String, dynamic>>> getCareEvents({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> getTreatmentPlans() async =>
      const <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> createCareEvent({
    required String clientRequestId,
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
    RecurrenceRule recurrence = const RecurrenceRule.none(),
    int patientReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultPatientMinutes,
    int caregiverReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultCaregiverMinutes,
  }) async {
    throw createError;
  }
}
