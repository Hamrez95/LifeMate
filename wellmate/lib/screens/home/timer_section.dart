import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_style.dart';
import '../../../core/utils/string_extensions.dart';

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
    if (h > 0) return "$h:$m";
    return "$m دقیقه";
  }

  @override
  Widget build(BuildContext context) {
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final isNow = secondsLeft <= 0;

    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.background,
        boxShadow: [
          const BoxShadow(
              color: Colors.white, offset: Offset(-8, -8), blurRadius: 20),
          BoxShadow(
              color: AppColors.shadowDark,
              offset: const Offset(8, 8),
              blurRadius: 20),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 210,
            height: 210,
            child: CustomPaint(painter: _SoftTimerPainter(progress: progress)),
          ),
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: AppColors.shadowDark.withOpacity(0.3),
                    offset: const Offset(0, 10),
                    blurRadius: 20),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.monitor_heart_rounded,
                    color: isNow ? Colors.redAccent : AppColors.primary,
                    size: 42),
                const SizedBox(height: 8),
                Text(titleText,
                    style: font.copyWith(
                        fontSize: 14, color: AppColors.textSecondary)),
                Text(medicineName,
                    style: font.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: isNow ? Colors.red.shade50 : AppColors.background,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _formatDuration(secondsLeft).toPersianDigit(isPersian),
                    style: font.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isNow ? Colors.red : AppColors.primary),
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
      ..color = const Color(0xFFE5EFEA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    final progressPaint = Paint()
      ..shader =
          const LinearGradient(colors: [Color(0xFF34D399), Color(0xFF10B981)])
              .createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -pi / 2,
        2 * pi * progress, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
