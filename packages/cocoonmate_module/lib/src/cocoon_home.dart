part of '../cocoonmate_module.dart';

class CocoonPregnancyHome extends StatelessWidget {
  const CocoonPregnancyHome({
    required this.host,
    required this.fa,
    required this.onOpenWeek,
    this.onOpenNotifications,
    this.onOpenSafety,
    super.key,
  });

  final CocoonHostContract host;
  final bool fa;
  final VoidCallback onOpenWeek;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenSafety;

  String t(String en, String faText) => fa ? faText : en;

  CocoonGestationalAge? get _age {
    final dating = host.pregnancySnapshot?.episode?.dating;
    if (dating == null) return null;
    try {
      return deriveCocoonGestationalAgeOffline(
            dating: dating,
            asOfLocalDate: DateTime.now(),
          ) ??
          dating.gestationalAge;
    } on CocoonPregnancyDatingError {
      return dating.gestationalAge;
    }
  }

  @override
  Widget build(BuildContext context) {
    final age = _age;
    final week = age?.week;
    final day = age?.day;
    final progress = ((age?.totalDays ?? 0) / 280).clamp(0.0, 1.0).toDouble();
    return CustomScrollView(
      key: const PageStorageKey('cocoon-home'),
      slivers: [
        SliverToBoxAdapter(
          child: CocoonPagePadding(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HomeGreeting(fa: fa, onOpenNotifications: onOpenNotifications),
                const SizedBox(height: 22),
                _PregnancyMoment(
                  fa: fa,
                  week: week,
                  day: day,
                  progress: progress,
                  onTap: onOpenWeek,
                ),
                const SizedBox(height: 30),
                Semantics(
                  header: true,
                  child: CocoonSectionHeading(
                    title: t('A note for this week', 'یادداشت این هفته'),
                    supporting: t(
                      'Only reviewed guidance is shown here',
                      'اینجا فقط راهنمای بازبینی‌شده نمایش داده می‌شود',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _WeeklyEditorial(fa: fa, week: week),
                const SizedBox(height: 32),
                Semantics(
                  header: true,
                  child: CocoonSectionHeading(
                    title: t('For today', 'برای امروز'),
                    supporting: t(
                      'Only the next useful steps',
                      'فقط قدم‌های بعدی و کاربردی',
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _TodayTimeline(fa: fa),
                const SizedBox(height: 32),
                _DevelopmentPreview(fa: fa, onOpenWeek: onOpenWeek),
                const SizedBox(height: 32),
                _SafetyEntry(fa: fa, onTap: onOpenSafety),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeGreeting extends StatelessWidget {
  const _HomeGreeting({required this.fa, this.onOpenNotifications});
  final bool fa;
  final VoidCallback? onOpenNotifications;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fa ? 'امروز در مسیر تو' : 'Your pregnancy, today',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  fa
                      ? 'آرام، روشن و قدم‌به‌قدم'
                      : 'Calm, clear, one step at a time',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: CocoonTheme.muted),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            enabled: onOpenNotifications != null,
            label: fa ? 'اعلان‌ها' : 'Notifications',
            child: InkResponse(
              onTap: onOpenNotifications,
              radius: 28,
              child: const CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: CocoonTheme.ink,
                ),
              ),
            ),
          ),
        ],
      );
}

class _PregnancyMoment extends StatelessWidget {
  const _PregnancyMoment({
    required this.fa,
    required this.week,
    required this.day,
    required this.progress,
    required this.onTap,
  });

  final bool fa;
  final int? week;
  final int? day;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasAge = week != null && day != null;
    final weekText = hasAge ? cocoonDigits('$week', fa) : '—';
    final dayText = hasAge ? cocoonDigits('$day', fa) : '—';
    return Semantics(
      button: true,
      label: hasAge
          ? (fa ? 'هفته $week و $day روز' : 'Week $week and $day days')
          : (fa
              ? 'زمان بارداری در حال همگام‌سازی'
              : 'Pregnancy dating syncing'),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsetsDirectional.fromSTEB(22, 24, 18, 22),
          decoration: BoxDecoration(
            color: CocoonTheme.warm,
            borderRadius: BorderRadius.circular(30),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 340 ||
                  MediaQuery.textScalerOf(context).scale(16) > 22;
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fa ? 'لحظه‌ی فعلی بارداری' : 'Your current moment',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: CocoonTheme.coral),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 7,
                    children: [
                      Text(
                        weekText,
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(color: CocoonTheme.coral),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          fa ? 'هفته و $dayText روز' : 'weeks + $dayText days',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  if (!hasAge) ...[
                    const SizedBox(height: 10),
                    Text(
                      fa
                          ? 'پس از دریافت تاریخ معتبر نمایش داده می‌شود'
                          : 'Shown after verified dating is available',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: CocoonTheme.muted),
                    ),
                  ],
                  if (hasAge) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        minHeight: 7,
                        value: progress,
                        color: CocoonTheme.coral,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      fa
                          ? 'پیشرفت بر پایه‌ی تاریخ ثبت‌شده'
                          : 'Progress based on the recorded dating source',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          fa ? 'جزئیات این هفته را ببین' : 'Explore this week',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: CocoonTheme.coral),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: CocoonTheme.coral,
                      ),
                    ],
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: CocoonGrowthOrb(
                        progress: progress,
                        semanticLabel: fa
                            ? 'نمایش انتزاعی پیشرفت بارداری'
                            : 'Abstract pregnancy progress visualization',
                      ),
                    ),
                    const SizedBox(height: 20),
                    copy,
                  ],
                );
              }
              return Row(
                children: [
                  CocoonGrowthOrb(
                    progress: progress,
                    semanticLabel: fa
                        ? 'نمایش انتزاعی پیشرفت بارداری'
                        : 'Abstract pregnancy progress visualization',
                    size: 144,
                  ),
                  const SizedBox(width: 20),
                  Expanded(child: copy),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TodayTimeline extends StatelessWidget {
  const _TodayTimeline({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          border: BorderDirectional(
            start: BorderSide(color: CocoonTheme.sageStrong, width: 2),
          ),
        ),
        padding: const EdgeInsetsDirectional.only(start: 18),
        child: Column(
          children: [
            _TimelineRow(
              icon: Icons.task_alt_rounded,
              title: fa ? 'برنامه‌ی مراقبت امروز' : "Today's care plan",
              body: fa
                  ? 'کارهای ثبت‌شده‌ی LifeMate اینجا مرتب می‌شوند.'
                  : 'Your saved LifeMate actions appear here.',
            ),
            const SizedBox(height: 18),
            _TimelineRow(
              icon: Icons.event_outlined,
              title: fa ? 'قرار بعدی' : 'Next appointment',
              body: fa
                  ? 'قرار تأییدشده‌ای برای نمایش نداریم.'
                  : 'No confirmed appointment to show.',
            ),
          ],
        ),
      );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: CocoonTheme.sage,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 21, color: CocoonTheme.sageStrong),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: CocoonTheme.muted),
                ),
              ],
            ),
          ),
        ],
      );
}

class _WeeklyEditorial extends StatelessWidget {
  const _WeeklyEditorial({required this.fa, required this.week});
  final bool fa;
  final int? week;

  @override
  Widget build(BuildContext context) {
    ClinicalContentSelection? selection;
    if (week != null) {
      selection = bundledPregnancyClinicalContent.weekly(
        gestationalWeek: _safeWeek(week!),
        locale: fa ? 'fa' : 'en',
        atUtc: DateTime.now().toUtc(),
      );
    }
    final unavailable = selection == null || selection.usedSafetyFallback;
    return Semantics(
      container: true,
      label: unavailable
          ? (fa
              ? 'محتوای بازبینی‌شده‌ی این هفته در دسترس نیست'
              : 'Reviewed content for this week is unavailable')
          : selection.content.title,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 22, 20, 20),
        decoration: BoxDecoration(
          color: CocoonTheme.sky,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              unavailable
                  ? Icons.auto_stories_outlined
                  : Icons.menu_book_rounded,
              color: CocoonTheme.skyStrong,
              size: 28,
            ),
            const SizedBox(height: 18),
            Text(
              selection?.content.title ??
                  (fa ? 'راهنمای این هفته' : 'This week’s guide'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              selection?.content.body ??
                  (fa
                      ? 'پس از دریافت زمان‌بندی معتبر، محتوای بازبینی‌شده نمایش داده می‌شود.'
                      : 'Reviewed guidance appears after verified dating is available.'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.verified_outlined,
                  size: 17,
                  color: CocoonTheme.skyStrong,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fa
                        ? 'محتوای دارای بازبینی بالینی'
                        : 'Clinically reviewed content',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: CocoonTheme.skyStrong),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _safeWeek(int value) => value < 1 ? 1 : (value > 42 ? 42 : value);
}

class _DevelopmentPreview extends StatelessWidget {
  const _DevelopmentPreview({required this.fa, required this.onOpenWeek});

  final bool fa;
  final VoidCallback onOpenWeek;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: fa
            ? 'رشد بارداری و تغییرات تو، باز کردن جزئیات هفته'
            : 'Pregnancy development and your changes, open week details',
        child: InkWell(
          onTap: onOpenWeek,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsetsDirectional.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: CocoonTheme.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fa
                      ? 'رشد و تغییرات این هفته'
                      : 'Growth and changes this week',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  fa
                      ? 'جزئیات مادر و بارداری در صفحه‌ی هفته، جدا و خوانا نمایش داده می‌شوند.'
                      : 'Maternal and pregnancy details are separated clearly in the weekly view.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: CocoonTheme.muted),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _PreviewLabel(
                      icon: Icons.favorite_border_rounded,
                      label: fa ? 'رشد بارداری' : 'Pregnancy development',
                      color: CocoonTheme.coral,
                      background: CocoonTheme.coralSoft,
                    ),
                    _PreviewLabel(
                      icon: Icons.self_improvement_rounded,
                      label: fa ? 'تغییرات تو' : 'Your changes',
                      color: CocoonTheme.sageStrong,
                      background: CocoonTheme.sage,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: CocoonTheme.coral,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _PreviewLabel extends StatelessWidget {
  const _PreviewLabel({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 12, 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 7),
            Flexible(
              child:
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
            ),
          ],
        ),
      );
}

class _SafetyEntry extends StatelessWidget {
  const _SafetyEntry({required this.fa, this.onTap});
  final bool fa;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: onTap != null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            padding: const EdgeInsetsDirectional.all(18),
            decoration: BoxDecoration(
              border: Border.all(color: CocoonTheme.line),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.health_and_safety_outlined,
                  color: CocoonTheme.coral,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fa ? 'نگرانی پزشکی داری؟' : 'Have a medical concern?',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        fa
                            ? 'سطح توجه و قدم بعدی را روشن ببین.'
                            : 'See the level of attention and your next step.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: CocoonTheme.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      );
}
