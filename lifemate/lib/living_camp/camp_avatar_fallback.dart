import 'package:flutter/material.dart';

/// Raster-only visual fallback while the #1074 Rive actor is being authored.
///
/// This is intentionally presentation-only. It neither claims Rive action
/// support nor provides a skin-tone tint: tinting a flattened illustration
/// would incorrectly recolour hair and clothing. The future Rive adapter can
/// replace this widget without changing actor identity or world placement.
enum CampAvatarFamily { adultFeminine, adultMasculine }

enum CampAvatarAgeBand { age2, age10, age20, age30, age50, age70 }

enum CampAvatarAction { idle, walk, drink, wellness }

@immutable
class CampAvatarFallbackAsset {
  const CampAvatarFallbackAsset({
    required this.family,
    required this.ageBand,
    required this.path,
  });

  final CampAvatarFamily family;
  final CampAvatarAgeBand ageBand;
  final String path;
}

class CampAvatarFallbackCatalog {
  CampAvatarFallbackCatalog._();

  static const assets = <CampAvatarFallbackAsset>[
    CampAvatarFallbackAsset(
      family: CampAvatarFamily.adultFeminine,
      ageBand: CampAvatarAgeBand.age2,
      path: 'assets/living_camp/v1/raster/actors/female_age_2_idle.png',
    ),
    CampAvatarFallbackAsset(
      family: CampAvatarFamily.adultFeminine,
      ageBand: CampAvatarAgeBand.age10,
      path: 'assets/living_camp/v1/raster/actors/female_age_10_idle.png',
    ),
    CampAvatarFallbackAsset(
      family: CampAvatarFamily.adultFeminine,
      ageBand: CampAvatarAgeBand.age20,
      path: 'assets/living_camp/v1/raster/actors/female_age_20_idle.png',
    ),
    CampAvatarFallbackAsset(
      family: CampAvatarFamily.adultFeminine,
      ageBand: CampAvatarAgeBand.age30,
      path: 'assets/living_camp/v1/raster/actors/adult_female_idle.png',
    ),
    CampAvatarFallbackAsset(
      family: CampAvatarFamily.adultMasculine,
      ageBand: CampAvatarAgeBand.age2,
      path: 'assets/living_camp/v1/raster/actors/male_age_2_idle.png',
    ),
    CampAvatarFallbackAsset(
      family: CampAvatarFamily.adultMasculine,
      ageBand: CampAvatarAgeBand.age10,
      path: 'assets/living_camp/v1/raster/actors/male_age_10_idle.png',
    ),
    CampAvatarFallbackAsset(
      family: CampAvatarFamily.adultMasculine,
      ageBand: CampAvatarAgeBand.age20,
      path: 'assets/living_camp/v1/raster/actors/male_age_20_idle.png',
    ),
    CampAvatarFallbackAsset(
      family: CampAvatarFamily.adultMasculine,
      ageBand: CampAvatarAgeBand.age30,
      path: 'assets/living_camp/v1/raster/actors/adult_male_idle.png',
    ),
    CampAvatarFallbackAsset(
      family: CampAvatarFamily.adultFeminine,
      ageBand: CampAvatarAgeBand.age50,
      path: 'assets/living_camp/v1/raster/actors/female_age_50_idle.png',
    ),
    CampAvatarFallbackAsset(
      family: CampAvatarFamily.adultFeminine,
      ageBand: CampAvatarAgeBand.age70,
      path: 'assets/living_camp/v1/raster/actors/female_age_70_idle.png',
    ),
    CampAvatarFallbackAsset(
      family: CampAvatarFamily.adultMasculine,
      ageBand: CampAvatarAgeBand.age50,
      path: 'assets/living_camp/v1/raster/actors/male_age_50_idle.png',
    ),
    CampAvatarFallbackAsset(
      family: CampAvatarFamily.adultMasculine,
      ageBand: CampAvatarAgeBand.age70,
      path: 'assets/living_camp/v1/raster/actors/male_age_70_idle.png',
    ),
  ];

  /// The fallback deliberately has one stable pose. Semantic action routing
  /// remains owned by the versioned Rive contract, not by this raster layer.
  static CampAvatarFallbackAsset resolve({
    required CampAvatarFamily family,
    CampAvatarAgeBand ageBand = CampAvatarAgeBand.age30,
    CampAvatarAction action = CampAvatarAction.idle,
  }) => assets.firstWhere(
    (asset) => asset.family == family && asset.ageBand == ageBand,
    orElse: () => assets.firstWhere(
      (asset) =>
          asset.family == family && asset.ageBand == CampAvatarAgeBand.age30,
    ),
  );
}

class CampAvatarFallback extends StatefulWidget {
  const CampAvatarFallback({
    super.key,
    required this.family,
    required this.motionEnabled,
    this.ageBand = CampAvatarAgeBand.age30,
    this.action = CampAvatarAction.idle,
  });

  final CampAvatarFamily family;
  final CampAvatarAgeBand ageBand;
  final CampAvatarAction action;
  final bool motionEnabled;

  @override
  State<CampAvatarFallback> createState() => _CampAvatarFallbackState();
}

class _CampAvatarFallbackState extends State<CampAvatarFallback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _syncMotion();
  }

  @override
  void didUpdateWidget(CampAvatarFallback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motionEnabled != widget.motionEnabled) _syncMotion();
  }

  void _syncMotion() {
    if (widget.motionEnabled) {
      // A compact one-time settle keeps the bridge visually alive without a
      // permanent ticker. The real Rive actor owns continuous loops later.
      _controller.forward(from: 0);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asset = CampAvatarFallbackCatalog.resolve(
      family: widget.family,
      ageBand: widget.ageBand,
      action: widget.action,
    );
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        child: Image.asset(asset.path, fit: BoxFit.contain),
        builder: (context, child) => Transform.translate(
          offset: Offset(0, -3 * Curves.easeInOut.transform(_controller.value)),
          child: child,
        ),
      ),
    );
  }
}
