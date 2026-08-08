import 'package:flutter/material.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/string_extensions.dart';
import '../../localization/app_localizations.dart';

class ActiveTreatmentCard extends StatelessWidget {
  final String treatmentName;
  final String dose;
  final String time;
  final String? assetIconPath;
  final double progressValue;
  final int secondsLeft;
  final VoidCallback? onTaken;
  final VoidCallback? onSkipped;
  final VoidCallback? onEdit;
  final bool isSubmitting;
  final TextStyle font;
  final String? supportingText;
  final String? countdownLabel;
  final bool showActions;
  final Color? accentColor;
  final Color? progressColor;
  final Color? progressBackgroundColor;
  final IconData fallbackIcon;

  const ActiveTreatmentCard({
    super.key,
    required this.treatmentName,
    required this.dose,
    required this.time,
    required this.assetIconPath,
    required this.progressValue,
    required this.secondsLeft,
    required this.onTaken,
    required this.onSkipped,
    required this.onEdit,
    this.isSubmitting = false,
    required this.font,
    this.supportingText,
    this.countdownLabel,
    this.showActions = true,
    this.accentColor,
    this.progressColor,
    this.progressBackgroundColor,
    this.fallbackIcon = Icons.medication,
  });

  @visibleForTesting
  static String formatCountdown(int totalSeconds) {
    if (totalSeconds <= 0) return 'الان!';
    final hours = totalSeconds ~/ 3600;
    final minutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final loc = AppLocalizations.of(context);
    final accent = accentColor ?? AppColors.primary;
    final progress = progressColor ?? AppColors.primaryLight;
    final progressBackground = progressBackgroundColor ?? AppColors.background;
    final helper = supportingText ?? loc['after_meal'];
    final countdown = countdownLabel ?? formatCountdown(secondsLeft);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      treatmentName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: font.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (dose.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        dose.toPersianDigit(isPersian),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: font.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    if (helper != null && helper.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        helper.toPersianDigit(isPersian),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: font.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 20),
              SizedBox(
                width: 100,
                height: 100,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: progressValue,
                      strokeWidth: 8,
                      backgroundColor: progressBackground,
                      valueColor: AlwaysStoppedAnimation<Color>(progress),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (assetIconPath?.trim().isNotEmpty == true)
                          Image.asset(
                            assetIconPath!,
                            width: 36,
                            height: 36,
                            errorBuilder: (_, __, ___) =>
                                Icon(fallbackIcon, color: accent),
                          )
                        else
                          Icon(fallbackIcon, color: accent, size: 36),
                        const SizedBox(height: 4),
                        Text(
                          countdown.toPersianDigit(isPersian),
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: font.copyWith(
                            color: accent,
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
          if (showActions) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildButton(
                    isSubmitting ? '...' : loc['taken'],
                    AppColors.primaryLight,
                    Colors.white,
                    font,
                    onTap: onTaken,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildButton(
                    loc['edit'],
                    AppColors.background,
                    AppColors.primary,
                    font,
                    onTap: onEdit,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildButton(
                    loc['missed'],
                    Colors.white,
                    AppColors.textSecondary,
                    font,
                    hasBorder: true,
                    onTap: onSkipped,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildButton(
    String text,
    Color backgroundColor,
    Color textColor,
    TextStyle textStyle, {
    bool hasBorder = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: hasBorder ? Border.all(color: Colors.grey.shade300) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: textStyle.copyWith(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
