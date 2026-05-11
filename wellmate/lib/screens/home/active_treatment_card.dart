import 'package:flutter/material.dart';
import '../../core/theme/app_style.dart';
import '../../core/utils/string_extensions.dart';
import '../../localization/app_localizations.dart';

class ActiveTreatmentCard extends StatelessWidget {
  final String treatmentName;
  final String dose;
  final String time;
  final String assetIconPath;
  final double progressValue;
  final int secondsLeft;
  final VoidCallback onTaken;
  final TextStyle font;

  const ActiveTreatmentCard({
    Key? key,
    required this.treatmentName,
    required this.dose,
    required this.time,
    required this.assetIconPath,
    required this.progressValue,
    required this.secondsLeft,
    required this.onTaken,
    required this.font,
  }) : super(key: key);

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return "الان!";
    final h = (totalSeconds ~/ 3600);
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    if (h > 0) return "$h:$m:$s";
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final loc = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // اطلاعات درمان (ابتدا قرار می‌گیرد تا سمت راست بیفتد)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      treatmentName,
                      style: font.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dose.toPersianDigit(isPersian),
                      style: font.copyWith(
                          color: AppColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      loc['after_meal'] ?? 'بعد از غذا',
                      style: font.copyWith(
                          color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // حلقه پیشرفت با تایمر و آیکون (دوم قرار می‌گیرد تا سمت چپ بیفتد)
              SizedBox(
                width: 100,
                height: 100,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: progressValue,
                      strokeWidth: 8,
                      backgroundColor: AppColors.background,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primaryLight),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          assetIconPath,
                          width: 36,
                          height: 36,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.medication,
                                  color: AppColors.primary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDuration(secondsLeft)
                              .toPersianDigit(isPersian),
                          style: font.copyWith(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // دکمه‌های عملیاتی (ترتیب برای زبان فارسی اصلاح شد)
          Row(
            children: [
              Expanded(
                flex: 1,
                child: _buildButton(loc['taken'] ?? 'مصرف شد',
                    AppColors.primaryLight, Colors.white, font,
                    onTap: onTaken),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: _buildButton(loc['edit'] ?? 'ویرایش',
                    AppColors.background, AppColors.primary, font),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: _buildButton(loc['missed'] ?? 'مصرف نشد', Colors.white,
                    AppColors.textSecondary, font,
                    hasBorder: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildButton(
      String text, Color bgColor, Color textColor, TextStyle font,
      {bool hasBorder = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: hasBorder ? Border.all(color: Colors.grey.shade300) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: font.copyWith(
              color: textColor, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }
}
