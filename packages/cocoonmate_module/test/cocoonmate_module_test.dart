import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

class FakeHost implements CocoonHostContract {
  FakeHost(this.entryState, this.locale, {this.pregnancySnapshot});

  @override
  CocoonEntryState entryState;
  @override
  Locale locale;
  @override
  String? personId = 'synthetic-person';
  @override
  CocoonPregnancySnapshot? offlinePregnancySnapshot;
  @override
  CocoonPregnancySnapshot? pregnancySnapshot;

  @override
  Future<void> beginPregnancySetup() async {}
  @override
  Future<void> openCommerce() async {}
  @override
  Future<void> openGlobalProfile() async {}
  @override
  Future<void> openLogin() async {}
  @override
  Future<void> refresh() async {}
  @override
  void recordSafeEvent(String name) {}
}

Widget appFor(FakeHost host) => MaterialApp(
      theme: CocoonTheme.light(),
      home: CocoonMateModule(config: CocoonModuleConfig(host: host)),
    );

void main() {
  testWidgets('module mounts under a host and uses Persian RTL', (
    tester,
  ) async {
    final host = FakeHost(CocoonEntryState.activePregnancy, const Locale('fa'));
    await tester.pumpWidget(appFor(host));

    expect(find.text('خانه'), findsOneWidget);
    final directionality = tester.widget<Directionality>(
      find
          .descendant(
            of: find.byType(CocoonMateModule),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
  });

  testWidgets('English LTR entitlement gate is deterministic', (tester) async {
    final host = FakeHost(CocoonEntryState.notEntitled, const Locale('en'));
    await tester.pumpWidget(appFor(host));

    expect(find.text('Choose access to CocoonMate'), findsOneWidget);
    expect(find.text('View options'), findsOneWidget);
  });

  testWidgets('protected owner snapshot keeps shell available while offline', (
    tester,
  ) async {
    final host = FakeHost(
      CocoonEntryState.offlineOwnerPregnancy,
      const Locale('en'),
    );
    await tester.pumpWidget(appFor(host));

    expect(find.text('Home'), findsOneWidget);
    expect(
      find.text('Last protected information saved on this device'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('large text does not require root navigator ownership', (
    tester,
  ) async {
    final host = FakeHost(CocoonEntryState.noPregnancy, const Locale('en'));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: appFor(host),
      ),
    );
    expect(find.text('No active pregnancy yet'), findsOneWidget);
  });

  testWidgets('home presents canonical gestational age and opens week detail', (
    tester,
  ) async {
    final host = FakeHost(
      CocoonEntryState.activePregnancy,
      const Locale('fa'),
      pregnancySnapshot: _pregnancyAtWeek(23, 4),
    );

    await tester.pumpWidget(appFor(host));

    expect(find.text('۲۳'), findsOneWidget);
    expect(find.text('هفته و ۴ روز'), findsOneWidget);
    await tester.tap(find.text('جزئیات این هفته را ببین'));
    await tester.pumpAndSettle();
    expect(find.text('هفته ۲۳'), findsOneWidget);
  });

  testWidgets('compact phone with large text keeps pregnancy home scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host = FakeHost(
      CocoonEntryState.activePregnancy,
      const Locale('en'),
      pregnancySnapshot: _pregnancyAtWeek(23, 4),
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: appFor(host),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomScrollView), findsOneWidget);
  });

  testWidgets('calendar presents gestational timeline without invented events',
      (
    tester,
  ) async {
    final host = FakeHost(
      CocoonEntryState.activePregnancy,
      const Locale('fa'),
      pregnancySnapshot: _pregnancyAtWeek(23, 4),
    );

    await tester.pumpWidget(appFor(host));
    await tester.tap(find.text('تقویم'));
    await tester.pumpAndSettle();

    expect(find.text('مسیر بارداری'), findsOneWidget);
    expect(find.text('هفته‌ی ۲۳ و روز ۴'), findsOneWidget);
    expect(find.text('برنامه‌ای ثبت نشده'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick check-in supports selection and external submission', (
    tester,
  ) async {
    CocoonCheckInDraft? submitted;
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: CocoonQuickCheckInScreen(
              fa: true,
              syncState: CocoonCheckInSyncState.idle,
              onSubmit: (draft) async => submitted = draft,
            ),
          ),
        ),
      ),
    );

    expect(find.text('یک مکث کوتاه برای خودت'), findsOneWidget);
    expect(find.text('ثبت حال امروز'), findsOneWidget);
    await tester.tap(find.text('آرام و خوب'));
    await tester.tap(find.text('معمولی'));
    await tester.pump();
    await tester.ensureVisible(find.text('ثبت حال امروز'));
    await tester.tap(find.text('ثبت حال امروز'));
    await tester.pump();

    expect(submitted?.feeling, CocoonCheckInFeeling.comfortable);
    expect(submitted?.energy, CocoonCheckInEnergy.steady);
  });

  testWidgets('queued check-in is not presented as server confirmed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Scaffold(
          body: CocoonQuickCheckInScreen(
            fa: false,
            syncState: CocoonCheckInSyncState.queued,
            onSubmit: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('Queued; not yet server-confirmed'), findsOneWidget);
    expect(find.text('Saved and server-confirmed'), findsNothing);
  });

  testWidgets('appointments distinguish cached pending-sync state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Scaffold(
          body: CocoonAppointmentsScreen(
            fa: true,
            offline: true,
            items: const [
              CocoonAppointmentViewData(
                id: 'appointment-1',
                title: 'ویزیت دوره‌ای',
                dateLabel: 'سه‌شنبه ۱۸ شهریور',
                timeLabel: '۱۶:۳۰',
                status: CocoonAppointmentStatus.pendingSync,
                cached: true,
              ),
            ],
            onAdd: _noop,
            onOpen: (_) {},
            onRetry: _noop,
          ),
        ),
      ),
    );

    expect(find.text('در انتظار همگام‌سازی'), findsOneWidget);
    expect(
      find.text('نسخه‌ی ذخیره‌شده؛ وضعیت آنلاین تأیید نشده'),
      findsOneWidget,
    );
    expect(find.text('پیش رو'), findsNothing);
  });

  testWidgets('appointments empty state has one clear add action', (
    tester,
  ) async {
    var requested = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Scaffold(
          body: CocoonAppointmentsScreen(
            fa: false,
            items: const [],
            onAdd: () => requested = true,
            onOpen: (_) {},
            onRetry: _noop,
          ),
        ),
      ),
    );

    expect(find.text('No appointments yet'), findsOneWidget);
    await tester.tap(find.text('Add appointment'));
    expect(requested, isTrue);
  });
}

void _noop() {}

CocoonPregnancySnapshot _pregnancyAtWeek(int week, int day) {
  final totalDays = week * 7 + day;
  return CocoonPregnancySnapshot(
    contractVersion: 1,
    episode: CocoonPregnancyEpisode(
      id: 'synthetic-episode',
      motherPersonId: 'synthetic-person',
      status: CocoonPregnancyEpisodeStatus.active,
      dating: CocoonPregnancyDating(
        method: null,
        lmpDate: null,
        estimatedDueDate: null,
        referenceDate: null,
        gestationalAgeAtReferenceDays: null,
        gestationalAge: CocoonGestationalAge(
          totalDays: totalDays,
          week: week,
          day: day,
          basis: 'server-derived',
        ),
      ),
      outcome: null,
      activatedAtUtc: null,
      endedAtUtc: null,
      version: 1,
      updatedAtUtc: null,
    ),
  );
}
