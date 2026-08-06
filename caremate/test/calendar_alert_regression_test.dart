import 'package:caremate/core/localization/locale_provider.dart';
import 'package:caremate/main.dart';
import 'package:caremate/screens/calendar/calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'bell ignores yesterday skipped and today future scheduled doses',
    (WidgetTester tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
            Provider<LifeMateApiClient>.value(
              value: _AlertApiClient([
                {
                  'id': 'yesterday-skipped',
                  'medicationName': 'سیتریزین دیروز',
                  'doseText': 'یک قرص',
                  'scheduledLocalDate': _date(
                    now.subtract(const Duration(days: 1)),
                  ),
                  'scheduledLocalTime': '21:00',
                  'status': 'skipped',
                },
                {
                  'id': 'today-scheduled',
                  'medicationName': 'سیتریزین امشب',
                  'doseText': 'یک قرص',
                  'scheduledLocalDate': _date(now),
                  'scheduledLocalTime': '23:59',
                  'status': 'scheduled',
                },
              ]),
            ),
          ],
          child: const CareMateApp(home: CalendarScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('هشدارهای مراقبتی'));
      await tester.pump();

      expect(find.text('هشدار دارویی فعالی وجود ندارد.'), findsOneWidget);
      expect(find.text('هشدارهای دارویی امروز'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

class _AlertApiClient extends LifeMateApiClient {
  _AlertApiClient(this.doses)
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  final List<Map<String, dynamic>> doses;

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => {
    'user': {'id': 'caregiver-1'},
    'profile': {'displayName': 'مراقب تست'},
  };

  @override
  Future<List<Map<String, dynamic>>> getCareRelationships() async => [
    {
      'id': 'relationship-1',
      'status': 'active',
      'patientUserId': 'patient-1',
      'patientDisplayName': 'حمیدرضا',
      'caregiverUserId': 'caregiver-1',
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> getCareRecipientDoseOccurrences({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async => doses;

  @override
  Future<List<Map<String, dynamic>>> getCareRecipientCareEvents({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const [];
}
