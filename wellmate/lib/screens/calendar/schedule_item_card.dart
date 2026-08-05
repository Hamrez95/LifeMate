import 'package:flutter/material.dart';
import 'package:wellmate/core/theme/app_style.dart';

import '../../../core/utils/string_extensions.dart';
import '../../../models/schedule_item_model.dart';
import 'calendar_utils.dart';

class ScheduleItemCard extends StatelessWidget {
  const ScheduleItemCard({
    super.key,
    required this.item,
    required this.loc,
    required this.isPersian,
    this.isMissed = false,
    this.showDone = false,
    this.onTap,
  });

  final ScheduleItemModel item;
  final dynamic loc;
  final bool isPersian;
  final bool isMissed;
  final bool showDone;
  final VoidCallback? onTap;

  bool get _isMedicine => item.type == 'medicine' || item.type == 'med';

  @override
  Widget build(BuildContext context) {
    final itemColor = isMissed
        ? Colors.red.shade700
        : CalendarUtils.getColorForType(item.type);
    final itemIcon = isMissed
        ? Icons.warning_amber_rounded
        : CalendarUtils.getIconForType(item.type);

    final content = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isMissed ? Colors.red.shade50 : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: isMissed ? Border.all(color: Colors.red.shade200) : null,
        boxShadow: [
          BoxShadow(
            color: isMissed
                ? Colors.red.withValues(alpha: 0.10)
                : AppColors.shadowDark.withValues(alpha: 0.40),
            offset: const Offset(3, 3),
            blurRadius: 10,
          ),
          if (!isMissed)
            const BoxShadow(
              color: AppColors.shadowLight,
              offset: Offset(-3, -3),
              blurRadius: 10,
            ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMissed
                  ? Colors.red.withValues(alpha: 0.10)
                  : itemColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
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
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red.shade700,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        item.title.toPersianDigit(isPersian),
                        style: AppTextStyles.get(
                          context,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isMissed ? Colors.red.shade900 : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (item.dosage.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    _isMedicine
                        ? "${loc['med_qty'] ?? 'مقدار'}: ${item.dosage.toPersianDigit(isPersian)}"
                        : item.dosage.toPersianDigit(isPersian),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption(context).copyWith(
                      height: 1.45,
                      color: isMissed ? Colors.red.shade400 : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.time.toPersianDigit(isPersian),
                textDirection: TextDirection.ltr,
                style: AppTextStyles.get(
                  context,
                  color: isMissed ? Colors.red.shade700 : itemColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (showDone) ...[
                const SizedBox(height: 4),
                const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.green,
                  size: 20,
                ),
              ] else if (onTap != null) ...[
                const SizedBox(height: 5),
                Icon(
                  Icons.edit_outlined,
                  color: itemColor.withValues(alpha: 0.85),
                  size: 18,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: 'ویرایش ${item.title}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}
