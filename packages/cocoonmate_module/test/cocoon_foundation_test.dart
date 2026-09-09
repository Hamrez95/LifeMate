import 'dart:convert';
import 'dart:io';

import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(_loadCocoonFont);

  test('bundled asset manifest is valid and every declared file exists', () {
    final manifestFile = File('assets/manifest.json');
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    expect(manifest['schemaVersion'], 1);

    final assets = manifest['assets']! as List<dynamic>;
    for (final entry in assets.cast<Map<String, dynamic>>()) {
      final path = entry['path'];
      if (path is String && path.startsWith('assets/')) {
        expect(File(path).existsSync(), isTrue, reason: entry['id'] as String);
      }
      expect(entry['purpose'], isNotEmpty);
      expect(entry['placement'], isNotEmpty);
      expect(entry['rtlSafety'], isNotEmpty);
      expect(entry['semanticRole'], isNotEmpty);
      expect(entry['sourceStatus'], isNotEmpty);
      expect(entry['medicalReviewStatus'], isNotEmpty);
    }
  });

  test('core text and action pairs meet WCAG AA contrast', () {
    expect(_contrast(CocoonColors.ink, CocoonColors.canvas), greaterThan(4.5));
    expect(
      _contrast(CocoonColors.muted, CocoonColors.canvas),
      greaterThan(4.5),
    );
    expect(_contrast(Colors.white, CocoonColors.coralAction), greaterThan(4.5));
    expect(
      _contrast(CocoonColors.skyStrong, CocoonColors.sky),
      greaterThan(4.5),
    );
  });

  testWidgets('brand mark has an accessible identity in RTL and LTR', (
    tester,
  ) async {
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: CocoonTheme.light(),
          home: Directionality(
            textDirection: direction,
            child: const Scaffold(
              body: Center(
                child: CocoonBrandMark(
                  semanticLabel: 'CocoonMate brand mark',
                  size: 96,
                  showWordmark: true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('CocoonMate brand mark'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('brand mark visual remains stable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(160, 160));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: const Scaffold(
          body: RepaintBoundary(
            key: ValueKey('brand-mark-golden'),
            child: Center(
              child: CocoonBrandMark(
                semanticLabel: 'CocoonMate brand mark',
                size: 112,
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(const ValueKey('brand-mark-golden')),
      matchesGoldenFile('goldens/cocoon_brand_mark.png'),
    );
  });

  testWidgets('onboarding hero renders in Persian at reference viewport', (
    tester,
  ) async {
    final previousComparator = goldenFileComparator;
    goldenFileComparator = _TolerantGoldenFileComparator(
      Uri.parse('test/cocoon_foundation_test.dart'),
      precisionTolerance: .035,
    );
    addTearDown(() => goldenFileComparator = previousComparator);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: DefaultAssetBundle(
          bundle: _PackageTestAssetBundle(),
          child: RepaintBoundary(
            key: const ValueKey('onboarding-golden'),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: CocoonPregnancyOnboardingScreen(
                fa: true,
                timezone: 'Asia/Tehran',
                onPickDate: (_) async => null,
                onActivate: (_) async => false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final illustration = find.byType(Image);
    expect(illustration, findsOneWidget);
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(
          'assets/illustrations/onboarding-protected-growth-v1.png',
          package: 'cocoonmate_module',
        ),
        tester.element(illustration),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('تصویر نمادین رشد در فضایی امن و آرام'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('onboarding-golden')),
      matchesGoldenFile('goldens/cocoon_onboarding_fa_390x844.png'),
    );
  });
}

class _PackageTestAssetBundle extends CachingAssetBundle {
  static const _packagePrefix = 'packages/cocoonmate_module/';

  @override
  Future<ByteData> load(String key) => rootBundle.load(
        key.startsWith(_packagePrefix)
            ? key.substring(_packagePrefix.length)
            : key,
      );
}

class _TolerantGoldenFileComparator extends LocalFileComparator {
  _TolerantGoldenFileComparator(
    super.testFile, {
    required double precisionTolerance,
  })  : assert(precisionTolerance >= 0 && precisionTolerance <= 1),
        _precisionTolerance = precisionTolerance;

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

double _contrast(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = foreground == lighter ? background : foreground;
  return (lighter.computeLuminance() + .05) / (darker.computeLuminance() + .05);
}
