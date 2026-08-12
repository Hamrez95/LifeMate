import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:wellmate/core/utils/string_extensions.dart';
import 'package:wellmate/core/utils/weekdays_extensions.dart';
import 'package:wellmate/providers/medication_provider.dart';

import '../../models/schedule_item_model.dart';
import '../../providers/notification_provider.dart';
import '../theme/app_style.dart';

typedef MissedMedicationReporter =
    Future<bool> Function(ScheduleItemModel item);

class WellMateAppHeader extends StatelessWidget {
  const WellMateAppHeader({
    super.key,
    required this.onProfileTap,
    this.onNotificationTap,
    this.onMissedMedicationTaken,
  });

  final VoidCallback onProfileTap;
  final VoidCallback? onNotificationTap;
  final MissedMedicationReporter? onMissedMedicationTaken;

  void _showMissedNotificationsPopup(
    BuildContext context,
    List<ScheduleItemModel> missedItems,
  ) {
    context.read<NotificationProvider>().setUnread(false);
    if (missedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'هیچ دارو، ویزیت یا تزریق انجام‌نشده‌ای وجود ندارد.',
                en: "There are no missed medications, visits or injections.",
              ),
              en: "There are no missed medications, visits or injections.",
            ),
            style: AppTextStyles.body(context).copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        final font = AppTextStyles.body(context);
        return Consumer<MedicationProvider>(
          builder: (context, scheduleProvider, child) {
            final currentMissedItems = scheduleProvider.missedItems;
            if (currentMissedItems.isEmpty) {
              Future.microtask(() {
                if (bottomSheetContext.mounted) {
                  Navigator.of(bottomSheetContext).pop();
                }
              });
              return const SizedBox.shrink();
            }
            return Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red.shade700,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'اعلان‌های انجام‌نشده',
                            en: "Notifications not done",
                          ),
                          en: "Notifications not done",
                        ),
                        style: font.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: currentMissedItems.length,
                      separatorBuilder: (_, __) => SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return _buildMissedNotificationCard(
                          currentMissedItems[index],
                          context,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMissedNotificationCard(
    ScheduleItemModel item,
    BuildContext context,
  ) {
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final occurrenceDate =
        item.startDate ?? item.scheduledAtUtc?.toLocal() ?? DateTime.now();
    final jalaliDate = Jalali.fromDateTime(occurrenceDate);
    final dayName = jalaliDate.persianDayName;
    final dateString =
        '${jalaliDate.year}/${jalaliDate.formatter.m}/${jalaliDate.formatter.d}'
            .toPersianDigit(isPersian);
    final timeString = item.time.toPersianDigit(isPersian);
    final dosageString = item.dosage.toPersianDigit(isPersian);
    final isMedicine = item.type == 'medicine';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _notificationIcon(item.type),
              color: AppColors.error,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: AppTextStyles.body(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (dosageString.trim().isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(
                    dosageString,
                    style: AppTextStyles.caption(
                      context,
                    ).copyWith(color: Colors.grey.shade600),
                  ),
                ],
                SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 4),
                        Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: '$dayName، $dateString',
                              en: "$dayName, $dateString",
                            ),
                            en: "$dayName, $dateString",
                          ),
                          style: AppTextStyles.caption(context).copyWith(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: AppColors.error,
                        ),
                        SizedBox(width: 4),
                        Text(
                          timeString,
                          style: AppTextStyles.caption(context).copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              final reporter = onMissedMedicationTaken;
              if (reporter == null) return;
              final success = await reporter(item);
              if (success && context.mounted) {
                context.read<MedicationProvider>().markAsDone(item.id);
              }
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isMedicine
                    ? LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'مصرف کردم',
                          en: "Taken",
                        ),
                        en: "I consumed",
                      )
                    : LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'انجام شد',
                          en: "Done",
                        ),
                        en: "done",
                      ),
                style: AppTextStyles.caption(
                  context,
                ).copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _notificationIcon(String type) {
    return switch (type) {
      'appointment' || 'visit' => Icons.medical_services_rounded,
      'injection' => Icons.vaccines_rounded,
      _ => Icons.medication_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = context.watch<NotificationProvider>().hasUnread;
    final missedItems = context.watch<MedicationProvider>().missedItems;
    final showRedDot = hasUnread || missedItems.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _buildSoftButton(
                icon: Icons.notifications_none_rounded,
                onTap:
                    onNotificationTap ??
                    () => _showMissedNotificationsPopup(context, missedItems),
              ),
              if (showRedDot)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          Image.asset(
            'assets/images/WellMateWithoutBack.png',
            height: 55,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.broken_image, color: Colors.grey);
            },
          ),
          GestureDetector(
            onTap: onProfileTap,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  width: 2,
                ),
              ),
              child: LifeMateCurrentUserAvatar(
                apiClient: context.read<LifeMateApiClient>(),
                radius: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoftButton({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 24),
      ),
    );
  }
}
