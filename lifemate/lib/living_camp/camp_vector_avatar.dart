import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'camp_avatar_fallback.dart';

/// Free, source-editable vector actor for the adult Living Camp PoC.
/// Scene position and navigation remain with [CampSceneRenderer].
class CampVectorAvatar extends StatefulWidget {
  const CampVectorAvatar({
    super.key,
    required this.family,
    required this.motionEnabled,
    this.action = CampAvatarAction.idle,
    this.skinTone = const Color(0xFFC99572),
    this.commandId,
    this.onActionComplete,
  });

  final CampAvatarFamily family;
  final CampAvatarAction action;
  final bool motionEnabled;
  final Color skinTone;
  final String? commandId;
  final void Function(CampAvatarAction action, String? commandId)?
  onActionComplete;

  @override
  State<CampVectorAvatar> createState() => _CampVectorAvatarState();
}

class _CampVectorAvatarState extends State<CampVectorAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  CampAvatarAction _shownAction = CampAvatarAction.idle;
  bool _playing = false;

  bool get _canMove =>
      widget.motionEnabled &&
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener(_onStatus);
    _shownAction = widget.action;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion(restart: true);
  }

  @override
  void didUpdateWidget(CampVectorAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action != widget.action ||
        oldWidget.commandId != widget.commandId ||
        oldWidget.motionEnabled != widget.motionEnabled) {
      _shownAction = widget.action;
      _syncMotion(restart: true);
    }
  }

  void _syncMotion({required bool restart}) {
    if (!_canMove) {
      _playing = false;
      _controller.stop();
      _controller.value = 0;
      final completed = _shownAction;
      if (completed == CampAvatarAction.drink ||
          completed == CampAvatarAction.wellness) {
        final commandId = widget.commandId;
        _shownAction = CampAvatarAction.idle;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onActionComplete?.call(completed, commandId);
        });
      }
      return;
    }
    if (!restart && _playing) return;
    _playing = true;
    _controller.stop();
    _controller.duration = switch (_shownAction) {
      CampAvatarAction.idle => const Duration(milliseconds: 2800),
      CampAvatarAction.walk => const Duration(milliseconds: 980),
      CampAvatarAction.drink => const Duration(milliseconds: 1600),
      CampAvatarAction.wellness => const Duration(milliseconds: 1800),
    };
    if (_shownAction == CampAvatarAction.walk) {
      _controller.repeat();
    } else {
      _controller.forward(from: 0);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_canMove) return;
    final completed = _shownAction;
    if (completed != CampAvatarAction.drink &&
        completed != CampAvatarAction.wellness) {
      return;
    }
    setState(() => _shownAction = CampAvatarAction.idle);
    _syncMotion(restart: true);
    widget.onActionComplete?.call(completed, widget.commandId);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          key: const ValueKey('camp-vector-avatar-paint'),
          painter: _AvatarPainter(
            family: widget.family,
            action: _canMove ? _shownAction : CampAvatarAction.idle,
            progress: _canMove ? _controller.value : 0,
            skinTone: widget.skinTone,
          ),
          size: Size.infinite,
        ),
      ),
    ),
  );
}

class _AvatarPainter extends CustomPainter {
  const _AvatarPainter({
    required this.family,
    required this.action,
    required this.progress,
    required this.skinTone,
  });

  final CampAvatarFamily family;
  final CampAvatarAction action;
  final double progress;
  final Color skinTone;

  static const _sourceSize = Size(420, 620);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / _sourceSize.width,
      size.height / _sourceSize.height,
    );
    final feminine = family == CampAvatarFamily.adultFeminine;
    final jacket = feminine ? const Color(0xFFA66E57) : const Color(0xFF71866D);
    final jacketLight = feminine
        ? const Color(0xFFBD866B)
        : const Color(0xFF8FA080);
    final pants = feminine ? const Color(0xFF607064) : const Color(0xFF4C6763);
    final hair = feminine ? const Color(0xFF473831) : const Color(0xFF3E3834);
    final shadowSkin = Color.lerp(skinTone, const Color(0xFF754C3A), .21)!;
    final wave = math.sin(progress * math.pi * 2);
    final walk = action == CampAvatarAction.walk ? wave : 0.0;
    final breathe = action == CampAvatarAction.idle ? wave * 1.4 : 0.0;
    final gesture =
        action == CampAvatarAction.drink || action == CampAvatarAction.wellness
        ? Curves.easeInOut.transform(
            progress <= .5 ? progress * 2 : (1 - progress) * 2,
          )
        : 0.0;
    final bob = action == CampAvatarAction.walk
        ? math.sin(progress * math.pi * 4).abs() * 3
        : 0.0;
    canvas.translate(0, -bob);

    _leg(canvas, 220, 339, -walk * .13, pants.withValues(alpha: .86), false);
    _leg(canvas, 181, 342, walk * .16, pants, true);
    _rearArm(
      canvas,
      jacket,
      shadowSkin,
      -walk * .11,
      action == CampAvatarAction.wellness ? gesture : 0,
    );
    _torso(canvas, jacket, jacketLight, breathe);
    _head(canvas, feminine, skinTone, shadowSkin, hair, breathe);
    _frontArm(
      canvas,
      jacket,
      skinTone,
      walk,
      gesture,
      action == CampAvatarAction.drink,
      action == CampAvatarAction.wellness,
    );
    canvas.restore();
  }

  void _shape(Canvas c, Path p, Color color) =>
      c.drawPath(p, Paint()..color = color);

  void _stroke(Canvas c, Path p, Color color, double width) => c.drawPath(
    p,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );

  void _leg(
    Canvas c,
    double x,
    double y,
    double angle,
    Color pants,
    bool foreground,
  ) {
    c.save();
    c.translate(x, y);
    c.rotate(angle);
    _shape(
      c,
      Path()
        ..moveTo(-16, 0)
        ..quadraticBezierTo(12, -5, 20, 4)
        ..lineTo(13, 190)
        ..lineTo(-13, 191)
        ..quadraticBezierTo(-20, 100, -16, 0),
      pants,
    );
    _stroke(
      c,
      Path()
        ..moveTo(1, 30)
        ..quadraticBezierTo(-5, 103, 4, 173),
      foreground ? const Color(0xFF3B5652) : const Color(0xFF435854),
      3,
    );
    _shape(
      c,
      Path()
        ..moveTo(-12, 183)
        ..lineTo(13, 183)
        ..lineTo(17, 210)
        ..quadraticBezierTo(31, 218, 40, 226)
        ..quadraticBezierTo(43, 234, 30, 235)
        ..lineTo(-11, 235)
        ..quadraticBezierTo(-22, 231, -17, 216)
        ..close(),
      foreground ? const Color(0xFF9A6D50) : const Color(0xFF87624B),
    );
    _stroke(
      c,
      Path()
        ..moveTo(-14, 227)
        ..quadraticBezierTo(6, 234, 37, 229),
      const Color(0xFF624839),
      3,
    );
    c.restore();
  }

  void _rearArm(
    Canvas c,
    Color jacket,
    Color hand,
    double walk,
    double stretch,
  ) {
    c.save();
    c.translate(165, 239);
    c.rotate(walk - stretch * .34);
    _stroke(
      c,
      Path()
        ..moveTo(3, 8)
        ..quadraticBezierTo(-18, 45, -12, 103),
      jacket,
      25,
    );
    c.drawCircle(const Offset(-12, 113), 10, Paint()..color = hand);
    c.restore();
  }

  void _torso(Canvas c, Color jacket, Color light, double breathe) {
    c.save();
    c.translate(0, breathe);
    _shape(
      c,
      Path()
        ..moveTo(184, 226)
        ..quadraticBezierTo(211, 240, 231, 226)
        ..lineTo(255, 348)
        ..quadraticBezierTo(215, 370, 168, 348)
        ..close(),
      const Color(0xFFF3E8D7),
    );
    _shape(
      c,
      Path()
        ..moveTo(183, 225)
        ..quadraticBezierTo(159, 228, 157, 264)
        ..lineTo(169, 349)
        ..quadraticBezierTo(183, 361, 202, 356)
        ..lineTo(197, 246)
        ..close(),
      jacket,
    );
    _shape(
      c,
      Path()
        ..moveTo(222, 225)
        ..quadraticBezierTo(254, 224, 259, 260)
        ..lineTo(255, 349)
        ..quadraticBezierTo(237, 361, 213, 356)
        ..lineTo(207, 247)
        ..close(),
      jacket,
    );
    _shape(
      c,
      Path()
        ..moveTo(185, 226)
        ..lineTo(199, 247)
        ..lineTo(183, 283)
        ..lineTo(172, 250)
        ..close(),
      light,
    );
    _shape(
      c,
      Path()
        ..moveTo(221, 226)
        ..lineTo(206, 248)
        ..lineTo(225, 284)
        ..lineTo(239, 250)
        ..close(),
      light,
    );
    _stroke(
      c,
      Path()
        ..moveTo(207, 250)
        ..lineTo(210, 353),
      const Color(0xFF526657),
      2.5,
    );
    c.restore();
  }

  void _head(
    Canvas c,
    bool feminine,
    Color skin,
    Color shade,
    Color hair,
    double breathe,
  ) {
    c.save();
    c.translate(0, breathe);
    if (feminine) {
      _shape(
        c,
        Path()
          ..moveTo(180, 156)
          ..cubicTo(167, 175, 165, 225, 179, 260)
          ..quadraticBezierTo(187, 269, 195, 255)
          ..lineTo(228, 253)
          ..quadraticBezierTo(246, 259, 250, 238)
          ..cubicTo(255, 199, 249, 158, 239, 140)
          ..close(),
        hair,
      );
    }
    _shape(
      c,
      Path()
        ..moveTo(193, 209)
        ..lineTo(222, 207)
        ..lineTo(225, 236)
        ..quadraticBezierTo(209, 246, 190, 233)
        ..close(),
      skin,
    );
    c.drawOval(const Rect.fromLTWH(222, 164, 15, 25), Paint()..color = shade);
    _shape(
      c,
      Path()
        ..moveTo(177, 152)
        ..cubicTo(183, 127, 204, 117, 224, 126)
        ..cubicTo(243, 136, 246, 159, 239, 183)
        ..cubicTo(232, 206, 218, 219, 201, 216)
        ..cubicTo(181, 212, 171, 186, 173, 166)
        ..close(),
      skin,
    );
    _shape(
      c,
      Path()
        ..moveTo(224, 135)
        ..cubicTo(240, 150, 237, 188, 223, 204)
        ..quadraticBezierTo(213, 215, 201, 216)
        ..cubicTo(227, 221, 243, 192, 243, 166)
        ..quadraticBezierTo(242, 142, 224, 135),
      shade.withValues(alpha: .34),
    );
    _shape(
      c,
      Path()
        ..moveTo(172, 160)
        ..cubicTo(165, 138, 178, 116, 198, 112)
        ..cubicTo(224, 105, 244, 124, 244, 151)
        ..quadraticBezierTo(225, 147, 214, 131)
        ..quadraticBezierTo(200, 149, 172, 154)
        ..close(),
      hair,
    );
    _stroke(
      c,
      Path()
        ..moveTo(183, 169)
        ..quadraticBezierTo(191, 164, 199, 168),
      hair,
      2.6,
    );
    _stroke(
      c,
      Path()
        ..moveTo(212, 169)
        ..quadraticBezierTo(219, 165, 225, 169),
      hair,
      2.4,
    );
    _stroke(
      c,
      Path()
        ..moveTo(186, 177)
        ..quadraticBezierTo(192, 180, 199, 177),
      const Color(0xFF493A34),
      2,
    );
    _stroke(
      c,
      Path()
        ..moveTo(214, 176)
        ..lineTo(222, 176),
      const Color(0xFF493A34),
      2,
    );
    _stroke(
      c,
      Path()
        ..moveTo(207, 176)
        ..quadraticBezierTo(203, 186, 211, 188),
      shade,
      1.7,
    );
    _stroke(
      c,
      Path()
        ..moveTo(198, 197)
        ..quadraticBezierTo(207, 202, 216, 195),
      const Color(0xFF965F53),
      2,
    );
    c.restore();
  }

  void _frontArm(
    Canvas c,
    Color jacket,
    Color skin,
    double walk,
    double gesture,
    bool drinking,
    bool wellness,
  ) {
    final handX = drinking
        ? 279 - 51 * gesture
        : wellness
        ? 279 - 68 * gesture
        : 279 + walk * 5;
    final handY = drinking
        ? 334 - 128 * gesture
        : wellness
        ? 334 - 70 * gesture
        : 334 - walk * 2;
    final elbowX =
        267 +
        (drinking
            ? 4 * gesture
            : wellness
            ? 13 * gesture
            : walk * 4);
    final elbowY =
        289 -
        (drinking
            ? 28 * gesture
            : wellness
            ? 12 * gesture
            : 0.0);
    _stroke(
      c,
      Path()
        ..moveTo(251, 246)
        ..quadraticBezierTo(elbowX, 255, elbowX, elbowY),
      jacket,
      26,
    );
    _stroke(
      c,
      Path()
        ..moveTo(elbowX, elbowY)
        ..lineTo(handX, handY - 9),
      skin,
      16,
    );
    c.drawCircle(Offset(handX, handY), 10, Paint()..color = skin);
    if (drinking || (!wellness && action == CampAvatarAction.idle)) {
      final cupX = handX + 17;
      final cupY = handY - 11;
      _shape(
        c,
        Path()
          ..moveTo(cupX - 11, cupY)
          ..lineTo(cupX + 13, cupY)
          ..lineTo(cupX + 9, cupY + 31)
          ..quadraticBezierTo(cupX, cupY + 37, cupX - 7, cupY + 30)
          ..close(),
        const Color(0xFFDCC8A8),
      );
      _stroke(
        c,
        Path()
          ..moveTo(cupX + 13, cupY + 7)
          ..cubicTo(
            cupX + 29,
            cupY + 1,
            cupX + 29,
            cupY + 27,
            cupX + 12,
            cupY + 26,
          ),
        const Color(0xFFDCC8A8),
        4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarPainter oldDelegate) =>
      oldDelegate.family != family ||
      oldDelegate.action != action ||
      oldDelegate.progress != progress ||
      oldDelegate.skinTone != skinTone;
}
