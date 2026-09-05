import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/screens/treatments/edit_treatment_screen.dart';
import 'package:wellmate/screens/treatments/offline_treatment_edit.dart';

void main() {
  testWidgets('successful online treatment edit never queues an offline duplicate', (
    tester,
  ) async {
    final api = _FakeEditApi();
    var offlineCalls = 0;
    final saveStates = <WellMateTreatmentEditSaveState>[];

    await _openEditor(
      tester,
      editApi: api,
      offlineEnqueuer: (_) async => offlineCalls += 1,
      onSaveStateChanged: saveStates.add,
    );
    await _save(tester);

    expect(api.calls, 1);
    expect(api.lastClientRequestId, isNotNull);
    expect(api.lastClientRequestId, isNotEmpty);
    expect(offlineCalls, 0);
    expect(saveStates, <WellMateTreatmentEditSaveState>[
      WellMateTreatmentEditSaveState.serverConfirmed,
    ]);
    expect(find.text('changed:true'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'transient network failure queues the exact edit with the same idempotency key',
    (tester) async {
      final api = _FakeEditApi(
        error: const LifeMateApiException(
          statusCode: 0,
          code: 'network_unavailable',
          message: 'offline',
        ),
      );
      WellMateOfflineTreatmentEditRequest? queued;
      final saveStates = <WellMateTreatmentEditSaveState>[];

      await _openEditor(
        tester,
        editApi: api,
        offlineEnqueuer: (request) async => queued = request,
        onSaveStateChanged: saveStates.add,
      );
      await _save(tester);

      expect(api.calls, 1);
      expect(queued, isNotNull);
      expect(queued!.clientRequestId, api.lastClientRequestId);
      expect(queued!.treatmentPlanId, '22222222-2222-4222-8222-222222222222');
      expect(queued!.version, 4);
      expect(queued!.medicationVersion, 2);
      expect(queued!.medicationName, 'Cetirizine private');
      expect(queued!.strengthText, '10 mg');
      expect(queued!.form, 'tablet');
      expect(queued!.doseText, '1 tablet');
      expect(queued!.instructions, 'after food private');
      expect(queued!.startDate, DateTime(2026, 9, 5));
      expect(queued!.endDate, isNull);
      expect(queued!.timeZone, 'Asia/Tehran');
      expect(
        queued!.schedules,
        const <Map<String, String>>[
          <String, String>{'dayOfWeek': 'monday', 'localTime': '08:00'},
        ],
      );
      expect(queued!.patientReminderMinutesBefore, 30);
      expect(queued!.caregiverReminderMinutesBefore, 60);
      expect(queued!.status, 'active');
      expect(saveStates, <WellMateTreatmentEditSaveState>[
        WellMateTreatmentEditSaveState.pendingSync,
      ]);
      expect(find.text('changed:true'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final blocked in const <LifeMateApiException>[
    LifeMateApiException(
      statusCode: 401,
      code: 'invalid_session',
      message: 'unauthorized',
    ),
    LifeMateApiException(
      statusCode: 403,
      code: 'forbidden',
      message: 'forbidden',
    ),
    LifeMateApiException(
      statusCode: 409,
      code: 'stale_treatment_plan',
      message: 'conflict',
    ),
  ]) {
    testWidgets('status ${blocked.statusCode} never queues offline treatment edit', (
      tester,
    ) async {
      final api = _FakeEditApi(error: blocked);
      var offlineCalls = 0;
      final saveStates = <WellMateTreatmentEditSaveState>[];

      await _openEditor(
        tester,
        editApi: api,
        offlineEnqueuer: (_) async => offlineCalls += 1,
        onSaveStateChanged: saveStates.add,
      );
      await _save(tester, expectPop: false);

      expect(api.calls, 1);
      expect(offlineCalls, 0);
      expect(saveStates, isEmpty);
      expect(find.text('changed:null'), findsNothing);
      expect(find.byKey(const ValueKey('edit-treatment-form')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('offline enqueue failure stays open without a saved-state signal', (
    tester,
  ) async {
    final api = _FakeEditApi(
      error: const LifeMateApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'timeout',
      ),
    );

    final saveStates = <WellMateTreatmentEditSaveState>[];
    await _openEditor(
      tester,
      editApi: api,
      offlineEnqueuer: (_) async => throw StateError('runtime not adopted'),
      onSaveStateChanged: saveStates.add,
    );
    await _save(tester, expectPop: false);

    expect(saveStates, isEmpty);
    expect(find.byKey(const ValueKey('edit-treatment-form')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openEditor(
  WidgetTester tester, {
  required LifeMateEditApi editApi,
  required WellMateOfflineTreatmentEditEnqueuer offlineEnqueuer,
  required ValueChanged<WellMateTreatmentEditSaveState> onSaveStateChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      home: _EditorHost(
        editApi: editApi,
        offlineEnqueuer: offlineEnqueuer,
        onSaveStateChanged: onSaveStateChanged,
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-treatment-editor')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('edit-treatment-form')), findsOneWidget);
}

Future<void> _save(WidgetTester tester, {bool expectPop = true}) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('save-treatment-edit')),
    700,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.byKey(const ValueKey('save-treatment-edit')));
  await tester.pumpAndSettle();
  if (expectPop) {
    expect(find.text('changed:true'), findsOneWidget);
  }
}

class _EditorHost extends StatefulWidget {
  const _EditorHost({
    required this.editApi,
    required this.offlineEnqueuer,
    required this.onSaveStateChanged,
  });

  final LifeMateEditApi editApi;
  final WellMateOfflineTreatmentEditEnqueuer offlineEnqueuer;
  final ValueChanged<WellMateTreatmentEditSaveState> onSaveStateChanged;

  @override
  State<_EditorHost> createState() => _EditorHostState();
}

class _EditorHostState extends State<_EditorHost> {
  bool? changed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('changed:$changed'),
            FilledButton(
              key: const ValueKey('open-treatment-editor'),
              onPressed: () async {
                final value = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => EditTreatmentScreen(
                      plan: _plan(),
                      editApi: widget.editApi,
                      offlineEnqueuer: widget.offlineEnqueuer,
                      onSaveStateChanged: widget.onSaveStateChanged,
                    ),
                  ),
                );
                if (mounted) setState(() => changed = value);
              },
              child: const Text('open'),
            ),
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic> _plan() => <String, dynamic>{
  'id': '22222222-2222-4222-8222-222222222222',
  'version': 4,
  'status': 'active',
  'doseText': '1 tablet',
  'instructions': 'after food private',
  'startDate': '2026-09-05',
  'endDate': null,
  'timeZone': 'Asia/Tehran',
  'patientReminderMinutesBefore': 30,
  'caregiverReminderMinutesBefore': 60,
  'medication': <String, dynamic>{
    'id': '33333333-3333-4333-8333-333333333333',
    'name': 'Cetirizine private',
    'strengthText': '10 mg',
    'form': 'tablet',
    'version': 2,
  },
  'schedules': <Map<String, String>>[
    <String, String>{'dayOfWeek': 'monday', 'localTime': '08:00'},
  ],
};

class _FakeEditApi extends LifeMateEditApi {
  _FakeEditApi({this.error})
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  final LifeMateApiException? error;
  int calls = 0;
  String? lastClientRequestId;

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
    calls += 1;
    lastClientRequestId = clientRequestId;
    if (error != null) throw error!;
    return <String, dynamic>{
      'id': treatmentPlanId,
      'version': version + 1,
      'medication': <String, dynamic>{'version': medicationVersion + 1},
    };
  }
}
