import 'package:flutter/material.dart';
import '../../core/theme/app_style.dart';
import '../../models/schedule_item_model.dart';

class TreatmentQueueWidget extends StatelessWidget {
  final List<ScheduleItemModel> schedules;
  final TextStyle font;

  const TreatmentQueueWidget(
      {Key? key, required this.schedules, required this.font})
      : super(key: key);

  String _calculateTimeDifference(String time) {
    final now = DateTime.now();
    final parts = time.split(':');
    final scheduleTime = DateTime(
        now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));

    if (scheduleTime.isBefore(now)) return "گذشته";

    final diff = scheduleTime.difference(now);
    if (diff.inHours > 0)
      return "${diff.inHours} ساعت و ${diff.inMinutes % 60} دقیقه دیگر";
    return "${diff.inMinutes} دقیقه دیگر";
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = schedules.where((s) => !s.isDone).toList();
    if (upcoming.isEmpty) return const SizedBox();

    final nextItem = upcoming.first;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.timer_outlined, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("نوبت بعدی: ${nextItem.title}",
                    style: font.copyWith(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(_calculateTimeDifference(nextItem.time),
                    style: font.copyWith(
                        color: AppColors.primary, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        ],
      ),
    );
  }
}
