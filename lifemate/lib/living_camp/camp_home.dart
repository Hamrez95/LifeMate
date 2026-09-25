import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'camp_asset_catalog.dart';
import 'camp_avatar_fallback.dart';
import 'camp_vector_avatar.dart';
import 'camp_environment.dart';
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
        const CampRect(left: 285, top: 320, width: 430, height: 405),
        _t('LifeMate home', 'خانه LifeMate'),
      ),
      _zone(
        'wellmate',
        const CampRect(left: 75, top: 450, width: 300, height: 290),
        'WellMate',
      ),
      _zone(
        'caremate',
        const CampRect(left: 625, top: 475, width: 300, height: 315),
        'CareMate',
      ),
      _zone(
        'reproductive_context',
        const CampRect(left: 65, top: 815, width: 325, height: 320),
        _t('Cocoon / Women Health', 'Cocoon / سلامت زنان'),
      ),
      _zone(
        'fitmate',
        const CampRect(left: 585, top: 1250, width: 400, height: 345),
        _t('FitMate', 'فیت‌میت'),
      ),
    ];

    final defaultPresentations = <CampZonePresentation>[
      CampZonePresentation(
        zoneId: 'lifemate_home',
        stateLabel: _t('Open', 'باز'),
      ),
      CampZonePresentation(zoneId: 'wellmate', stateLabel: _t('Open', 'باز')),
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
        return ColoredBox(
          color: const Color(0xFF142B3A),
          child: Stack(
            children: [
              Positioned.fill(
                child: _CampDaylight(
                  factor: environment.daylightFactor,
                  child: CampSceneRenderer(
                    zones: zones,
                    presentations: presentations,
                    actors: [
                      CampSceneActor(
                        actorId: 'main_avatar_vector',
                        anchor: const CampPoint(505, 1135),
                        width: 145,
                        height: 210,
                        builder: (_) => _CampRoamingAvatar(
                          motionEnabled: environment.motionEnabled,
                        ),
                      ),
                      CampSceneActor(
                        actorId: 'moon_garden_decoration',
                        anchor: const CampPoint(830, 1150),
                        width: 330,
                        height: 300,
                        builder: (_) => Image.asset(
                          CampAssetCatalog.moonGarden,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ],
                    layers: [
                      CampSceneLayer(
                        id: 'background',
                        zIndex: 0,
                        builder: (_) => _CampBackdrop(
                          motionEnabled: environment.motionEnabled,
                          daylightFactor: environment.daylightFactor,
                        ),
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
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 60,
                left: 20,
                right: 20,
                child: _CampWelcome(
                  isPersian: isPersian,
                  isNight: environment.phase == CampDayPhase.night,
                  onOpenToday: onOpenToday,
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
          builder: (_) => ExcludeSemantics(
            child: _CampZoneVisual(zoneId: id, label: label),
          ),
        ),
      ],
    );
  }
}

class _CampWelcome extends StatelessWidget {
  const _CampWelcome({
    required this.isPersian,
    required this.isNight,
    required this.onOpenToday,
  });

  final bool isPersian;
  final bool isNight;
  final VoidCallback onOpenToday;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: IgnorePointer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isNight
                    ? (isPersian ? 'شب بخیر،' : 'Good evening,')
                    : (isPersian ? 'روز بخیر،' : 'Good day,'),
                style: const TextStyle(color: Colors.white, fontSize: 17),
              ),
              Text(
                isPersian ? 'خوش آمدی 👋' : 'Welcome back 👋',
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  shadows: [Shadow(color: Color(0xAA10212F), blurRadius: 9)],
                ),
              ),
              Text(
                isPersian ? 'کمپ زنده' : 'Living Camp',
                style: const TextStyle(color: Color(0xFFEEECE3), fontSize: 14),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 8),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 152),
        child: Material(
          color: const Color(0xE42A3444),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            key: const ValueKey('camp-today-card'),
            onTap: onOpenToday,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wb_sunny_rounded, color: Color(0xFFFFD66D)),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isPersian ? 'امروز' : 'Today',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          isPersian ? 'روزت را ببین' : 'See your day',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFD9DEDD),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _CampZoneSign extends StatelessWidget {
  const _CampZoneSign({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xE82A292C),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0x99F3CBA5)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 8)],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

/// Distant terrain drifts a few pixels behind the independently rendered zones.
class _CampBackdrop extends StatefulWidget {
  const _CampBackdrop({
    required this.motionEnabled,
    required this.daylightFactor,
  });

  final bool motionEnabled;
  final double daylightFactor;

  @override
  State<_CampBackdrop> createState() => _CampBackdropState();
}

class _CampBackdropState extends State<_CampBackdrop>
    with TickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();
  late final AnimationController _daylight = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  );
  late Animation<double> _daylightTransition = AlwaysStoppedAnimation(
    widget.daylightFactor,
  );

  @override
  void didUpdateWidget(_CampBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.daylightFactor - widget.daylightFactor).abs() > .0001) {
      final currentFactor = _daylightTransition.value;
      _daylightTransition = Tween<double>(
        begin: currentFactor,
        end: widget.daylightFactor,
      ).animate(CurvedAnimation(parent: _daylight, curve: Curves.easeInOut));
      _daylight.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    _daylight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_drift, _daylight]),
    builder: (context, _) {
      final phase = widget.motionEnabled ? _drift.value * math.pi * 2 : 0.0;
      final daylightFactor = _daylightTransition.value;
      return Transform.translate(
        offset: Offset(math.sin(phase) * 3, math.cos(phase) * 2),
        child: Transform.scale(
          scale: 1.018,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                CampAssetCatalog.backgroundDay,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
              Opacity(
                opacity: 1 - daylightFactor,
                child: Image.asset(
                  CampAssetCatalog.terrainDusk,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              ColoredBox(
                color: Color.lerp(
                  const Color(0x000D1B39),
                  const Color(0x55101A3C),
                  1 - daylightFactor,
                )!,
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The actor actually walks along the path; the vector animation supplies steps.
class _CampRoamingAvatar extends StatefulWidget {
  const _CampRoamingAvatar({required this.motionEnabled});

  final bool motionEnabled;

  @override
  State<_CampRoamingAvatar> createState() => _CampRoamingAvatarState();
}

class _CampRoamingAvatarState extends State<_CampRoamingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _path =
      AnimationController(vsync: this, duration: const Duration(seconds: 9))
        ..value = .5
        ..addStatusListener(_onPathStatus)
        ..forward();
  CampAvatarAction _action = CampAvatarAction.walk;
  int _command = 0;

  void _onPathStatus(AnimationStatus status) {
    if (!mounted || !widget.motionEnabled) return;
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      setState(() {
        _action = status == AnimationStatus.completed
            ? CampAvatarAction.drink
            : CampAvatarAction.wellness;
        _command++;
      });
    }
  }

  void _onActionComplete(CampAvatarAction action, String? commandId) {
    if (!mounted || commandId != '$_command') return;
    setState(() => _action = CampAvatarAction.walk);
    if (_path.status == AnimationStatus.completed) {
      _path.reverse();
    } else {
      _path.forward();
    }
  }

  @override
  void didUpdateWidget(_CampRoamingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.motionEnabled) {
      _path.stop();
    } else if (!oldWidget.motionEnabled) {
      _action = CampAvatarAction.walk;
      _path.forward();
    }
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _path,
    builder: (context, _) => Transform.translate(
      offset: widget.motionEnabled
          ? Offset(
              (_path.value - .5) * 28,
              -math.sin(_path.value * math.pi) * 8,
            )
          : Offset.zero,
      child: CampVectorAvatar(
        family: CampAvatarFamily.adultMasculine,
        action: widget.motionEnabled ? _action : CampAvatarAction.idle,
        motionEnabled: widget.motionEnabled,
        commandId: '$_command',
        onActionComplete: _onActionComplete,
      ),
    ),
  );
}

/// Each zone stays a separate transparent, hit-tested 2.5D foreground layer.
class _CampZoneVisual extends StatefulWidget {
  const _CampZoneVisual({required this.zoneId, required this.label});

  final String zoneId;
  final String label;

  @override
  State<_CampZoneVisual> createState() => _CampZoneVisualState();
}

class _CampZoneVisualState extends State<_CampZoneVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      AnimatedBuilder(
        animation: _glow,
        builder: (context, _) => Transform.translate(
          offset: Offset(
            math.sin(_glow.value * math.pi * 2) * 1.1,
            math.cos(_glow.value * math.pi * 2) * .8,
          ),
          child: Image.asset(
            CampAssetCatalog.resolve(
              zoneId: widget.zoneId,
              variant: widget.zoneId == 'fitmate'
                  ? 'under_construction'
                  : 'default',
            ).path,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
      AnimatedBuilder(
        animation: _glow,
        builder: (context, _) {
          final daylight = _CampDaylight.maybeOf(context)?.factor ?? 0;
          final night = 1 - daylight;
          return Align(
            alignment: const Alignment(.1, -.1),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFFFFD477,
                    ).withValues(alpha: night * (.08 + _glow.value * .16)),
                    blurRadius: night * (18 + _glow.value * 9),
                    spreadRadius: night * 5,
                  ),
                ],
              ),
            ),
          );
        },
      ),
      _CampZoneSign(label: widget.label),
    ],
  );
}

class _CampDaylight extends InheritedWidget {
  const _CampDaylight({required this.factor, required super.child});

  final double factor;

  static _CampDaylight? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CampDaylight>();

  @override
  bool updateShouldNotify(_CampDaylight oldWidget) =>
      (factor - oldWidget.factor).abs() > .002;
}
