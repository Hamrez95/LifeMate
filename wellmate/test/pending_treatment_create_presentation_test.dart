import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/screens/home/pending_treatment_create_presentation.dart';

void main() {
  test('projects exact bounded local dates and times without server IDs', () {
    final values = projectPendingTreatmentCreates(
      pendingCreates: <Map<String, dynamic>>[
        <String, dynamic>{
          'pendingSync': true,
          'clientRequestId': 'request-offline-1234',
          'doseText': '1 tablet',
          'startDate': '2026-09-05',
          'endDate': '2026-09-12',
          'recurrence': <String, dynamic>{'version': 2, 'enabled': false},
          'schedules': <Map<String, String>>[
            <String, String>{'dayOfWeek': 'saturday', 'localTime': '08:15'},
            <String, String>{'dayOfWeek': 'monday', 'localTime': '21:40'},
          ],
        },
      ],
      fromDate: DateTime(2026, 9, 5),
      toDate: DateTime(2026, 9, 12),
    );

    expect(values, hasLength(3));
    expect(values[0].localDate, DateTime(2026, 9, 5));
    expect(values[0].localTime, '08:15');
    expect(values[1].localDate, DateTime(2026, 9, 7));
    expect(values[1].localTime, '21:40');
    expect(values[2].localDate, DateTime(2026, 9, 12));
    expect(values[2].localTime, '08:15');
    expect(
      values.every(
        (value) => value.localPresentationKey.startsWith('local-pending:'),
      ),
      isTrue,
    );
    expect(
      values.every((value) => value.clientRequestId == 'request-offline-1234'),
      isTrue,
    );
  });

  test(
    'fails closed for malformed or server-like unsupported pending data',
    () {
      final values = projectPendingTreatmentCreates(
        pendingCreates: <Map<String, dynamic>>[
          <String, dynamic>{
            'pendingSync': false,
            'clientRequestId': 'request-offline-1234',
            'doseText': '1 tablet',
            'startDate': '2026-09-05',
            'recurrence': <String, dynamic>{'enabled': false},
            'schedules': <Map<String, String>>[
              <String, String>{'dayOfWeek': 'saturday', 'localTime': '08:15'},
            ],
          },
          <String, dynamic>{
            'pendingSync': true,
            'clientRequestId': 'request-offline-5678',
            'doseText': '1 tablet',
            'startDate': '2026-09-05',
            'recurrence': <String, dynamic>{'enabled': true},
            'schedules': <Map<String, String>>[
              <String, String>{'dayOfWeek': 'saturday', 'localTime': '08:15'},
            ],
          },
          <String, dynamic>{
            'pendingSync': true,
            'clientRequestId': 'request-offline-9012',
            'doseText': '1 tablet',
            'startDate': '2026-09-05',
            'recurrence': <String, dynamic>{'enabled': false},
            'schedules': <Map<String, String>>[
              <String, String>{'dayOfWeek': 'saturday', 'localTime': '25:00'},
            ],
          },
        ],
        fromDate: DateTime(2026, 9, 5),
        toDate: DateTime(2026, 9, 12),
      );

      expect(values, isEmpty);
    },
  );

  testWidgets('pending card is explicitly local and has no adherence actions', (
    tester,
  ) async {
    final occurrence = PendingTreatmentCreateOccurrence(
      localPresentationKey:
          'local-pending:request-offline-1234:2026-09-05:08:15',
      clientRequestId: 'request-offline-1234',
      localDate: DateTime(2026, 9, 5),
      localTime: '08:15',
      doseText: '1 tablet',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PendingTreatmentCreateCard(
            occurrence: occurrence,
            pendingCount: 1,
            font: TextStyle(),
            isPersian: false,
          ),
        ),
      ),
    );

    expect(find.text('Treatment saved on this device'), findsOneWidget);
    expect(find.text('Pending server sync'), findsOneWidget);
    expect(find.textContaining('1 tablet'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Taken'), findsNothing);
    expect(find.text('Skipped'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });
}
