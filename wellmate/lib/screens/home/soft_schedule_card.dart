import 'package:flutter/material.dart';
import '../../core/theme/app_style.dart';
import '../../models/schedule_item_model.dart';
import '../../../core/utils/string_extensions.dart';

class SoftScheduleCard extends StatelessWidget {
  final ScheduleItemModel item;
  final int index;
  final TextStyle? font;

  const SoftScheduleCard(
      {Key? key, required this.item, required this.index, this.font})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: AppColors.shadowDark.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              width: 65,
              height: 65,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.medication_liquid_rounded,
                  color: AppColors.primary, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: font?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time_rounded,
                                size: 14, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(item.time.toPersianDigit(isPersian),
                                style: font?.copyWith(
                                    color: AppColors.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(item.dosage.toPersianDigit(isPersian),
                              style: font?.copyWith(
                                  color: AppColors.textSecondary, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                    ],
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
