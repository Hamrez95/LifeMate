import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:wellmate/core/utils/string_extensions.dart';
import 'package:wellmate/core/utils/weekdays_extensions.dart';
import 'package:wellmate/providers/medication_provider.dart';
import '../../providers/notification_provider.dart';
// حتماً ScheduleProvider رو هم اینجا ایمپورت کن:
// import '../../providers/schedule_provider.dart';
import '../theme/app_style.dart';
import '../../models/schedule_item_model.dart';

class WellMateAppHeader extends StatelessWidget {
  final VoidCallback onProfileTap;
  final VoidCallback? onNotificationTap;

  // نکته: missedItems از اینجا حذف شد چون مستقیما از پرووایدر گرفته میشه
  const WellMateAppHeader({
    Key? key,
    required this.onProfileTap,
    this.onNotificationTap,
  }) : super(key: key);

  // نکته: حالا missedItems رو به عنوان ورودی به این متد پاس میدیم
  void _showMissedMedicationsPopup(
      BuildContext context, List<ScheduleItemModel> missedItems) {
    if (missedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('هیچ داروی فراموش شده‌ای وجود ندارد.',
              style: AppTextStyles.body(context).copyWith(color: Colors.white)),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }

    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (bottomSheetContext) {
          final font = AppTextStyles.body(context);

          // 👈 استفاده از Consumer برای اینکه با زدن دکمه لیست زنده آپدیت شود
          return Consumer<MedicationProvider>(
            builder: (context, medProvider, child) {
              final missedItems = medProvider.missedItems;

              // اگر همه داروها در پاپ آپ مصرف شدند، پاپ آپ را ببندد
              if (missedItems.isEmpty) {
                Future.microtask(() => Navigator.of(context).pop());
                return const SizedBox.shrink();
              }
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
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
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.warning_amber_rounded,
                              color: Colors.red.shade700),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'داروهای فراموش شده',
                          style: font.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: missedItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = missedItems[index];
                          return _buildMissedNotificationCard(item, context);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          );
        });
  }

  Widget _buildMissedNotificationCard(
      ScheduleItemModel item, BuildContext context) {
    // 👈 دریافت تاریخ سیستم و تبدیل به شمسی
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';

    final Jalali today = Jalali.now();
    final String dayName = today.persianDayName;

    final String dateString =
        '${today.year}/${today.formatter.m}/${today.formatter.d}'
            .toPersianDigit(isPersian);
    final String timeString = item.time.toPersianDigit(isPersian);
    final String dosageString = (item.dosage ?? '').toPersianDigit(isPersian);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.type == 'medicine' ? Icons.medication : Icons.calendar_month,
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
                const SizedBox(height: 4),
                Text(
                  dosageString,
                  style: AppTextStyles.caption(context).copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),

                // 👈 ردیف جدید برای نمایش تاریخ، روز و ساعت
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      '$dayName، $dateString',
                      style: AppTextStyles.caption(context).copyWith(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.access_time, size: 14, color: AppColors.error),
                    const SizedBox(width: 4),
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
          ),
          // 👈 مشکل اینجا بود! دکمه به داخل Row منتقل شد
          GestureDetector(
            onTap: () {
              context.read<MedicationProvider>().markAsDone(item.id);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'مصرف کردم',
                style: AppTextStyles.caption(context).copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = context.watch<NotificationProvider>().hasUnread;
    final missedItems = context.watch<MedicationProvider>().missedItems;

    // نقطه قرمز زمانی نمایش داده می‌شود که یا نوتیفیکیشن جدید داشته باشیم یا داروی فراموش شده
    final showRedDot = hasUnread || missedItems.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _buildSoftButton(
                icon: Icons.notifications_none_rounded,
                // نکته: لیست missedItems رو به متد پاس میدیم
                onTap: onNotificationTap ??
                    () => _showMissedMedicationsPopup(context, missedItems),
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

          // نکته کوچک: معمولاً در فلاتر مسیر تصاویر رو از پوشه assets ریشه آدرس‌دهی می‌کنند
          // مثلا: 'assets/images/WellMateWithoutBack.png'
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
                    color: AppColors.primary.withOpacity(0.1), width: 2),
              ),
              child: const CircleAvatar(
                radius: 20,
                backgroundColor: Colors.transparent,
                backgroundImage:
                    AssetImage('assets/images/mother_avatar.png'),
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
              color: AppColors.primary.withOpacity(0.08),
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
