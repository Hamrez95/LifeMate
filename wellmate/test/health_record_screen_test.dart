import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/screens/profile/health_record_screen.dart';

void main() {
  testWidgets('Health Record lists private documents and filters by category', (
    tester,
  ) async {
    await tester.pumpWidget(
      Provider<LifeMateApiClient>.value(
        value: _HealthRecordApi(),
        child: const MaterialApp(
          locale: Locale('fa'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: HealthRecordScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('پرونده سلامت'), findsOneWidget);
    expect(find.text('نسخه'), findsWidgets);
    expect(find.text('آزمایش'), findsWidgets);
    expect(
      find.byKey(const ValueKey('health-record-document-document-prescription')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('health-record-document-document-lab')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('health-record-filter-lab_result')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('health-record-document-document-prescription')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('health-record-document-document-lab')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _HealthRecordApi extends LifeMateApiClient {
  _HealthRecordApi()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<List<LifeMateHealthDocument>> getHealthDocuments() async => [
    LifeMateHealthDocument(
      id: 'document-prescription',
      contentType: 'application/pdf',
      byteSize: 900 * 1024,
      category: LifeMateHealthDocumentCategory.prescription,
      capturedOn: DateTime(2026, 9, 4),
      createdAtUtc: DateTime.utc(2026, 9, 5),
      links: const [
        {'contextType': 'treatment_plan', 'contextId': 'plan-id'},
      ],
      sourceProduct: 'wellmate',
    ),
    LifeMateHealthDocument(
      id: 'document-lab',
      contentType: 'image/jpeg',
      byteSize: 2 * 1024 * 1024,
      category: LifeMateHealthDocumentCategory.labResult,
      capturedOn: DateTime(2026, 9, 2),
      createdAtUtc: DateTime.utc(2026, 9, 3),
      links: const [],
      sourceProduct: 'wellmate',
    ),
  ];
}
