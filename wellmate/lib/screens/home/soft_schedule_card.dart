import 'package:flutter/material.dart';
import 'package:wellmate/core/theme/app_style.dart';
import 'package:wellmate/models/schedule_item_model.dart';
import '../../../core/utils/string_extensions.dart';

class SoftScheduleCard extends StatelessWidget {
  final ScheduleItemModel item; // تغییر نوع داده از Map به مدل
  final int index;
  final TextStyle? font;

  const SoftScheduleCard({
    Key? key,
    required this.item,
    required this.index,
    this.font,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // تعیین آیکون و رنگ بر اساس نوع آیتم (مثلاً دارو، ویزیت و...)
    IconData iconData = Icons.medication;
    Color iconColor = AppColors.primary;

    if (item.type == 'visit') {
      iconData = Icons.medical_services_outlined;
      iconColor = Colors.orangeAccent;
    } else if (item.type == 'liquid') {
      iconData = Icons.local_drink_outlined;
      iconColor = Colors.blueAccent;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark,
            blurRadius: 10,
            offset: const Offset(4, 4),
          ),
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 10,
            offset: const Offset(-4, -4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(iconData, color: iconColor),
        ),
        title: Text(
          item.title, // استفاده مستقیم از ویژگی‌های مدل
          style: font ??
              AppTextStyles.body(context).copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${item.time} • ${item.dosage}',
          style: AppTextStyles.caption(context),
        ),
        trailing: item.isDone
            ? const Icon(Icons.check_circle_rounded,
                color: Colors.green, size: 28)
            : Icon(Icons.circle_outlined,
                color: Colors.grey.shade400, size: 28),
      ),
    );
  }
}
