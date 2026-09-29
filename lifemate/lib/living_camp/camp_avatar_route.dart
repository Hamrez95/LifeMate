import 'package:flutter/foundation.dart';

import 'camp_avatar_fallback.dart';
import 'camp_scene_renderer.dart';

@immutable
class CampAvatarRouteSample {
  const CampAvatarRouteSample({
    required this.position,
    required this.action,
    required this.commandId,
  });

  final CampPoint position;
  final CampAvatarAction action;
  final String commandId;
}

/// A deterministic home → WellMate wellness visit → home presentation route.
/// Progress is normalized so route timing can be tested without wall-clock time.
abstract final class CampAvatarRoute {
  static const home = CampPoint(505, 790);
  static const wellmateDoor = CampPoint(238, 730);

  static const outbound = <CampPoint>[
    home,
    CampPoint(492, 872),
    CampPoint(420, 914),
    CampPoint(330, 850),
    wellmateDoor,
  ];

  static CampAvatarRouteSample sample(double progress) {
    final p = progress.clamp(0.0, 1.0);
    if (p < .36) {
      return CampAvatarRouteSample(
        position: _along(outbound, _ease(p / .36)),
        action: CampAvatarAction.walk,
        commandId: 'walk-to-wellmate',
      );
    }
    if (p < .43) {
      return const CampAvatarRouteSample(
        position: wellmateDoor,
        action: CampAvatarAction.wellness,
        commandId: 'wellmate-wellness',
      );
    }
    if (p < .50) {
      return const CampAvatarRouteSample(
        position: wellmateDoor,
        action: CampAvatarAction.drink,
        commandId: 'wellmate-drink',
      );
    }
    if (p < .93) {
      return CampAvatarRouteSample(
        position: _along(outbound.reversed.toList(), _ease((p - .50) / .43)),
        action: CampAvatarAction.walk,
        commandId: 'walk-home',
      );
    }
    return const CampAvatarRouteSample(
      position: home,
      action: CampAvatarAction.idle,
      commandId: 'rest-at-home',
    );
  }

  static CampPoint _along(List<CampPoint> points, double progress) {
    final scaled = progress * (points.length - 1);
    final index = scaled.floor().clamp(0, points.length - 2);
    final local = scaled - index;
    final start = points[index];
    final end = points[index + 1];
    return CampPoint(
      start.x + (end.x - start.x) * local,
      start.y + (end.y - start.y) * local,
    );
  }

  static double _ease(double value) => value * value * (3 - 2 * value);
}
