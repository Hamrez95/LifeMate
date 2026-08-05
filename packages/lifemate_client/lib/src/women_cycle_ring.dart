import 'dart:math' as math;

import 'package:flutter/material.dart';

@immutable
class WomenCycleRingSegment {
  const WomenCycleRingSegment({required this.color, required this.weight});

  final Color color;
  final double weight;
}

class WomenCycleRing extends StatelessWidget {
  const WomenCycleRing({
    super.key,
    required this.segments,
    required this.progress,
    required this.center,
    this.size = 190,
    this.strokeWidth = 15,
    this.backgroundColor = const Color(0xFFF2EDF7),
    this.markerColor = Colors.white,
    this.semanticsLabel,
  });

  final List<WomenCycleRingSegment> segments;
  final double progress;
  final Widget center;
  final double size;
  final double strokeWidth;
  final Color backgroundColor;
  final Color markerColor;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = progress.clamp(0.0, 1.0).toDouble();
    return Semantics(
      label: semanticsLabel,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _WomenCycleRingPainter(
                segments: segments,
                progress: effectiveProgress,
                strokeWidth: strokeWidth,
                backgroundColor: backgroundColor,
                markerColor: markerColor,
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints.tightFor(
                width: size - (strokeWidth * 4.1),
                height: size - (strokeWidth * 4.1),
              ),
              child: Center(child: center),
            ),
          ],
        ),
      ),
    );
  }
}

class _WomenCycleRingPainter extends CustomPainter {
  const _WomenCycleRingPainter({
    required this.segments,
    required this.progress,
    required this.strokeWidth,
    required this.backgroundColor,
    required this.markerColor,
  });

  final List<WomenCycleRingSegment> segments;
  final double progress;
  final double strokeWidth;
  final Color backgroundColor;
  final Color markerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final basePaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, basePaint);

    final positive = segments.where((segment) => segment.weight > 0).toList();
    final total = positive.fold<double>(0, (sum, segment) => sum + segment.weight);
    if (total <= 0) return;

    const gap = 0.035;
    var start = -math.pi / 2;
    for (final segment in positive) {
      final rawSweep = math.pi * 2 * (segment.weight / total);
      final sweep = math.max(0.0, rawSweep - gap);
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += rawSweep;
    }

    final angle = -math.pi / 2 + (math.pi * 2 * progress);
    final markerCenter = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(markerCenter, strokeWidth * 0.68, shadowPaint);
    final markerPaint = Paint()..color = markerColor;
    canvas.drawCircle(markerCenter, strokeWidth * 0.56, markerPaint);
    final outlinePaint = Paint()
      ..color = const Color(0xFF9B7BD4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(markerCenter, strokeWidth * 0.56, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _WomenCycleRingPainter oldDelegate) =>
      oldDelegate.segments != segments ||
      oldDelegate.progress != progress ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.markerColor != markerColor;
}
