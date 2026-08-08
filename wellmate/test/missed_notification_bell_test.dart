import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/core/widgets/wellmate_app_header.dart';
import 'package:wellmate/models/schedule_item_model.dart';
import 'package:wellmate/providers/medication_provider.dart';
import 'package:wellmate/providers/notification_provider.dart';

void main() {
  setUp(LifeMateProfileRefresh.clearCacheForTesting);
  tearDown(LifeMateProfileRefresh.clearCacheForTesting);

  testWidgets('missed doctor visit appears in the notification bell', (
    tester,
  ) async {
    final provider = MedicationProvider()
      ..setScheduleItems([
        _item(
          id: 'visit-1',
          type: 'appointment',
          title: 'ویزیت دکتر قلب',
          status: 'missed',
        ),
      ]);

    var completed = false;
    await _pumpHeader(
      tester,
      provider,
      reporter: (item) async {
        completed = item.id == 'visit-1';
        return true;
      },
    );
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();

    expect(find.text('اعلان‌های انجام‌نشده'), findsOneWidget);
    expect(find.text('ویزیت دکتر قلب'), findsOneWidget);
    expect(find.text('انجام شد'), findsOneWidget);
    expect(find.text('انجام نشد'), findsNothing);
    expect(find.text('مصرف کردم'), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    await tester.tap(find.text('انجام شد'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(provider.missedItems, isEmpty);
    expect(
      find.text('هیچ دارو، ویزیت یا تزریق انجام‌نشده‌ای وجود ندارد.'),
      findsNothing,
    );
  });

  testWidgets('missed medicine and doctor visit are shown together', (
    tester,
  ) async {
    final provider = MedicationProvider()
      ..setScheduleItems([
        _item(
          id: 'dose-1',
          type: 'medicine',
          title: 'آسپرین',
          status: 'missed',
          dosage: '۱ قرص',
        ),
        _item(
          id: 'visit-1',
          type: 'appointment',
          title: 'ویزیت دکتر قلب',
          status: 'missed',
        ),
      ]);

    await _pumpHeader(tester, provider);
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();

    expect(find.text('آسپرین'), findsOneWidget);
    expect(find.text('ویزیت دکتر قلب'), findsOneWidget);
    expect(find.text('مصرف کردم'), findsOneWidget);
    expect(find.text('انجام شد'), findsOneWidget);
    expect(find.text('انجام نشد'), findsNothing);
  });

  testWidgets('empty bell uses a generic care empty state', (tester) async {
    await _pumpHeader(tester, MedicationProvider());
    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pumpAndSettle();

    expect(
      find.text('هیچ دارو، ویزیت یا تزریق انجام‌نشده‌ای وجود ندارد.'),
      findsOneWidget,
    );
    expect(find.text('هیچ داروی فراموش شده‌ای وجود ندارد.'), findsNothing);
  });

  test('completed and cancelled care events are not missed', () {
    final provider = MedicationProvider()
      ..setScheduleItems([
        _item(
          id: 'visit-completed',
          type: 'appointment',
          title: 'ویزیت انجام‌شده',
          status: 'completed',
          isDone: true,
        ),
        _item(
          id: 'visit-cancelled',
          type: 'appointment',
          title: 'ویزیت لغوشده',
          status: 'cancelled',
          isDone: true,
        ),
      ]);

    expect(provider.missedItems, isEmpty);
  });
}

Future<void> _pumpHeader(
  WidgetTester tester,
  MedicationProvider medicationProvider, {
  MissedMedicationReporter? reporter,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<LifeMateApiClient>.value(value: _FakeLifeMateApiClient()),
        ChangeNotifierProvider<MedicationProvider>.value(
          value: medicationProvider,
        ),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        locale: const Locale('fa'),
        home: Scaffold(
          body: WellMateAppHeader(
            onProfileTap: () {},
            onMissedMedicationTaken: reporter,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScheduleItemModel _item({
  required String id,
  required String type,
  required String title,
  required String status,
  String dosage = '',
  bool isDone = false,
}) {
  final now = DateTime.now();
  return ScheduleItemModel(
    id: id,
    type: type,
    title: title,
    time: '08:00',
    dosage: dosage,
    status: status,
    isDone: isDone,
    frequency: type == 'medicine' ? 'روزانه' : 'ویزیت',
    startDate: DateTime(now.year, now.month, now.day),
    scheduledAtUtc: now.subtract(const Duration(hours: 1)).toUtc(),
  );
}

class _FakeLifeMateApiClient extends LifeMateApiClient {
  _FakeLifeMateApiClient()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> getCurrentProfile() async => const {
    'displayName': 'کاربر تست',
    'avatarKey': 'person_green',
    'profilePhotoUrl': null,
  };
}
