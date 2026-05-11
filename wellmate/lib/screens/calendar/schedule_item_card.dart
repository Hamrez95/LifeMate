import 'package:flutter/material.dart';
import 'package:wellmate/core/theme/app_style.dart';
import '../../../models/schedule_item_model.dart';
import '../../../core/utils/string_extensions.dart';
import 'calendar_utils.dart';

class ScheduleItemCard extends StatelessWidget {
  final ScheduleItemModel item;
  final dynamic loc;
  final bool isPersian;

  const ScheduleItemCard({
    Key? key,
    required this.item,
    required this.loc,
    required this.isPersian,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final itemColor = CalendarUtils.getColorForType(item.type);
    final itemIcon = CalendarUtils.getIconForType(item.type);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadowDark.withOpacity(0.4),
              offset: const Offset(3, 3),
              blurRadius: 10),
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
                color: itemColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(itemIcon, color: itemColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title.toPersianDigit(isPersian),
                  style: AppTextStyles.get(context,
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                if (item.dosage.isNotEmpty)
                  Text(
                    "${loc['med_qty'] ?? 'تعداد'}: ${item.dosage.toPersianDigit(isPersian)}",
                    style: AppTextStyles.caption(context),
                  ),
              ],
            ),
          ),
          Text(
            item.time.toPersianDigit(isPersian),
            style: AppTextStyles.get(context,
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 14),
          ),
        ],
      ),
    );
  }
}
