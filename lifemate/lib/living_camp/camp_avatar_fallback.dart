import 'package:flutter/material.dart';

/// Raster-only visual fallback while the #1074 Rive actor is being authored.
///
/// This is intentionally presentation-only. It neither claims Rive action
/// support nor provides a skin-tone tint: tinting a flattened illustration
/// would incorrectly recolour hair and clothing. The future Rive adapter can
/// replace this widget without changing actor identity or world placement.
enum CampAvatarFamily { adultFeminine, adultMasculine }

enum CampAvatarAction { idle, walk, drink, wellness }

@immutable
class CampAvatarFallbackAsset {
  const CampAvatarFallbackAsset({required this.family, required this.path});

  final CampAvatarFamily family;
  final String path;
}

class CampAvatarFallbackCatalog {
  CampAvatarFallbackCatalog._();

  static const assets = <CampAvatarFallbackAsset>[
    CampAvatarFallbackAsset(
      family: CampAvatarFamily.adultFeminine,
      path: 'assets/living_camp/v1/raster/actors/adult_female_idle.png',
    ),
    CampAvatarFallbackAsset(
      family: CampAvatarFamily.adultMasculine,
      path: 'assets/living_camp/v1/raster/actors/adult_male_idle.png',
    ),
  ];

  /// The fallback deliberately has one stable pose. Semantic action routing
  /// remains owned by the versioned Rive contract, not by this raster layer.
  static CampAvatarFallbackAsset resolve({
    required CampAvatarFamily family,
    CampAvatarAction action = CampAvatarAction.idle,
  }) => assets.firstWhere((asset) => asset.family == family);
}

class CampAvatarFallback extends StatefulWidget {
  const CampAvatarFallback({
    super.key,
    required this.family,
    required this.motionEnabled,
    this.action = CampAvatarAction.idle,
  });

  final CampAvatarFamily family;
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
      _controller.repeat(reverse: true);
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
