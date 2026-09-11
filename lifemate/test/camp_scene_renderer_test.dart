import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/living_camp/camp_scene_renderer.dart';

void main() {
  test('zone visual resolver falls back to Stage 1 default', () {
    final stage1 = CampZoneVisual(
      stage: 1,
      variant: 'default',
      builder: (_) => const SizedBox(),
    );
    final zone = CampZoneDefinition(
      zoneId: 'wellmate',
      bounds: const CampRect(left: 0, top: 0, width: 100, height: 100),
      semanticLabel: 'WellMate',
      visuals: [stage1],
    );

    expect(zone.resolveVisual(stage: 99, variant: 'future'), same(stage1));
  });

  testWidgets('renderer exposes semantic hotspot independently from art', (
    tester,
  ) async {
    String? tapped;
    final zone = CampZoneDefinition(
      zoneId: 'lifemate_home',
      bounds: const CampRect(left: 300, top: 800, width: 400, height: 300),
      semanticLabel: 'LifeMate home',
      visuals: [
        CampZoneVisual(
          stage: 1,
          variant: 'default',
          builder: (_) => const ColoredBox(color: Colors.green),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: CampSceneRenderer(
            zones: [zone],
            presentations: const [
              CampZonePresentation(zoneId: 'lifemate_home'),
            ],
            layers: const [],
            onZoneTap: (id) => tapped = id,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('LifeMate home'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('LifeMate home'));
    expect(tapped, 'lifemate_home');
  });

  testWidgets('locked zone remains semantic but cannot navigate', (
    tester,
  ) async {
    var taps = 0;
    final zone = CampZoneDefinition(
      zoneId: 'caremate',
      bounds: const CampRect(left: 300, top: 800, width: 400, height: 300),
      semanticLabel: 'CareMate',
      visuals: [
        CampZoneVisual(
          stage: 1,
          variant: 'default',
          builder: (_) => const SizedBox.expand(),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CampSceneRenderer(
          zones: [zone],
          presentations: const [
            CampZonePresentation(
              zoneId: 'caremate',
              availability: CampZoneAvailability.locked,
            ),
          ],
          layers: const [],
          onZoneTap: (_) => taps++,
        ),
      ),
    );

    expect(find.bySemanticsLabel('CareMate'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('CareMate'));
    expect(taps, 0);
  });
}
