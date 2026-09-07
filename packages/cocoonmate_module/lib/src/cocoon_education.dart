part of '../cocoonmate_module.dart';

enum CocoonEducationLoadState { loading, ready, unavailable, error }

class CocoonPregnancyEducation extends StatelessWidget {
  const CocoonPregnancyEducation({
    required this.host,
    required this.fa,
    required this.offline,
    super.key,
  });

  final CocoonHostContract host;
  final bool fa;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final dating =
        (offline ? host.offlinePregnancySnapshot : host.pregnancySnapshot)
            ?.episode
            ?.dating;
    CocoonGestationalAge? age;
    if (dating != null) {
      try {
        age = deriveCocoonGestationalAgeOffline(
              dating: dating,
              asOfLocalDate: DateTime.now(),
            ) ??
            dating.gestationalAge;
      } on CocoonPregnancyDatingError {
        age = dating.gestationalAge;
      }
    }
    final week = (age?.week ?? 0).clamp(1, 42).toInt();
    ClinicalContentSelection selection;
    try {
      selection = bundledPregnancyClinicalContent.weekly(
        gestationalWeek: week,
        locale: fa ? 'fa' : 'en',
        atUtc: DateTime.now().toUtc(),
      );
    } on StateError {
      return CocoonEducationScreen(
        fa: fa,
        state: CocoonEducationLoadState.unavailable,
        onRetry: host.refresh,
      );
    }
    if (selection.usedSafetyFallback) {
      return CocoonEducationScreen(
        fa: fa,
        state: CocoonEducationLoadState.unavailable,
        onRetry: host.refresh,
      );
    }
    return CocoonEducationScreen(
      fa: fa,
      state: CocoonEducationLoadState.ready,
      data: CocoonEducationViewData(
        selection: selection,
        weekLabel: fa ? 'هفته ${cocoonDigits('$week', true)}' : 'Week $week',
        cached: offline,
      ),
      onRetry: host.refresh,
    );
  }
}

class CocoonEducationViewData {
  const CocoonEducationViewData({
    required this.selection,
    required this.weekLabel,
    this.cached = false,
    this.savedAtLabel,
  });

  final ClinicalContentSelection selection;
  final String weekLabel;
  final bool cached;
  final String? savedAtLabel;
}

class CocoonEducationScreen extends StatelessWidget {
  const CocoonEducationScreen({
    required this.fa,
    required this.state,
    required this.onRetry,
    this.data,
    super.key,
  });

  final bool fa;
  final CocoonEducationLoadState state;
  final CocoonEducationViewData? data;
  final VoidCallback onRetry;

  String t(String en, String faText) => fa ? faText : en;

  @override
  Widget build(BuildContext context) => switch (state) {
        CocoonEducationLoadState.loading => _EducationLoading(fa: fa),
        CocoonEducationLoadState.error => CocoonStatePage(
            icon: Icons.menu_book_outlined,
            eyebrow: t('Education', 'آموزش'),
            title:
                t('Could not refresh content', 'به‌روزرسانی محتوا انجام نشد'),
            body: t(
              'Nothing was replaced. Try again when your connection is stable.',
              'هیچ محتوایی جایگزین نشده است؛ با اتصال پایدار دوباره تلاش کن.',
            ),
            action: t('Try again', 'تلاش دوباره'),
            onPressed: onRetry,
          ),
        CocoonEducationLoadState.unavailable => CocoonStatePage(
            icon: Icons.shield_outlined,
            eyebrow: t('Approved content', 'محتوای تأییدشده'),
            title: t(
              'Guidance is temporarily unavailable',
              'راهنمای تأییدشده موقتاً در دسترس نیست',
            ),
            body: t(
              'Use your existing care plan and professional care for urgent concerns.',
              'برنامه مراقبتی فعلی را دنبال کن و برای نگرانی فوری از مراقبت حرفه‌ای استفاده کن.',
            ),
            action: t('Refresh', 'به‌روزرسانی'),
            onPressed: onRetry,
          ),
        CocoonEducationLoadState.ready when data != null =>
          _EducationArticle(fa: fa, data: data!),
        _ => CocoonStatePage(
            icon: Icons.shield_outlined,
            eyebrow: t('Approved content', 'محتوای تأییدشده'),
            title: t('Content unavailable', 'محتوا در دسترس نیست'),
            body: t(
              'No unreviewed guidance is shown in its place.',
              'هیچ راهنمای بازبینی‌نشده‌ای جایگزین آن نمایش داده نمی‌شود.',
            ),
            action: t('Refresh', 'به‌روزرسانی'),
            onPressed: onRetry,
          ),
      };
}

class _EducationArticle extends StatelessWidget {
  const _EducationArticle({required this.fa, required this.data});
  final bool fa;
  final CocoonEducationViewData data;

  @override
  Widget build(BuildContext context) {
    final content = data.selection.content;
    return CustomScrollView(
      key: const PageStorageKey('cocoon-education'),
      slivers: [
        SliverToBoxAdapter(
          child: CocoonPagePadding(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.cached) ...[
                  _EducationCacheNotice(
                      fa: fa, savedAtLabel: data.savedAtLabel),
                  const SizedBox(height: 16),
                ],
                Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 26, 24, 24),
                  decoration: BoxDecoration(
                    color: CocoonTheme.lilac,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 11,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              data.weekLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: CocoonTheme.ink),
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.auto_stories_outlined,
                            color: CocoonTheme.coral,
                          ),
                        ],
                      ),
                      const SizedBox(height: 34),
                      Text(
                        content.title,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        fa ? 'راهنمای این هفته' : 'This week’s guide',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(color: CocoonTheme.ink),
                      ),
                    ],
                  ),
                ),
                if (data.selection.usedLocaleFallback) ...[
                  const SizedBox(height: 14),
                  _LocaleFallbackNotice(fa: fa),
                ],
                const SizedBox(height: 30),
                Text(
                  content.body,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 17,
                        height: 1.9,
                      ),
                ),
                const SizedBox(height: 32),
                _ReviewMetadata(fa: fa, content: content),
                const SizedBox(height: 26),
                Container(
                  padding: const EdgeInsetsDirectional.all(18),
                  decoration: BoxDecoration(
                    color: CocoonTheme.sage,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.health_and_safety_outlined,
                        color: CocoonTheme.sageStrong,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          fa
                              ? 'این محتوا جایگزین برنامه مراقبتی شخصی یا توصیه پزشک و ماما نیست.'
                              : 'This content does not replace your personal care plan or clinician advice.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EducationCacheNotice extends StatelessWidget {
  const _EducationCacheNotice({required this.fa, this.savedAtLabel});
  final bool fa;
  final String? savedAtLabel;

  @override
  Widget build(BuildContext context) {
    final message = savedAtLabel == null
        ? (fa
            ? 'آخرین محتوای تأییدشده ذخیره‌شده روی دستگاه'
            : 'Last approved content saved on this device')
        : (fa
            ? 'ذخیره‌شده روی دستگاه · $savedAtLabel'
            : 'Saved on device · $savedAtLabel');
    return Semantics(
      label: message,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsetsDirectional.all(13),
        decoration: BoxDecoration(
          color: CocoonTheme.sky,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          children: [
            const Icon(Icons.offline_pin_outlined,
                size: 20, color: CocoonTheme.skyStrong),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: CocoonTheme.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocaleFallbackNotice extends StatelessWidget {
  const _LocaleFallbackNotice({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.all(14),
        decoration: BoxDecoration(
          color: CocoonTheme.warm,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Icon(Icons.translate_rounded, color: CocoonTheme.gold),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                fa
                    ? 'نسخه فارسی تأییدشده هنوز آماده نیست؛ نسخه تأییدشده جایگزین نمایش داده شده است.'
                    : 'An approved version in your language is not ready; an approved fallback is shown.',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      );
}

class _ReviewMetadata extends StatelessWidget {
  const _ReviewMetadata({required this.fa, required this.content});
  final bool fa;
  final PregnancyClinicalContent content;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsetsDirectional.only(bottom: 14),
        leading:
            const Icon(Icons.verified_outlined, color: CocoonTheme.sageStrong),
        title: Text(
          fa ? 'بازبینی بالینی' : 'Clinical review',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          fa
              ? 'نسخه ${cocoonDigits('${content.version}', true)}'
              : 'Version ${content.version}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              fa
                  ? 'شناسه بازبینی: ${content.review.reviewedByRef}'
                  : 'Review reference: ${content.review.reviewedByRef}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      );
}

class _EducationLoading extends StatelessWidget {
  const _EducationLoading({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: fa
            ? 'در حال آماده‌سازی محتوای تأییدشده'
            : 'Loading approved content',
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 28),
          children: [
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: CocoonTheme.lilac,
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            const SizedBox(height: 26),
            for (final width in [double.infinity, double.infinity, 230.0]) ...[
              Container(
                width: width,
                height: 16,
                decoration: BoxDecoration(
                  color: CocoonTheme.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 13),
            ],
          ],
        ),
      );
}
