import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> configureView(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
  }

  Widget harness({
    required Size size,
    required LifeMateOnboardingTheme theme,
    TextDirection direction = TextDirection.rtl,
    double textScale = 1,
    EdgeInsets viewInsets = EdgeInsets.zero,
    EdgeInsets padding = const EdgeInsets.only(top: 24, bottom: 24),
    bool keyboardAware = false,
    bool showField = false,
  }) {
    final controller = TextEditingController(text: showField ? '09121234567' : '');
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: padding,
          viewPadding: padding,
          viewInsets: viewInsets,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(
          textDirection: direction,
          child: LifeMateOnboardingScaffold(
            theme: theme,
            title: 'LifeMate',
            progress: 0.5,
            progressLabel: '۲ از ۴',
            primaryLabel: 'ادامه',
            onPrimary: () {},
            keyboardAware: keyboardAware,
            body: Column(
              children: [
                const Spacer(),
                LifeMateOnboardingQuestion(
                  theme: theme,
                  title: showField
                      ? 'شماره موبایل را وارد کن'
                      : 'LifeMate را بیشتر برای چه کاری می‌خواهی؟',
                  description: showField
                      ? 'کد تأیید فقط برای همین شماره ارسال می‌شود.'
                      : 'این انتخاب فقط تجربه را شخصی‌سازی می‌کند.',
                  icon: showField
                      ? Icons.phone_android_rounded
                      : Icons.favorite_outline_rounded,
                  alignCenter: true,
                ),
                const SizedBox(height: 16),
                if (showField)
                  LifeMateOnboardingTextField(
                    key: const ValueKey('directional-field'),
                    theme: theme,
                    controller: controller,
                    label: 'شماره موبایل',
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                  )
                else
                  LifeMateOnboardingOptionCard(
                    key: const ValueKey('matrix-option'),
                    theme: theme,
                    title: 'برای خودم',
                    subtitle: 'مدیریت سلامت و برنامه‌های شخصی',
                    icon: Icons.person_outline_rounded,
                    selected: true,
                    onTap: () {},
                  ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  for (final size in const <Size>[
    Size(390, 844),
    Size(360, 760),
    Size(360, 640),
    Size(320, 568),
  ]) {
    testWidgets('V3 scaffold has no overflow or scroll at ${size.width}x${size.height}', (
      tester,
    ) async {
      await configureView(tester, size);
      await tester.pumpWidget(
        harness(
          size: size,
          theme: LifeMateOnboardingTheme.shared,
          textScale: size.height <= 640 ? 1.15 : 1.3,
        ),
      );

      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(ListView), findsNothing);
      expect(find.text('ادامه'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('safe areas keep fixed CTA above gesture navigation inset', (
    tester,
  ) async {
    const size = Size(390, 844);
    await configureView(tester, size);
    await tester.pumpWidget(
      harness(
        size: size,
        theme: LifeMateOnboardingTheme.wellMate,
        padding: const EdgeInsets.only(top: 32, bottom: 34),
      ),
    );

    final button = find.byType(LifeMatePrimaryOnboardingButton);
    expect(button, findsOneWidget);
    final rect = tester.getRect(button);
    expect(rect.top, greaterThan(32));
    expect(rect.bottom, lessThanOrEqualTo(size.height - 34));
    expect(tester.takeException(), isNull);
  });

  testWidgets('RTL form keeps phone input explicitly LTR', (tester) async {
    const size = Size(390, 844);
    await configureView(tester, size);
    await tester.pumpWidget(
      harness(
        size: size,
        theme: LifeMateOnboardingTheme.shared,
        direction: TextDirection.rtl,
        showField: true,
      ),
    );

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.textDirection, TextDirection.ltr);
    expect(Directionality.of(tester.element(find.byType(Scaffold))), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English LTR uses the same component tree', (tester) async {
    const size = Size(390, 844);
    await configureView(tester, size);
    await tester.pumpWidget(
      harness(
        size: size,
        theme: LifeMateOnboardingTheme.careMate,
        direction: TextDirection.ltr,
      ),
    );

    expect(find.byType(LifeMateOnboardingScaffold), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(Scaffold))), TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard-aware screen preserves CTA and no-scroll contract', (
    tester,
  ) async {
    const size = Size(390, 844);
    await configureView(tester, size);
    await tester.pumpWidget(
      harness(
        size: size,
        theme: LifeMateOnboardingTheme.shared,
        keyboardAware: true,
        showField: true,
        viewInsets: const EdgeInsets.only(bottom: 280),
        padding: const EdgeInsets.only(top: 24),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('ادامه'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary, option and back controls meet 48dp target minimums', (
    tester,
  ) async {
    const size = Size(390, 844);
    await configureView(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: LifeMateOnboardingScaffold(
            theme: LifeMateOnboardingTheme.womenHealth,
            title: 'مرحله',
            primaryLabel: 'ادامه',
            onPrimary: () {},
            onBack: () {},
            body: Center(
              child: LifeMateOnboardingOptionCard(
                key: const ValueKey('target-option'),
                theme: LifeMateOnboardingTheme.womenHealth,
                title: 'منظم',
                selected: true,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(LifeMatePrimaryOnboardingButton)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('target-option'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byType(IconButton).first).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected state is not communicated by color alone', (tester) async {
    const size = Size(390, 844);
    await configureView(tester, size);
    await tester.pumpWidget(
      harness(size: size, theme: LifeMateOnboardingTheme.womenHealth),
    );

    final option = find.byKey(const ValueKey('matrix-option'));
    expect(
      find.descendant(of: option, matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
