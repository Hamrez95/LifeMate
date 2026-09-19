import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/living_camp/camp_avatar_fallback.dart';
import 'package:lifemate/living_camp/camp_scene_renderer.dart';

void main() {
  test('both adult families resolve to an idle fallback asset', () {
    for (final family in CampAvatarFamily.values) {
      final asset = CampAvatarFallbackCatalog.resolve(family: family);
      expect(asset.path, contains('assets/living_camp/v1/raster/actors/'));
    }
  });

  test('unsupported raster actions deliberately remain on the idle asset', () {
    final idle = CampAvatarFallbackCatalog.resolve(
      family: CampAvatarFamily.adultMasculine,
    );
    final wellness = CampAvatarFallbackCatalog.resolve(
      family: CampAvatarFamily.adultMasculine,
      action: CampAvatarAction.wellness,
    );
    expect(wellness.path, idle.path);
  });

  testWidgets(
    'world actor is decorative and does not create a second tap target',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: CampSceneRenderer(
              zones: const [],
              presentations: const [],
              layers: const [],
              actors: [
                CampSceneActor(
                  actorId: 'avatar',
                  anchor: const CampPoint(500, 1000),
                  width: 100,
                  height: 160,
                  builder: (_) => const CampAvatarFallback(
                    family: CampAvatarFamily.adultFeminine,
                    motionEnabled: false,
                  ),
                ),
              ],
              onZoneTap: (_) => taps++,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('camp-actor-avatar')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(200, 400));
      expect(taps, 0);
    },
  );
}
