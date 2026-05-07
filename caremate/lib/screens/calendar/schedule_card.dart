import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/string_extensions.dart';
import '../../../models/event_model.dart';

class ScheduleCard extends StatelessWidget {
  final EventModel event;
  final TextStyle font;
  final bool isPersian;

  const ScheduleCard({
    Key? key,
    required this.event,
    required this.font,
    required this.isPersian,
  }) : super(key: key);

  // فانکشن‌های کمکی که فقط به این ویجت مربوط هستند
  Map<String, dynamic> _getEventTheme(EventType type) {
    switch (type) {
      case EventType.medicine:
        return {'color': Colors.pinkAccent, 'icon': Icons.medication};
      case EventType.doctor:
        return {'color': Colors.blueAccent, 'icon': Icons.medical_services};
      case EventType.checkup:
        return {'color': Colors.orangeAccent, 'icon': Icons.vaccines};
      case EventType.other:
      default:
        return {'color': AppColors.darkBlue, 'icon': Icons.event};
    }
  }

  DateTime _getEventDateTime(EventModel event) {
    final timeParts = event.time.split(':');
    return DateTime(event.date.year, event.date.month, event.date.day,
        int.parse(timeParts[0]), int.parse(timeParts[1]));
  }

  @override
  Widget build(BuildContext context) {
    final theme = _getEventTheme(event.type);
    final now = DateTime.now();
    final eventDateTime = _getEventDateTime(event);
    final bool isPast = eventDateTime.isBefore(now);
    final bool isOverdue =
        isPast && (event.isCompleted == false || event.isCompleted == null);
    final Color cardColor = isOverdue ? Colors.amber.shade100 : Colors.white;

    final Widget statusIcon;
    if (isPast) {
      statusIcon = event.isCompleted == true
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.cancel, color: Colors.red);
    } else {
      statusIcon =
          const Icon(Icons.access_time_filled_rounded, color: Colors.grey);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              offset: const Offset(2, 4),
              blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (theme['color'] as Color).withOpacity(0.15),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(theme['icon'], color: theme['color'], size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title,
                    style: font.copyWith(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  event.description != null
                      ? '${event.time} - ${event.description}'
                          .toPersianDigit(isPersian)
                      : event.time.toPersianDigit(isPersian),
                  style: font.copyWith(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          statusIcon,
        ],
      ),
    );
  }
}
