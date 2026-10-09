import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LifeMateRuntimeLocale.setLanguageCode('fa');
  });

  Future<void> pumpAuth(
    WidgetTester tester, {
    Size viewport = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: LifeMateSharedAuthExperience(
          appName: 'WellMate',
          logoAssetPath: 'missing-test-logo.png',
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('auth V3 uses no scroll view on reference viewport', (
    tester,
  ) async {
    await pumpAuth(tester);

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('حساب LifeMate'), findsOneWidget);
    expect(find.text('ورود با ایمیل'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide auth layout stays centered at a readable width', (
    tester,
  ) async {
    await pumpAuth(tester, viewport: const Size(1280, 800));

    final button = find.byType(LifeMatePrimaryOnboardingButton);
    expect(tester.getSize(button).width, lessThanOrEqualTo(560));
    expect(tester.getCenter(button).dx, closeTo(640, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone path stays hidden when provider flag is disabled', (
    tester,
  ) async {
    await pumpAuth(tester);

    expect(LifeMateFeatureFlags.phoneOtpEnabled, isFalse);
    expect(find.text('شماره موبایل'), findsNothing);
    expect(find.byType(SegmentedButton<dynamic>), findsNothing);
  });

  testWidgets('email signup no longer collects display name inside auth', (
    tester,
  ) async {
    await pumpAuth(tester);

    await tester.tap(find.text('حساب جدید'));
    await tester.pump();

    expect(find.text('ساخت حساب LifeMate'), findsOneWidget);
    expect(find.text('تکرار رمز عبور'), findsOneWidget);
    expect(find.textContaining('نام نمایشی'), findsNothing);
    expect(find.textContaining('نام و هدف استفاده'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
