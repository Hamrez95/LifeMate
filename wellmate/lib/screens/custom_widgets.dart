import 'package:flutter/material.dart';

// Neumorphic Timer Painter
class _NeumorphicTimerPainter extends CustomPainter {
  final double progress;
  final Color color;
  _NeumorphicTimerPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint base = Paint()
      ..color = Colors.grey[200]!
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke;
    final Paint shadow = Paint()
      ..color = Colors.white
      ..strokeWidth = 18
      ..style = PaintingStyle.stroke;
    final Paint progressPaint = Paint()
      ..color = color
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    canvas.drawCircle(center, radius, shadow);
    canvas.drawCircle(center, radius, base);
    final double sweep = 2 * 3.141592653589793 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.141592653589793 / 2,
      sweep,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Schedule Card Widget
class _ScheduleCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final double progress;
  const _ScheduleCard({required this.name, required this.icon, required this.color, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 18),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: color.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(8),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom bottom navigation bar with floating add button
class _CustomBottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 8, left: 12, right: 12, bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.home_rounded, size: 32),
                color: const Color(0xFF4A90E2),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.person_rounded, size: 28),
                color: Colors.grey[400],
                onPressed: () {},
              ),
              const SizedBox(width: 60),
              IconButton(
                icon: const Icon(Icons.event_note_rounded, size: 28),
                color: Colors.grey[400],
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.medication_liquid_rounded, size: 28),
                color: Colors.grey[400],
                onPressed: () {},
              ),
            ],
          ),
          Positioned(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF4A90E2),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueGrey.withOpacity(0.18),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.white, size: 38),
                onPressed: () {},
                tooltip: 'Add Medicine',
              ),
            ),
            bottom: 0,
            left: 0,
            right: 0,
          ),
        ],
      ),
    );
  }
}
