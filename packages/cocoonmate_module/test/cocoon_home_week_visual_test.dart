import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  setUpAll(_loadCocoonFont);

  testWidgets('Persian home is directional and stable at 390x844, text 1.5', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    final host = _VisualHost(
      locale: const Locale('fa'),
      pregnancySnapshot: _pregnancyAtWeek(24, 3),
    );

    await tester.pumpWidget(
      _screen(
        fa: true,
        textScale: 1.5,
        child: CocoonPregnancyHome(
          host: host,
          fa: true,
          onOpenWeek: _noop,
          onOpenSafety: _noop,
        ),
      ),
    );

    expect(find.text('۲۴'), findsOneWidget);
    expect(find.text('هفته و ۳ روز'), findsOneWidget);
    expect(find.text('یادداشت این هفته'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('cocoon-visual-screen')),
      matchesGoldenFile('goldens/cocoon_home_fa_390x844.png'),
    );
  });

  testWidgets('English home dating fallback is stable on a 320x568 phone', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 568));
    final host = _VisualHost(locale: const Locale('en'));

    await tester.pumpWidget(
      _screen(
        fa: false,
        textScale: 1.5,
        child: CocoonPregnancyHome(
          host: host,
          fa: false,
          onOpenWeek: _noop,
          onOpenSafety: _noop,
        ),
      ),
    );

    expect(
      find.text('Shown after verified dating is available'),
      findsOneWidget,
    );
    expect(find.text('This week’s guide'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Persian week detail remains scrollable at 320x568, text 1.5', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 568));
    final host = _VisualHost(
      locale: const Locale('fa'),
      pregnancySnapshot: _pregnancyAtWeek(24, 3),
    );

    await tester.pumpWidget(
      _screen(
        fa: true,
        textScale: 1.5,
        child: CocoonWeekDetail(host: host, fa: true),
      ),
    );

    expect(find.text('هفته ۲۴'), findsOneWidget);
    expect(find.text('هفته ۲۴، روز ۳'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('نشانه‌های نیازمند توجه'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('در انتظار محتوای تأییدشده'), findsWidgets);
    expect(find.text('نشانه‌های نیازمند توجه'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English week detail exposes a professional partial state', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    final host = _VisualHost(
      locale: const Locale('en'),
      pregnancySnapshot: _pregnancyAtWeek(24, 3),
    );

    await tester.pumpWidget(
      _screen(
        fa: false,
        textScale: 1,
        child: CocoonWeekDetail(host: host, fa: false),
      ),
    );

    expect(find.text('Reviewed weekly guide'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('cocoon-visual-screen')),
      matchesGoldenFile('goldens/cocoon_week_detail_en_390x844.png'),
    );
    await tester.scrollUntilVisible(
      find.text('Pregnancy development'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Awaiting approved content'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
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

Widget _screen({
  required bool fa,
  required double textScale,
  required Widget child,
}) =>
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
        theme: CocoonTheme.light(),
        home: RepaintBoundary(
          key: const ValueKey('cocoon-visual-screen'),
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

void _noop() {}

class _VisualHost implements CocoonHostContract {
  _VisualHost({required this.locale, this.pregnancySnapshot});

  @override
  CocoonEntryState entryState = CocoonEntryState.activePregnancy;
  @override
  final Locale locale;
  @override
  String? personId = 'visual-person';
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

CocoonPregnancySnapshot _pregnancyAtWeek(int week, int day) {
  final totalDays = week * 7 + day;
  return CocoonPregnancySnapshot(
    contractVersion: 1,
    episode: CocoonPregnancyEpisode(
      id: 'visual-episode',
      motherPersonId: 'visual-person',
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
