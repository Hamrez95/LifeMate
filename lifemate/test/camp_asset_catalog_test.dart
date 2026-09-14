import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/living_camp/camp_asset_catalog.dart';

void main() {
  test('every required stable zone has a Stage-1 asset', () {
    const requiredZones = {
      'lifemate_home',
      'wellmate',
      'caremate',
      'reproductive_context',
      'fitmate',
    };

    expect(
      CampAssetCatalog.zones.map((asset) => asset.zoneId).toSet(),
      containsAll(requiredZones),
    );
    for (final zoneId in requiredZones) {
      expect(CampAssetCatalog.resolve(zoneId: zoneId).stage, 'stage_1');
    }
  });

  test('a missing future stage falls back without changing zone identity', () {
    final fallback = CampAssetCatalog.resolve(
      zoneId: 'wellmate',
      stage: 'stage_99',
      variant: 'future_theme',
    );

    expect(fallback.zoneId, 'wellmate');
    expect(fallback.stage, 'stage_1');
    expect(fallback.variant, 'default');
  });

  test('FitMate exposes the quiet under-construction Stage-1 variant', () {
    final fitmate = CampAssetCatalog.resolve(
      zoneId: 'fitmate',
      variant: 'under_construction',
    );

    expect(fitmate.variant, 'under_construction');
    expect(fitmate.path, contains('under_construction_day.webp'));
  });
}
