import 'package:flutter/material.dart';
import 'package:wellmate/core/theme/app_style.dart';
import '../../../models/schedule_item_model.dart';
import '../../../core/utils/string_extensions.dart';
import 'calendar_utils.dart';

class ScheduleItemCard extends StatelessWidget {
  final ScheduleItemModel item;
  final dynamic loc;
  final bool isPersian;
  final bool isMissed;
  final bool showDone; // <--- پارامتر جدید

  const ScheduleItemCard({
    Key? key,
    required this.item,
    required this.loc,
    required this.isPersian,
    this.isMissed = false,
    this.showDone = false, // <--- مقدار پیش‌فرض
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final itemColor = isMissed
        ? Colors.red.shade700
        : CalendarUtils.getColorForType(item.type);
    final itemIcon = isMissed
        ? Icons.warning_amber_rounded
        : CalendarUtils.getIconForType(item.type);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isMissed ? Colors.red.shade50 : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: isMissed ? Border.all(color: Colors.red.shade200) : null,
        boxShadow: [
          BoxShadow(
              color: isMissed
                  ? Colors.red.withOpacity(0.1)
                  : AppColors.shadowDark.withOpacity(0.4),
              offset: const Offset(3, 3),
              blurRadius: 10),
          if (!isMissed)
            BoxShadow(
                color: AppColors.shadowLight,
                offset: const Offset(-3, -3),
                blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: isMissed
                    ? Colors.red.withOpacity(0.1)
                    : itemColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(itemIcon, color: itemColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isMissed) ...[
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.red.shade700, size: 16),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        item.title.toPersianDigit(isPersian),
                        style: AppTextStyles.get(context,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isMissed ? Colors.red.shade900 : null),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (item.dosage.isNotEmpty)
                  Text(
                    "${loc['med_qty'] ?? 'تعداد'}: ${item.dosage.toPersianDigit(isPersian)}",
                    style: AppTextStyles.caption(context).copyWith(
                      color: isMissed ? Colors.red.shade400 : null,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.time.toPersianDigit(isPersian),
                style: AppTextStyles.get(context,
                    color: isMissed ? Colors.red.shade700 : AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
              // استفاده از showDone به جای item.isDone
              if (showDone) ...[
                const SizedBox(height: 4),
                const Icon(Icons.check_circle_rounded,
                    color: Colors.green, size: 20),
              ]
            ],
          ),
        ],
      ),
    );
  }
}
