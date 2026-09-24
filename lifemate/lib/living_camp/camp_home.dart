import 'package:flutter/material.dart';

import 'camp_asset_catalog.dart';
import 'camp_avatar_fallback.dart';
import 'camp_vector_avatar.dart';
import 'camp_environment.dart';
import 'camp_ground_overlay.dart';
import 'camp_scene_renderer.dart';

class CampHome extends StatelessWidget {
  const CampHome({
    super.key,
    required this.isPersian,
    required this.onOpenToday,
    required this.onOpenWellMate,
    this.onOpenCareMate,
    this.onOpenReproductiveContext,
    this.onOpenFitMate,
    this.zonePresentations,
    this.environmentPreferences = const CampEnvironmentPreferences(),
    this.nowUtc,
  });

  final bool isPersian;
  final VoidCallback onOpenToday;
  final VoidCallback onOpenWellMate;
  final VoidCallback? onOpenCareMate;
  final VoidCallback? onOpenReproductiveContext;
  final VoidCallback? onOpenFitMate;

  /// Normalized snapshot from a reviewed adapter; Camp only renders it.
  final List<CampZonePresentation>? zonePresentations;
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

    final defaultPresentations = <CampZonePresentation>[
      CampZonePresentation(
        zoneId: 'lifemate_home',
        stateLabel: _t('Available', 'در دسترس'),
      ),
      CampZonePresentation(
        zoneId: 'wellmate',
        stateLabel: _t('Available', 'در دسترس'),
      ),
      CampZonePresentation(
        zoneId: 'caremate',
        availability: CampZoneAvailability.locked,
        stateLabel: _t('Locked', 'قفل است'),
      ),
      CampZonePresentation(
        zoneId: 'reproductive_context',
        availability: CampZoneAvailability.locked,
        stateLabel: _t('Locked', 'قفل است'),
      ),
      CampZonePresentation(
        zoneId: 'fitmate',
        availability: CampZoneAvailability.unavailable,
        stateLabel: _t('Coming soon', 'به‌زودی'),
      ),
    ];
    final presentations = zonePresentations ?? defaultPresentations;

    return CampEnvironmentHost(
      preferences: environmentPreferences,
      nowUtc: nowUtc,
      builder: (context, environment) {
        final isNight = environment.phase == CampDayPhase.night;
        final backgroundColor = isNight
            ? const Color(0xFF111A29)
            : const Color(0xFFE3E9D9);

        return SafeArea(
          child: ColoredBox(
            color: backgroundColor,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CampSceneRenderer(
                    zones: zones,
                    presentations: presentations,
                    actors: [
                      CampSceneActor(
                        actorId: 'main_avatar_vector',
                        anchor: const CampPoint(505, 1300),
                        width: 132,
                        height: 198,
                        builder: (_) => CampVectorAvatar(
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
                                    Color(0x661A3044),
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
                        builder: (_) => CampGroundOverlay(isNight: isNight),
                      ),
                    ],
                    onZoneTap: (zoneId) {
                      switch (zoneId) {
                        case 'lifemate_home':
                          onOpenToday();
                        case 'wellmate':
                          onOpenWellMate();
                        case 'caremate':
                          onOpenCareMate?.call();
                        case 'reproductive_context':
                          onOpenReproductiveContext?.call();
                        case 'fitmate':
                          onOpenFitMate?.call();
                      }
                    },
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                    child: _CampSceneCaption(
                      title: _t('Living Camp', 'کمپ زنده'),
                      subtitle: _t(
                        'A little space to breathe',
                        'جایی برای نفس کشیدن',
                      ),
                      isNight: isNight,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: _CampSceneHint(
                      label: _t(
                        'Tap a place to explore',
                        'برای دیدن هر بخش، روی آن بزن',
                      ),
                      isNight: isNight,
                    ),
                  ),
                ),
              ],
            ),
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
          builder: (_) => ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  CampAssetCatalog.resolve(
                    zoneId: id,
                    variant: id == 'fitmate' ? 'under_construction' : 'default',
                  ).path,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 190),
                    margin: const EdgeInsets.only(bottom: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xEFFFF9EB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x66A3977B)),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF3D4D40),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CampSceneCaption extends StatelessWidget {
  const _CampSceneCaption({
    required this.title,
    required this.subtitle,
    required this.isNight,
  });

  final String title;
  final String subtitle;
  final bool isNight;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isNight ? const Color(0xD91B2B35) : const Color(0xEFFFF9EC),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isNight ? const Color(0x446F8A85) : const Color(0x88E2CDAF),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isNight
                      ? const Color(0xFFF1ECE0)
                      : const Color(0xFF354C40),
                ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isNight
                      ? const Color(0xFFD4DDCE)
                      : const Color(0xFF52675A),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CampSceneHint extends StatelessWidget {
  const _CampSceneHint({required this.label, required this.isNight});

  final String label;
  final bool isNight;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: isNight ? const Color(0xDD1B2B35) : const Color(0xEFFFF9EC),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: isNight ? const Color(0xFFF1ECE0) : const Color(0xFF354C40),
          ),
        ),
      ),
    ),
  );
}
