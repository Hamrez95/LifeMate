import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Soft terrain treatment and footpaths, aligned with the 1000×2000 camp world.
class CampGroundOverlay extends StatelessWidget {
  const CampGroundOverlay({super.key, required this.isNight});

  final bool isNight;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: _CampGroundPainter(isNight),
      child: const SizedBox.expand(),
    ),
  );
}

class _CampGroundPainter extends CustomPainter {
  const _CampGroundPainter(this.isNight);

  final bool isNight;

  @override
  void paint(Canvas canvas, Size size) {
    const world = Size(1000, 2000);
    final scale = math.max(
      size.width / world.width,
      size.height / world.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - world.width * scale) / 2,
      (size.height - world.height * scale) / 2,
    );
    canvas.scale(scale);

    final wash = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .41, .72, 1],
        colors: isNight
            ? const [
                Color(0x44101D2B),
                Color(0x66101D2B),
                Color(0xAA122521),
                Color(0xBB12251F),
              ]
            : const [
                Colors.transparent,
                Color(0x10F5E8CE),
                Color(0x6DD5DFC4),
                Color(0x99B9CFAB),
              ],
      ).createShader(const Rect.fromLTWH(0, 0, 1000, 2000));
    canvas.drawRect(const Rect.fromLTWH(0, 0, 1000, 2000), wash);

    final paths = <Path>[
      Path()
        ..moveTo(507, 1055)
        ..cubicTo(510, 1170, 485, 1250, 498, 1380)
        ..cubicTo(510, 1500, 493, 1635, 495, 1810),
      Path()
        ..moveTo(498, 1330)
        ..cubicTo(395, 1355, 316, 1300, 232, 1260),
      Path()
        ..moveTo(498, 1330)
        ..cubicTo(620, 1370, 704, 1320, 772, 1255),
      Path()
        ..moveTo(500, 1540)
        ..cubicTo(410, 1580, 335, 1625, 258, 1630),
      Path()
        ..moveTo(500, 1540)
        ..cubicTo(605, 1580, 689, 1630, 750, 1640),
    ];
    for (final path in paths) {
      canvas.drawPath(
        path,
        Paint()
          ..color = isNight ? const Color(0x442D352C) : const Color(0x558D8A68)
          ..strokeWidth = 38
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = isNight ? const Color(0x9969705D) : const Color(0xBBCFC9A4)
          ..strokeWidth = 27
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CampGroundPainter oldDelegate) =>
      oldDelegate.isNight != isNight;
}
