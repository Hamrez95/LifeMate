import 'package:flutter/material.dart';
import '../../core/theme/app_style.dart';
import '../../models/schedule_item_model.dart';
import '../../../core/utils/string_extensions.dart';

class SoftScheduleCard extends StatelessWidget {
  final ScheduleItemModel item;
  final int index;
  final TextStyle font;
  final String assetPath;
  final bool isMissed;
  final VoidCallback? onTaken; // 👈 اضافه شدن تابع برای دکمه مصرف

  const SoftScheduleCard({
    Key? key,
    required this.item,
    required this.index,
    required this.font,
    required this.assetPath,
    this.isMissed = false,
    this.onTaken, // 👈 دریافت از سازنده
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';

    return Container(
      decoration: BoxDecoration(
        color: isMissed ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: isMissed ? Border.all(color: Colors.red.shade200) : null,
        boxShadow: [
          BoxShadow(
              color: isMissed
                  ? Colors.red.withOpacity(0.1)
                  : AppColors.shadowDark.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isMissed) ...[
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.red.shade700, size: 18),
                        const SizedBox(width: 4),
                      ],
                      Text(item.title,
                          style: font.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isMissed
                                  ? Colors.red.shade900
                                  : AppColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: isMissed
                                ? Colors.red.withOpacity(0.1)
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            Icon(Icons.access_time_rounded,
                                size: 14,
                                color: isMissed
                                    ? Colors.red.shade700
                                    : AppColors.primary),
                            const SizedBox(width: 4),
                            Text(item.time.toPersianDigit(isPersian),
                                style: font.copyWith(
                                    color: isMissed
                                        ? Colors.red.shade700
                                        : AppColors.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.dosage.toPersianDigit(isPersian),
                          style: font.copyWith(
                              color: isMissed
                                  ? Colors.red.shade400
                                  : AppColors.textSecondary,
                              fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  // 👈 دکمه "مصرف کردم" برای حالت فراموش شده
                  if (isMissed) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: onTaken,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade600,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'مصرف کردم',
                          style: font.copyWith(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ]
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: isMissed
                    ? Colors.red.withOpacity(0.1)
                    : AppColors.background,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Image.asset(
                  assetPath,
                  width: 32,
                  height: 32,
                  color: isMissed ? Colors.red.shade700 : null,
                  errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.medication,
                      color:
                          isMissed ? Colors.red.shade700 : AppColors.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
