import 'package:flutter/material.dart';

import 'camp_asset_catalog.dart';
import 'camp_avatar_fallback.dart';
import 'camp_environment.dart';
import 'camp_scene_renderer.dart';

class CampHome extends StatelessWidget {
  const CampHome({
    super.key,
    required this.isPersian,
    required this.onOpenToday,
    required this.onOpenWellMate,
    this.environmentPreferences = const CampEnvironmentPreferences(),
    this.nowUtc,
  });

  final bool isPersian;
  final VoidCallback onOpenToday;
  final VoidCallback onOpenWellMate;
  final CampEnvironmentPreferences environmentPreferences;
  final DateTime Function()? nowUtc;

  String _t(String en, String fa) => isPersian ? fa : en;

  @override
  Widget build(BuildContext context) {
    final zones = <CampZoneDefinition>[
      _zone(
        'lifemate_home',
        const CampRect(left: 360, top: 820, width: 280, height: 260),
        _t('LifeMate home', 'خانه LifeMate'),
      ),
      _zone(
        'wellmate',
        const CampRect(left: 100, top: 1110, width: 250, height: 220),
        'WellMate',
      ),
      _zone(
        'caremate',
        const CampRect(left: 650, top: 1100, width: 250, height: 220),
        'CareMate',
      ),
      _zone(
        'reproductive_context',
        const CampRect(left: 120, top: 1450, width: 260, height: 220),
        _t('Cocoon / Women Health', 'Cocoon / سلامت زنان'),
      ),
      _zone(
        'fitmate',
        const CampRect(left: 620, top: 1460, width: 260, height: 220),
        'FitMate',
      ),
    ];

    const presentations = <CampZonePresentation>[
      CampZonePresentation(zoneId: 'lifemate_home'),
      CampZonePresentation(zoneId: 'wellmate'),
      CampZonePresentation(
        zoneId: 'caremate',
        availability: CampZoneAvailability.locked,
      ),
      CampZonePresentation(
        zoneId: 'reproductive_context',
        availability: CampZoneAvailability.locked,
      ),
      CampZonePresentation(
        zoneId: 'fitmate',
        availability: CampZoneAvailability.unavailable,
      ),
    ];

    return CampEnvironmentHost(
      preferences: environmentPreferences,
      nowUtc: nowUtc,
      builder: (context, environment) {
        final colors = Theme.of(context).colorScheme;
        final isNight = environment.phase == CampDayPhase.night;
        final backgroundColor = isNight
            ? const Color(0xFF111A29)
            : colors.surface;
        final groundTop = isNight
            ? const Color(0xFF1C2933)
            : colors.surfaceContainerLow;
        final groundBottom = isNight
            ? const Color(0xFF13241F)
            : colors.surfaceContainer;

        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 8),
                child: Text(
                  _t('Living Camp', 'کمپ زنده'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: CampSceneRenderer(
                  zones: zones,
                  presentations: presentations,
                  actors: [
                    CampSceneActor(
                      actorId: 'main_avatar_fallback',
                      anchor: const CampPoint(505, 1060),
                      width: 132,
                      height: 198,
                      builder: (_) => CampAvatarFallback(
                        family: CampAvatarFamily.adultMasculine,
                        motionEnabled: environment.motionEnabled,
                      ),
                    ),
                  ],
                  layers: [
                    CampSceneLayer(
                      id: 'background',
                      zIndex: 0,
                      builder: (_) => ColoredBox(
                        color: backgroundColor,
                        child: ColorFiltered(
                          colorFilter: isNight
                              ? const ColorFilter.mode(
                                  Color(0xAA10213B),
                                  BlendMode.multiply,
                                )
                              : const ColorFilter.mode(
                                  Colors.transparent,
                                  BlendMode.srcOver,
                                ),
                          child: Image.asset(
                            CampAssetCatalog.backgroundDay,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                    CampSceneLayer(
                      id: 'ground',
                      zIndex: 10,
                      builder: (_) => DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [groundTop, groundBottom],
                          ),
                        ),
                      ),
                    ),
                  ],
                  onZoneTap: (zoneId) {
                    switch (zoneId) {
                      case 'lifemate_home':
                        onOpenToday();
                      case 'wellmate':
                        onOpenWellMate();
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 16),
                child: Text(
                  _t(
                    'Scene topology is live. Final layered artwork and Rive actors arrive through #1073 and #1074 without changing zone identity or hotspots.',
                    'توپولوژی صحنه فعال است. آرت لایه‌ای و بازیگرهای Rive در #1073 و #1074 بدون تغییر هویت zone یا hotspot جایگزین می‌شوند.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  CampZoneDefinition _zone(String id, CampRect bounds, String label) {
    return CampZoneDefinition(
      zoneId: id,
      bounds: bounds,
      semanticLabel: label,
      visuals: [
        CampZoneVisual(
          stage: 1,
          variant: 'default',
          builder: (_) => Image.asset(
            CampAssetCatalog.resolve(
              zoneId: id,
              variant: id == 'fitmate' ? 'under_construction' : 'default',
            ).path,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ],
    );
  }
}
