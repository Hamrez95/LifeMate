import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app({
    required LifeMateOnboardingTheme theme,
    TextDirection direction = TextDirection.rtl,
    double textScale = 1,
    Size size = const Size(390, 844),
  }) {
    return MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
      child: Directionality(
        textDirection: direction,
        child: MaterialApp(
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
        ),
      ),
    );
  }

  testWidgets('normal onboarding uses a fixed column and no scroll view', (tester) async {
    await tester.pumpWidget(app(theme: LifeMateOnboardingTheme.shared));
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('ادامه'), findsOneWidget);
    expect(find.text('۲ از ۴'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same scaffold renders all semantic product themes', (tester) async {
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

  testWidgets('RTL and large text remain buildable on reference viewport', (tester) async {
    await tester.pumpWidget(
      app(
        theme: LifeMateOnboardingTheme.careMate,
        direction: TextDirection.rtl,
        textScale: 1.3,
      ),
    );
    expect(find.text('LifeMate را بیشتر برای چه کاری می‌خواهی؟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected option exposes semantic selected state', (tester) async {
    await tester.pumpWidget(app(theme: LifeMateOnboardingTheme.wellMate));
    final semantics = tester.getSemantics(find.text('برای خودم'));
    expect(semantics.hasFlag(SemanticsFlag.isSelected), isTrue);
  });
}
