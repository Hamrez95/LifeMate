import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> configureView(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
  }

  Widget app({
    required LifeMateOnboardingTheme theme,
    TextDirection direction = TextDirection.rtl,
    double textScale = 1,
  }) {
    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(
          textDirection: direction,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: LifeMateOnboardingScaffold(
        theme: theme,
        title: 'شروع',
        progress: 0.5,
        progressLabel: '۲ از ۴',
        primaryLabel: 'ادامه',
        onPrimary: () {},
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LifeMateOnboardingQuestion(
              theme: theme,
              title: 'LifeMate را بیشتر برای چه کاری می‌خواهی؟',
              description: 'انتخاب شما فقط تجربه را شخصی‌سازی می‌کند.',
              icon: Icons.favorite_outline_rounded,
              alignCenter: true,
            ),
            const SizedBox(height: 24),
            LifeMateOnboardingOptionCard(
              key: const ValueKey('intent-self'),
              theme: theme,
              title: 'برای خودم',
              subtitle: 'مدیریت سلامت و برنامه‌های شخصی',
              icon: Icons.person_outline_rounded,
              selected: true,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('normal onboarding uses a fixed column and no scroll view', (
    tester,
  ) async {
    await configureView(tester);
    await tester.pumpWidget(app(theme: LifeMateOnboardingTheme.shared));

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('ادامه'), findsOneWidget);
    expect(find.text('۲ از ۴'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same scaffold renders all semantic product themes', (
    tester,
  ) async {
    await configureView(tester);
    for (final theme in const [
      LifeMateOnboardingTheme.shared,
      LifeMateOnboardingTheme.wellMate,
      LifeMateOnboardingTheme.womenHealth,
      LifeMateOnboardingTheme.careMate,
    ]) {
      await tester.pumpWidget(app(theme: theme));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, theme.background);
      expect(find.text('برای خودم'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('RTL and large text remain buildable on reference viewport', (
    tester,
  ) async {
    await configureView(tester);
    await tester.pumpWidget(
      app(
        theme: LifeMateOnboardingTheme.careMate,
        direction: TextDirection.rtl,
        textScale: 1.3,
      ),
    );

    expect(find.text('LifeMate را بیشتر برای چه کاری می‌خواهی؟'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('representative smaller viewport does not overflow', (
    tester,
  ) async {
    await configureView(tester, size: const Size(360, 760));
    await tester.pumpWidget(
      app(theme: LifeMateOnboardingTheme.wellMate, textScale: 1.15),
    );

    expect(find.text('ادامه'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected option uses visual state beyond color alone', (
    tester,
  ) async {
    await configureView(tester);
    await tester.pumpWidget(app(theme: LifeMateOnboardingTheme.wellMate));

    final optionFinder = find.byKey(const ValueKey('intent-self'));
    expect(optionFinder, findsOneWidget);
    expect(
      find.descendant(
        of: optionFinder,
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
