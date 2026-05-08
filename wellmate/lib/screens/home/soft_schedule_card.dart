import 'package:flutter/material.dart';
import '../../core/theme/app_style.dart';
import '../../models/schedule_item_model.dart';
import '../../../core/utils/string_extensions.dart';

class SoftScheduleCard extends StatelessWidget {
  final ScheduleItemModel item;
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
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';

    IconData iconData = Icons.medication_outlined;
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
        color: AppColors.cardBackground ?? Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(4, 4),
          ),
          BoxShadow(
            color: Colors.white, // Shadow Light
            blurRadius: 15,
            offset: const Offset(-4, -4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(iconData, color: iconColor, size: 26),
        ),
        title: Text(
          item.title,
          style: font?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.textPrimary) ??
              TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.textPrimary),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            children: [
              Icon(Icons.access_time, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                item.time.toPersianDigit(isPersian),
                style: font?.copyWith(
                        color: AppColors.textSecondary, fontSize: 13) ??
                    TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(width: 12),
              Icon(Icons.monitor_weight_outlined,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                item.dosage.toPersianDigit(isPersian),
                style: font?.copyWith(
                        color: AppColors.textSecondary, fontSize: 13) ??
                    TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        trailing: InkWell(
          onTap: () {
            // اکشن تیک زدن دارو
          },
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: item.isDone ? Colors.green.shade50 : Colors.transparent,
              border: item.isDone
                  ? null
                  : Border.all(color: Colors.grey.shade300, width: 2),
            ),
            child: item.isDone
                ? const Icon(Icons.check, color: Colors.green, size: 20)
                : const SizedBox(width: 20, height: 20),
          ),
        ),
      ),
    );
  }
}
