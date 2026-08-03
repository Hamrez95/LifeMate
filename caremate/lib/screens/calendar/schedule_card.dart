import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/string_extensions.dart';
import '../../../models/event_model.dart';

class ScheduleCard extends StatelessWidget {
  const ScheduleCard({
    super.key,
    required this.event,
    required this.font,
    required this.isPersian,
  });

  final EventModel event;
  final TextStyle font;
  final bool isPersian;

  bool get _isMedication => event.type == EventType.medicine;

  Map<String, dynamic> _getEventTheme(EventType type) {
    switch (type) {
      case EventType.medicine:
        return {'color': Colors.pinkAccent, 'icon': Icons.medication_rounded};
      case EventType.appointment:
      case EventType.doctor:
        return {
          'color': Colors.blueAccent,
          'icon': Icons.medical_services_rounded,
        };
      case EventType.injection:
      case EventType.checkup:
        return {'color': Colors.orangeAccent, 'icon': Icons.vaccines_rounded};
      case EventType.other:
        return {'color': AppColors.darkBlue, 'icon': Icons.event_rounded};
    }
  }

  DateTime _getEventDateTime(EventModel event) {
    final timeParts = event.time.split(':');
    final hour = int.tryParse(timeParts.first) ?? 0;
    final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;
    return DateTime(
      event.date.year,
      event.date.month,
      event.date.day,
      hour,
      minute,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _getEventTheme(event.type);
    final eventDateTime = _getEventDateTime(event);
    final isPast = eventDateTime.isBefore(DateTime.now());
    final isOverdue = _isMedication &&
        isPast &&
        (event.isCompleted == false || event.isCompleted == null);
    final cardColor = isOverdue ? Colors.amber.shade100 : Colors.white;

    final Widget statusIcon;
    if (!_isMedication) {
      statusIcon = Icon(
        event.type == EventType.injection
            ? Icons.vaccines_outlined
            : Icons.event_available_rounded,
        color: theme['color'] as Color,
      );
    } else if (isPast) {
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
            color: Colors.black.withValues(alpha: 0.03),
            offset: const Offset(2, 4),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (theme['color'] as Color).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              theme['icon'] as IconData,
              color: theme['color'] as Color,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: font.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  event.description != null && event.description!.isNotEmpty
                      ? '${event.time} • ${event.description}'
                          .toPersianDigit(isPersian)
                      : event.time.toPersianDigit(isPersian),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: font.copyWith(
                    fontSize: 13,
                    height: 1.45,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          statusIcon,
        ],
      ),
    );
  }
}
