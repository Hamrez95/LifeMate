import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  setUpAll(_loadCocoonFont);

  testWidgets('Persian populated calendar is semantic and stable at 390x844', (
    tester,
  ) async {
    _useGoldenTolerance();
    await _setViewport(tester, const Size(390, 844));
    var selectedWeek = 0;
    var openedItem = '';
    await tester.pumpWidget(
      _screen(
        fa: true,
        child: CocoonPregnancyCalendar(
          host: _CalendarHost(snapshot: _pregnancyAtWeek(24, 3)),
          fa: true,
          state: CocoonCalendarLoadState.populated,
          asOfLocalDate: DateTime(2026, 9, 9),
          items: _items,
          onOpenWeek: (week) => selectedWeek = week,
          onOpenItem: (item) => openedItem = item.id,
        ),
      ),
    );

    expect(find.text('برنامه‌ی مراقبت'), findsOneWidget);
    expect(find.text('ویزیت بعدی'), findsOneWidget);
    expect(find.text('۲۳'), findsOneWidget);
    await tester.tap(find.text('۲۳'));
    await tester.tap(find.text('ویزیت بعدی'));
    await tester.pumpAndSettle();
    expect(selectedWeek, 23);
    expect(openedItem, 'appointment-1');
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('calendar-visual-screen')),
      matchesGoldenFile('goldens/cocoon_calendar_fa_populated_390x844.png'),
    );
  });

  testWidgets('English cached calendar is clear at reference viewport', (
    tester,
  ) async {
    _useGoldenTolerance();
    await _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      _screen(
        fa: false,
        child: CocoonPregnancyCalendar(
          host: _CalendarHost(snapshot: _pregnancyAtWeek(24, 3)),
          fa: false,
          state: CocoonCalendarLoadState.offlineCached,
          asOfLocalDate: DateTime(2026, 9, 9),
          items: _englishItems,
        ),
      ),
    );

    expect(find.text('Showing the last saved device copy'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('calendar-visual-screen')),
      matchesGoldenFile('goldens/cocoon_calendar_en_offline_390x844.png'),
    );
  });

  testWidgets('Calendar handles small Persian phone and large text', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 568));
    await tester.pumpWidget(
      _screen(
        fa: true,
        textScale: 1.5,
        child: CocoonPregnancyCalendar(
          host: _CalendarHost(snapshot: _pregnancyAtWeek(24, 3)),
          fa: true,
          state: CocoonCalendarLoadState.partial,
          items: _items,
        ),
      ),
    );

    expect(find.text('سه‌ماهه اول'), findsOneWidget);
    expect(find.text('سه‌ماهه دوم'), findsOneWidget);
    expect(find.text('سه‌ماهه سوم'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('بخش دیگری از برنامه پس از همگام‌سازی نمایش داده می‌شود.'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Calendar error exposes a retry action', (tester) async {
    await _setViewport(tester, const Size(390, 844));
    var retried = false;
    await tester.pumpWidget(
      _screen(
        fa: false,
        child: CocoonPregnancyCalendar(
          host: _CalendarHost(),
          fa: false,
          state: CocoonCalendarLoadState.error,
          onRetry: () => retried = true,
        ),
      ),
    );

    final retry = find.text('Try again');
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    expect(retried, isTrue);
    expect(tester.takeException(), isNull);
  });
}

const _items = [
  CocoonCalendarItem(
    id: 'appointment-1',
    title: 'ویزیت بعدی',
    dateLabel: '۲۲ شهریور',
    timeLabel: '۱۶:۳۰',
    supporting: 'مرور برنامه مراقبت',
    kind: CocoonCalendarItemKind.appointment,
  ),
  CocoonCalendarItem(
    id: 'reminder-1',
    title: 'یادآوری امروز',
    dateLabel: 'امروز',
    timeLabel: '۲۰:۰۰',
    kind: CocoonCalendarItemKind.reminder,
    pendingSync: true,
  ),
];

const _englishItems = [
  CocoonCalendarItem(
    id: 'appointment-1',
    title: 'Next appointment',
    dateLabel: '22 Sep',
    timeLabel: '16:30',
    supporting: 'Review your care plan',
    kind: CocoonCalendarItemKind.appointment,
  ),
  CocoonCalendarItem(
    id: 'reminder-1',
    title: "Today's reminder",
    dateLabel: 'Today',
    timeLabel: '20:00',
    supporting: 'Take a quiet moment to check in',
    kind: CocoonCalendarItemKind.reminder,
  ),
];

Widget _screen(
        {required bool fa, required Widget child, double textScale = 1}) =>
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
        theme: CocoonTheme.light(),
        home: RepaintBoundary(
          key: const ValueKey('calendar-visual-screen'),
          child: Material(
            child: Directionality(
              textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
              child: child,
            ),
          ),
        ),
      ),
    );

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _useGoldenTolerance() {
  final previous = goldenFileComparator;
  goldenFileComparator = _TolerantGoldenFileComparator(
    Uri.parse('test/cocoon_calendar_visual_test.dart'),
    precisionTolerance: .05,
  );
  addTearDown(() => goldenFileComparator = previous);
}

class _TolerantGoldenFileComparator extends LocalFileComparator {
  _TolerantGoldenFileComparator(
    super.testFile, {
    required double precisionTolerance,
  }) : _precisionTolerance = precisionTolerance;

  final double _precisionTolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _precisionTolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

Future<void> _loadCocoonFont() async {
  final loader = FontLoader(CocoonTheme.fontFamily)
    ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf'));
  await loader.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

class _CalendarHost implements CocoonHostContract {
  _CalendarHost({this.snapshot});

  final CocoonPregnancySnapshot? snapshot;

  @override
  CocoonEntryState get entryState => CocoonEntryState.activePregnancy;
  @override
  Locale get locale => const Locale('fa');
  @override
  String? get personId => 'calendar-person';
  @override
  CocoonPregnancySnapshot? get pregnancySnapshot => snapshot;
  @override
  CocoonPregnancySnapshot? get offlinePregnancySnapshot => null;
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

CocoonPregnancySnapshot _pregnancyAtWeek(int week, int day) =>
    CocoonPregnancySnapshot(
      contractVersion: 1,
      episode: CocoonPregnancyEpisode(
        id: 'calendar-episode',
        motherPersonId: 'calendar-person',
        status: CocoonPregnancyEpisodeStatus.active,
        dating: CocoonPregnancyDating(
          method: null,
          lmpDate: null,
          estimatedDueDate: null,
          referenceDate: null,
          gestationalAgeAtReferenceDays: null,
          gestationalAge: CocoonGestationalAge(
            totalDays: week * 7 + day,
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
