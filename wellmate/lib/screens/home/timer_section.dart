import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/utils/string_extensions.dart'; // مسیر اکستنشن شما

class TimerSection extends StatelessWidget {
  final double progress;
  final int secondsLeft;
  final String medicineName;
  final String titleText;
  final TextStyle font;

  const TimerSection({
    Key? key,
    required this.progress,
    required this.secondsLeft,
    required this.medicineName,
    required this.titleText,
    required this.font,
  }) : super(key: key);

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return "00:00";
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF2F4F8),
            boxShadow: [
              const BoxShadow(
                  color: Colors.white,
                  offset: Offset(-10, -10),
                  blurRadius: 20),
              BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  offset: const Offset(10, 10),
                  blurRadius: 20),
            ],
          ),
        ),
        SizedBox(
          width: 220,
          height: 220,
          child: CustomPaint(painter: _SoftTimerPainter(progress: progress)),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(titleText,
                style: font.copyWith(
                    fontSize: 14, color: const Color(0xFF9EA3B0))),
            const SizedBox(height: 4),
            Text(
              _formatDuration(secondsLeft).toPersianDigit(isPersian),
              style: font.copyWith(
                fontSize: 50,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF6D7696),
                height: 1.0,
              ),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 8),
            Text(
              medicineName.toPersianDigit(isPersian),
              style:
                  font.copyWith(fontSize: 15, color: const Color(0xFFA0A5B5)),
            ),
          ],
        ),
      ],
    );
  }
}

class _SoftTimerPainter extends CustomPainter {
  final double progress;
  _SoftTimerPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2);

    final trackPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    final progressPaint = Paint()
      ..color = const Color(0xFFFDE6D6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
