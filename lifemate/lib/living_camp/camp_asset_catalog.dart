import 'package:flutter/widgets.dart';

/// Runtime-facing catalog for the versioned #1073 Camp art pack.
///
/// Asset identity deliberately stays separate from zone topology, navigation,
/// entitlement and future progression. A new stage only adds catalog entries;
/// it never changes a zone's logical bounds or hotspot.
@immutable
class CampRasterAsset {
  const CampRasterAsset({
    required this.assetId,
    required this.zoneId,
    required this.stage,
    required this.variant,
    required this.path,
  });

  final String assetId;
  final String zoneId;
  final String stage;
  final String variant;
  final String path;
}

class CampAssetCatalog {
  CampAssetCatalog._();

  static const backgroundDay =
      'assets/living_camp/v1/raster/base/camp_background_day.webp';
  static const terrainDusk =
      'assets/living_camp/v1/raster/base/camp_terrain_dusk.webp';
  static const moonGarden =
      'assets/living_camp/v1/raster/zones/reproductive_context/stage_1/moon_garden.webp';

  static const zones = <CampRasterAsset>[
    CampRasterAsset(
      assetId: 'zone.lifemate_home.stage_1.default.day',
      zoneId: 'lifemate_home',
      stage: 'stage_1',
      variant: 'default',
      path:
          'assets/living_camp/v1/raster/zones/lifemate_home/stage_1/default_day.webp',
    ),
    CampRasterAsset(
      assetId: 'zone.wellmate.stage_1.default.day',
      zoneId: 'wellmate',
      stage: 'stage_1',
      variant: 'default',
      path:
          'assets/living_camp/v1/raster/zones/wellmate/stage_1/default_day.webp',
    ),
    CampRasterAsset(
      assetId: 'zone.caremate.stage_1.default.day',
      zoneId: 'caremate',
      stage: 'stage_1',
      variant: 'default',
      path:
          'assets/living_camp/v1/raster/zones/caremate/stage_1/default_day.webp',
    ),
    CampRasterAsset(
      assetId: 'zone.reproductive_context.stage_1.default.day',
      zoneId: 'reproductive_context',
      stage: 'stage_1',
      variant: 'default',
      path:
          'assets/living_camp/v1/raster/zones/reproductive_context/stage_1/default_day.webp',
    ),
    CampRasterAsset(
      assetId: 'zone.fitmate.stage_1.under_construction.day',
      zoneId: 'fitmate',
      stage: 'stage_1',
      variant: 'under_construction',
      path:
          'assets/living_camp/v1/raster/zones/fitmate/stage_1/under_construction_day.webp',
    ),
  ];

  /// Exact stage/variant wins; the modest Stage-1 default is the guaranteed
  /// compatibility fallback for future packs that are not installed yet.
  static CampRasterAsset resolve({
    required String zoneId,
    String stage = 'stage_1',
    String variant = 'default',
  }) {
    return zones.firstWhere(
      (asset) =>
          asset.zoneId == zoneId &&
          asset.stage == stage &&
          asset.variant == variant,
      orElse: () => zones.firstWhere(
        (asset) =>
            asset.zoneId == zoneId &&
            asset.stage == 'stage_1' &&
            asset.variant == 'default',
        orElse: () => zones.firstWhere((asset) => asset.zoneId == zoneId),
      ),
    );
  }
}
