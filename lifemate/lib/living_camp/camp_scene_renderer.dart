import 'dart:math' as math;

import 'package:flutter/material.dart';

@immutable
class CampWorldSize {
  const CampWorldSize({this.width = 1000, this.height = 2000});

  final double width;
  final double height;
}

@immutable
class CampPoint {
  const CampPoint(this.x, this.y);

  final double x;
  final double y;
}

@immutable
class CampRect {
  const CampRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

enum CampZoneAvailability { active, locked, expired, unavailable }

@immutable
class CampZoneVisual {
  const CampZoneVisual({
    required this.stage,
    required this.variant,
    required this.builder,
  });

  final int stage;
  final String variant;
  final WidgetBuilder builder;
}

@immutable
class CampZoneDefinition {
  const CampZoneDefinition({
    required this.zoneId,
    required this.bounds,
    required this.semanticLabel,
    required this.visuals,
    this.defaultStage = 1,
    this.defaultVariant = 'default',
  });

  final String zoneId;
  final CampRect bounds;
  final String semanticLabel;
  final List<CampZoneVisual> visuals;
  final int defaultStage;
  final String defaultVariant;

  CampZoneVisual resolveVisual({int? stage, String? variant}) {
    final requestedStage = stage ?? defaultStage;
    final requestedVariant = variant ?? defaultVariant;

    CampZoneVisual? exact;
    CampZoneVisual? stageDefault;
    CampZoneVisual? fallback;
    for (final visual in visuals) {
      if (visual.stage == requestedStage &&
          visual.variant == requestedVariant) {
        exact = visual;
        break;
      }
      if (visual.stage == requestedStage && visual.variant == defaultVariant) {
        stageDefault = visual;
      }
      if (visual.stage == defaultStage && visual.variant == defaultVariant) {
        fallback = visual;
      }
    }
    return exact ?? stageDefault ?? fallback ?? visuals.first;
  }
}

@immutable
class CampZonePresentation {
  const CampZonePresentation({
    required this.zoneId,
    this.stage,
    this.variant,
    this.availability = CampZoneAvailability.active,
    this.stateLabel,
  });

  final String zoneId;
  final int? stage;
  final String? variant;
  final CampZoneAvailability availability;

  /// Localized normalized wording from a reviewed presentation adapter.
  /// It must not contain raw enrollment, consent, or health details.
  final String? stateLabel;
}

/// Presentation-only state. Camp never derives it from raw domain records;
/// `stage` remains independent so expiry never erases a zone's visual stage.
@immutable
class CampZoneStatePresentation {
  const CampZoneStatePresentation({
    required this.availability,
    required this.label,
  });

  final CampZoneAvailability availability;
  final String label;
}

@immutable
class CampSceneLayer {
  const CampSceneLayer({
    required this.id,
    required this.zIndex,
    required this.builder,
  });

  final String id;
  final int zIndex;
  final WidgetBuilder builder;
}

/// A presentation-only actor anchored in world coordinates. It has no hit
/// target: zone semantics and navigation stay outside decorative animation.
@immutable
class CampSceneActor {
  const CampSceneActor({
    required this.actorId,
    required this.anchor,
    required this.width,
    required this.height,
    required this.builder,
  });

  final String actorId;
  final CampPoint anchor;
  final double width;
  final double height;
  final WidgetBuilder builder;
}

class CampSceneRenderer extends StatelessWidget {
  const CampSceneRenderer({
    super.key,
    required this.zones,
    required this.presentations,
    required this.layers,
    this.actors = const [],
    this.worldSize = const CampWorldSize(),
    this.onZoneTap,
  });

  final List<CampZoneDefinition> zones;
  final List<CampZonePresentation> presentations;
  final List<CampSceneLayer> layers;
  final List<CampSceneActor> actors;
  final CampWorldSize worldSize;
  final ValueChanged<String>? onZoneTap;

  CampZonePresentation _presentationFor(String zoneId) {
    for (final presentation in presentations) {
      if (presentation.zoneId == zoneId) return presentation;
    }
    return CampZonePresentation(
      zoneId: zoneId,
      availability: CampZoneAvailability.unavailable,
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderedLayers = [...layers]
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    final orderedActors = [...actors]
      ..sort((a, b) => a.anchor.y.compareTo(b.anchor.y));
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.max(
          constraints.maxWidth / worldSize.width,
          constraints.maxHeight / worldSize.height,
        );
        final renderedWidth = worldSize.width * scale;
        final renderedHeight = worldSize.height * scale;
        final offsetX = (constraints.maxWidth - renderedWidth) / 2;
        final offsetY = (constraints.maxHeight - renderedHeight) / 2;

        Offset worldToScreen(CampPoint point) {
          return Offset(offsetX + point.x * scale, offsetY + point.y * scale);
        }

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final layer in orderedLayers) layer.builder(context),
              for (final zone in zones)
                _buildZone(
                  context,
                  zone,
                  _presentationFor(zone.zoneId),
                  scale,
                  worldToScreen,
                ),
              for (final actor in orderedActors)
                _buildActor(context, actor, scale, worldToScreen),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActor(
    BuildContext context,
    CampSceneActor actor,
    double scale,
    Offset Function(CampPoint) worldToScreen,
  ) {
    final ground = worldToScreen(actor.anchor);
    return Positioned(
      key: ValueKey<String>('camp-actor-${actor.actorId}'),
      left: ground.dx - actor.width * scale / 2,
      top: ground.dy - actor.height * scale,
      width: actor.width * scale,
      height: actor.height * scale,
      child: IgnorePointer(child: actor.builder(context)),
    );
  }

  Widget _buildZone(
    BuildContext context,
    CampZoneDefinition zone,
    CampZonePresentation presentation,
    double scale,
    Offset Function(CampPoint) worldToScreen,
  ) {
    final topLeft = worldToScreen(CampPoint(zone.bounds.left, zone.bounds.top));
    final visual = zone.resolveVisual(
      stage: presentation.stage,
      variant: presentation.variant,
    );
    final statePresentation = _statePresentation(presentation);

    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: zone.bounds.width * scale,
      height: zone.bounds.height * scale,
      child: Semantics(
        button: true,
        enabled: onZoneTap != null,
        label: '${zone.semanticLabel}, ${statePresentation.label}',
        child: GestureDetector(
          key: ValueKey<String>('camp-zone-hit-${zone.zoneId}'),
          behavior: HitTestBehavior.opaque,
          onTap: onZoneTap == null ? null : () => onZoneTap!(zone.zoneId),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: switch (presentation.availability) {
                  CampZoneAvailability.active => 1,
                  CampZoneAvailability.locked => 0.72,
                  CampZoneAvailability.expired => 0.58,
                  CampZoneAvailability.unavailable => 0.45,
                },
                child: visual.builder(context),
              ),
              if (presentation.availability != CampZoneAvailability.active)
                _ZoneStateBadge(presentation: statePresentation),
            ],
          ),
        ),
      ),
    );
  }

  CampZoneStatePresentation _statePresentation(
    CampZonePresentation presentation,
  ) {
    return switch (presentation.availability) {
      CampZoneAvailability.active => CampZoneStatePresentation(
        availability: CampZoneAvailability.active,
        label: presentation.stateLabel ?? 'Available',
      ),
      CampZoneAvailability.locked => CampZoneStatePresentation(
        availability: CampZoneAvailability.locked,
        label: presentation.stateLabel ?? 'Locked',
      ),
      CampZoneAvailability.expired => CampZoneStatePresentation(
        availability: CampZoneAvailability.expired,
        label: presentation.stateLabel ?? 'Currently closed',
      ),
      CampZoneAvailability.unavailable => CampZoneStatePresentation(
        availability: CampZoneAvailability.unavailable,
        label: presentation.stateLabel ?? 'Coming soon',
      ),
    };
  }
}

class _ZoneStateBadge extends StatelessWidget {
  const _ZoneStateBadge({required this.presentation});

  final CampZoneStatePresentation presentation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = switch (presentation.availability) {
      CampZoneAvailability.locked => Icons.lock_outline_rounded,
      CampZoneAvailability.expired => Icons.nights_stay_outlined,
      CampZoneAvailability.unavailable => Icons.construction_outlined,
      CampZoneAvailability.active => Icons.check_circle_outline,
    };
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsetsDirectional.fromSTEB(8, 5, 10, 5),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14),
              const SizedBox(width: 4),
              Text(
                presentation.label,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CampPlaceholderVisual extends StatelessWidget {
  const CampPlaceholderVisual({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: colors.primary),
              const SizedBox(height: 8),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}
