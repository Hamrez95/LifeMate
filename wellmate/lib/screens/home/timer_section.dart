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
    if (totalSeconds <= 0) return "الان!";
    final h = (totalSeconds ~/ 3600);
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    if (h > 0) return "$h:$m:$s";
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final isNow = secondsLeft <= 0;

    return Stack(
      alignment: Alignment.center,
      children: [
        // پس‌زمینه با سایه‌های نرم (Neumorphism ملایم)
        Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              const BoxShadow(
                  color: Colors.white,
                  offset: Offset(-10, -10),
                  blurRadius: 20),
              BoxShadow(
                  color: Colors.green.withOpacity(0.08), // سایه سبز ملایم
                  offset: const Offset(10, 10),
                  blurRadius: 20),
            ],
          ),
        ),
        SizedBox(
          width: 200,
          height: 200,
          child: CustomPaint(painter: _SoftTimerPainter(progress: progress)),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(titleText,
                style:
                    font.copyWith(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 8),
            Text(
              _formatDuration(secondsLeft).toPersianDigit(isPersian),
              style: font.copyWith(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                color: isNow
                    ? Colors.red.shade400
                    : Colors.green.shade700, // اگر زمان رسیده قرمز شود
                height: 1.0,
              ),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                medicineName.toPersianDigit(isPersian),
                style: font.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800),
              ),
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
      ..color = Colors.green.shade50 // رنگ مسیر خنثی
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    final progressPaint = Paint()
      ..color = Colors.green.shade400 // رنگ پیشرفت تایمر
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
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
