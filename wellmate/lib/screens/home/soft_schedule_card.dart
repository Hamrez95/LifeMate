import 'package:flutter/material.dart';
import '../../core/theme/app_style.dart';
import '../../models/schedule_item_model.dart';
import '../../../core/utils/string_extensions.dart';

class SoftScheduleCard extends StatelessWidget {
  final ScheduleItemModel item;
  final int index;
  final TextStyle font;
  final String? assetPath;
  final bool isMissed;
  final VoidCallback? onTaken;
  final VoidCallback? onCompleted;
  final VoidCallback? onNotCompleted;

  const SoftScheduleCard({
    Key? key,
    required this.item,
    required this.index,
    required this.font,
    required this.assetPath,
    this.isMissed = false,
    this.onTaken,
    this.onCompleted,
    this.onNotCompleted,
  }) : super(key: key);

  IconData get _fallbackIcon => switch (item.type) {
    'injection' => Icons.vaccines_rounded,
    'appointment' || 'visit' => Icons.medical_services_rounded,
    _ => Icons.medication,
  };

  @override
  Widget build(BuildContext context) {
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final isPending = item.pendingSync || item.status == 'pending_sync';

    return Container(
      decoration: BoxDecoration(
        color: isMissed
            ? Colors.red.shade50
            : isPending
                ? const Color(0xFFF2F7FF)
                : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: isMissed
            ? Border.all(color: Colors.red.shade200)
            : isPending
                ? Border.all(color: const Color(0xFFB8CDF6))
                : null,
        boxShadow: [
          BoxShadow(
            color: isMissed
                ? Colors.red.withOpacity(0.1)
                : AppColors.shadowDark.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
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
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red.shade700,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                      ] else if (isPending) ...[
                        const Icon(
                          Icons.cloud_upload_outlined,
                          color: Color(0xFF4F74C8),
                          size: 18,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          item.title.toPersianDigit(isPersian),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: font.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isMissed
                                ? Colors.red.shade900
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isPending) ...[
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCE8FF),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        'روی گوشی ذخیره شد • منتظر همگام‌سازی',
                        key: const ValueKey('pending-sync-label'),
                        style: font.copyWith(
                          color: const Color(0xFF365DA8),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isMissed
                              ? Colors.red.withOpacity(0.1)
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: isMissed
                                  ? Colors.red.shade700
                                  : AppColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.time.toPersianDigit(isPersian),
                              style: font.copyWith(
                                color: isMissed
                                    ? Colors.red.shade700
                                    : AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (isMissed && !isPending) ...[
                    const SizedBox(height: 12),
                    if (item.type == 'medicine')
                      GestureDetector(
                        onTap: onTaken,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'مصرف کردم',
                            style: font.copyWith(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          GestureDetector(
                            onTap: onCompleted,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade600,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'انجام شد',
                                style: font.copyWith(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: onNotCompleted,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade300),
                              ),
                              child: Text(
                                'انجام نشد',
                                style: font.copyWith(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
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
                child: assetPath?.trim().isNotEmpty == true
                    ? Image.asset(
                        assetPath!,
                        width: 32,
                        height: 32,
                        color: isMissed ? Colors.red.shade700 : null,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          _fallbackIcon,
                          color: isMissed
                              ? Colors.red.shade700
                              : AppColors.primary,
                        ),
                      )
                    : Icon(
                        _fallbackIcon,
                        color: isPending
                            ? const Color(0xFF4F74C8)
                            : isMissed
                                ? Colors.red.shade700
                                : AppColors.primary,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
