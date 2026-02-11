import 'dart:math';
import 'package:flutter/material.dart';

// --- 1. Header Widget ---
class HomeHeader extends StatelessWidget {
  final String title;
  final TextStyle font;
  final VoidCallback onProfileTap;

  const HomeHeader({
    Key? key,
    required this.title,
    required this.font,
    required this.onProfileTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _neumorphicContainer(
          padding: 10,
          child: const Icon(Icons.notifications_none_rounded,
              color: Color(0xFF4B5563), size: 24),
        ),
        Text(
          title,
          style: font.copyWith(fontSize: 24, color: const Color(0xFF283054)),
        ),
        GestureDetector(
          onTap: onProfileTap,
          child: _neumorphicContainer(
            padding: 3,
            child: const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFFE2D4C8),
              child: Icon(Icons.person, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _neumorphicContainer({required Widget child, double padding = 8}) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F8),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: Colors.white,
              offset: const Offset(-4, -4),
              blurRadius: 10),
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              offset: const Offset(4, 4),
              blurRadius: 10),
        ],
      ),
      child: child,
    );
  }
}

// --- 2. Timer Section Widget ---
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
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Background Circle (Soft UI)
        Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF2F4F8),
            boxShadow: [
              BoxShadow(
                  color: Colors.white,
                  offset: const Offset(-10, -10),
                  blurRadius: 20),
              BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  offset: const Offset(10, 10),
                  blurRadius: 20),
            ],
          ),
        ),
        // Progress Arc
        SizedBox(
          width: 220,
          height: 220,
          child: CustomPaint(
            painter: _SoftTimerPainter(progress: progress),
          ),
        ),
        // Text Content
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(titleText,
                style: font.copyWith(fontSize: 14, color: const Color(0xFF9EA3B0))),
            const SizedBox(height: 4),
            Text(
              _formatDuration(secondsLeft),
              style: font.copyWith(
                fontSize: 50, // کمی کوچکتر برای جا شدن در فارسی/انگلیسی
                fontWeight: FontWeight.bold,
                color: const Color(0xFF6D7696),
                height: 1.0, // ارتفاع خط برای فیکس کردن فاصله
              ),
            ),
            const SizedBox(height: 8),
            Text(
              medicineName,
              style: font.copyWith(fontSize: 15, color: const Color(0xFFA0A5B5)),
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

    // Track (White Ring)
    final trackPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Progress (Soft Orange/Peach)
    final progressPaint = Paint()
      ..color = const Color(0xFFFDE6D6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round;

    // Start from top (-pi/2)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * 0.35, // مقدار ثابت برای شباهت به عکس (یا progress استفاده کن)
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// --- 3. Button Widget ---
class NeumorphicActionButton extends StatelessWidget {
  final String text;
  final bool isLoading;
  final VoidCallback onTap;
  final TextStyle font;

  const NeumorphicActionButton({
    Key? key,
    required this.text,
    required this.isLoading,
    required this.onTap,
    required this.font,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 55,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: const Color(0xFFF2F4F8),
        border: Border.all(color: Colors.black, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              offset: const Offset(0, 4),
              blurRadius: 8),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : Text(
                    text,
                    style: font.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black),
                  ),
          ),
        ),
      ),
    );
  }
}

// --- 4. Schedule Card Widget ---
class SoftScheduleCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final int index;
  final TextStyle font;

  const SoftScheduleCard({
    Key? key,
    required this.item,
    required this.index,
    required this.font,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color iconBgColor;
    Color barColor;
    IconData iconData;

    // رنگ‌بندی طبق عکس
    if (index % 3 == 0) {
      iconBgColor = const Color(0xFFFFE4E6);
      barColor = const Color(0xFFFB7185);
      iconData = Icons.medication;
    } else if (index % 3 == 1) {
      iconBgColor = const Color(0xFFDBEAFE);
      barColor = const Color(0xFF60A5FA);
      iconData = Icons.medical_services_outlined;
    } else {
      iconBgColor = const Color(0xFFFEF3C7);
      barColor = const Color(0xFFF59E0B);
      iconData = Icons.vaccines;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          const BoxShadow(
              color: Colors.white, offset: Offset(-5, -5), blurRadius: 10),
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              offset: const Offset(5, 5),
              blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(iconData, color: barColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] ?? '',
                  style: font.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1F2937)),
                ),
                const SizedBox(height: 8),
                Stack(
                  children: [
                    Container(
                      height: 6,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: 0.6, // طول تصادفی برای زیبایی
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- 5. Bottom Navigation Widget ---
class GlassBottomNav extends StatelessWidget {
  final String addText;
  final TextStyle font;

  const GlassBottomNav({
    Key? key,
    required this.addText,
    required this.font,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 95, // ارتفاع کلی برای دکمه شناور
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withOpacity(0.0), Colors.white],
        ),
      ),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // نوار اصلی
          Container(
            height: 70,
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF2F7),
              borderRadius: BorderRadius.circular(35),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10)),
                const BoxShadow(
                    color: Colors.white, blurRadius: 10, offset: Offset(0, -5)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _navItem(Icons.home_filled, isActive: true),
                _navItem(Icons.person, isActive: false),
                const SizedBox(width: 60), // جای خالی وسط
                _navItem(Icons.calendar_today_rounded, isActive: false),
                _navItem(Icons.medication_outlined, isActive: false),
              ],
            ),
          ),

          // دکمه وسط (Add Medicine)
          Positioned(
            bottom: 25,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 65,
                  height: 65,
                  decoration: BoxDecoration(
                    color: const Color(0xFF283054),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFF283054).withOpacity(0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: const [
                      Icon(Icons.medication, color: Colors.white, size: 28),
                      Positioned(
                        right: 14,
                        bottom: 14,
                        child: Icon(Icons.add_circle,
                            color: Colors.white, size: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  addText,
                  style: font.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF283054)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, {required bool isActive}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: isActive
          ? BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(14),
            )
          : null,
      child: Icon(
        icon,
        size: 26,
        color: isActive ? Colors.white : const Color(0xFFA0A5B5),
      ),
    );
  }
}
