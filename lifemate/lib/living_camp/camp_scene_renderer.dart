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
  });

  final String zoneId;
  final int? stage;
  final String? variant;
  final CampZoneAvailability availability;
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

class CampSceneRenderer extends StatelessWidget {
  const CampSceneRenderer({
    super.key,
    required this.zones,
    required this.presentations,
    required this.layers,
    this.worldSize = const CampWorldSize(),
    this.onZoneTap,
  });

  final List<CampZoneDefinition> zones;
  final List<CampZonePresentation> presentations;
  final List<CampSceneLayer> layers;
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
            ],
          ),
        );
      },
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
    final enabled = presentation.availability == CampZoneAvailability.active;

    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: zone.bounds.width * scale,
      height: zone.bounds.height * scale,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: zone.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled && onZoneTap != null
              ? () => onZoneTap!(zone.zoneId)
              : null,
          child: Opacity(
            opacity: switch (presentation.availability) {
              CampZoneAvailability.active => 1,
              CampZoneAvailability.locked => 0.72,
              CampZoneAvailability.expired => 0.58,
              CampZoneAvailability.unavailable => 0.45,
            },
            child: visual.builder(context),
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
