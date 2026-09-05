import 'package:flutter/material.dart';

import 'home_schedule_loader.dart';

class HomeOfflineStatusBanner extends StatelessWidget {
  const HomeOfflineStatusBanner({
    super.key,
    this.cachedAtUtc,
  });

  final DateTime? cachedAtUtc;

  @override
  Widget build(BuildContext context) {
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final cachedAtLocal = cachedAtUtc?.toLocal();
    final timeLabel = cachedAtLocal == null
        ? null
        : '${cachedAtLocal.hour.toString().padLeft(2, '0')}:${cachedAtLocal.minute.toString().padLeft(2, '0')}';
    final pendingCount =
        homeOfflinePresentationState.value.pendingTreatmentCreateCount;
    final hasPendingTreatment = pendingCount > 0;
    final title = hasPendingTreatment
        ? (isPersian
              ? 'درمان روی گوشی ذخیره شده'
              : 'Treatment saved on this device')
        : (isPersian
              ? 'اطلاعات ذخیره‌شده روی گوشی'
              : 'Saved on this device');
    final body = hasPendingTreatment
        ? (isPersian
              ? pendingCount == 1
                    ? 'این درمان هنوز روی سرور تأیید نشده و پس از اتصال اینترنت همگام می‌شود.'
                    : '$pendingCount درمان هنوز روی سرور تأیید نشده‌اند و پس از اتصال اینترنت همگام می‌شوند.'
              : pendingCount == 1
              ? 'This treatment is not server-confirmed yet and will sync when you reconnect.'
              : '$pendingCount treatments are not server-confirmed yet and will sync when you reconnect.')
        : (isPersian
              ? timeLabel == null
                    ? 'فعلاً اطلاعات محلی نمایش داده می‌شود. پس از اتصال، وضعیت سرور تازه می‌شود.'
                    : 'آخرین نسخه ذخیره‌شده ساعت $timeLabel است. پس از اتصال، وضعیت سرور تازه می‌شود.'
              : timeLabel == null
              ? 'Showing local data for now. Server status will refresh when you reconnect.'
              : 'Last saved copy: $timeLabel. Server status will refresh when you reconnect.');

    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $body',
      child: Container(
        key: const ValueKey('home-offline-status-banner'),
        width: double.infinity,
        margin: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 4),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: colors.secondaryContainer.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colors.secondary.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              hasPendingTreatment
                  ? Icons.cloud_upload_rounded
                  : Icons.cloud_off_rounded,
              size: 22,
              color: colors.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: TextStyle(
                      color: colors.onSecondaryContainer.withValues(alpha: 0.82),
                      fontSize: 12.5,
                      height: 1.45,
                    ),
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
