part of '../cocoonmate_module.dart';

class CocoonPregnancyCalendar extends StatelessWidget {
  const CocoonPregnancyCalendar({
    required this.host,
    required this.fa,
    this.state = CocoonCalendarLoadState.empty,
    this.items = const [],
    this.asOfLocalDate,
    this.onOpenItem,
    this.onOpenWeek,
    this.onRetry,
    super.key,
  });

  final CocoonHostContract host;
  final bool fa;
  final CocoonCalendarLoadState state;
  final List<CocoonCalendarItem> items;
  final DateTime? asOfLocalDate;
  final ValueChanged<CocoonCalendarItem>? onOpenItem;
  final ValueChanged<int>? onOpenWeek;
  final VoidCallback? onRetry;

  String t(String en, String faText) => fa ? faText : en;

  CocoonGestationalAge? get _age {
    final snapshot = host.pregnancySnapshot ?? host.offlinePregnancySnapshot;
    final dating = snapshot?.episode?.dating;
    if (dating == null) return null;
    try {
      return deriveCocoonGestationalAgeOffline(
            dating: dating,
            asOfLocalDate: asOfLocalDate ?? DateTime.now(),
          ) ??
          dating.gestationalAge;
    } on CocoonPregnancyDatingError {
      return dating.gestationalAge;
    }
  }

  @override
  Widget build(BuildContext context) {
    final age = _age;
    return CustomScrollView(
      key: const PageStorageKey('cocoon-calendar'),
      slivers: [
        SliverToBoxAdapter(
          child: CocoonPagePadding(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TimelineIntroduction(fa: fa, age: age),
                const SizedBox(height: 30),
                CocoonSectionHeading(
                  title: t('Pregnancy timeline', 'مسیر بارداری'),
                  supporting: t(
                    'Your current place, without calendar clutter',
                    'جای فعلی تو، بدون شلوغی تقویم',
                  ),
                ),
                const SizedBox(height: 16),
                _GestationalTimeline(fa: fa, age: age, onOpenWeek: onOpenWeek),
                const SizedBox(height: 32),
                CocoonSectionHeading(
                  title: t('Care plan', 'برنامه‌ی مراقبت'),
                  supporting: t(
                    'Appointments and reminders appear only after they are saved',
                    'قرارها و یادآوری‌ها فقط پس از ثبت نمایش داده می‌شوند',
                  ),
                ),
                const SizedBox(height: 14),
                _CarePlanState(
                  fa: fa,
                  state: state,
                  items: items,
                  onOpenItem: onOpenItem,
                  onRetry: onRetry,
                ),
                const SizedBox(height: 26),
                _DatingNote(fa: fa),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineIntroduction extends StatelessWidget {
  const _TimelineIntroduction({required this.fa, required this.age});

  final bool fa;
  final CocoonGestationalAge? age;

  @override
  Widget build(BuildContext context) {
    final week = age?.week;
    final day = age?.day;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(22, 22, 22, 20),
      decoration: BoxDecoration(
        color: CocoonTheme.sage,
        borderRadius: BorderRadius.circular(28),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(16) > 21;
          final compact = constraints.maxWidth < 330 || largeText;
          final icon = Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.route_rounded,
              color: CocoonTheme.sageStrong,
              size: 27,
            ),
          );
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fa ? 'امروز در مسیر تو' : 'Today on your journey',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: CocoonTheme.sageStrong),
              ),
              const SizedBox(height: 7),
              Text(
                week == null || day == null
                    ? (fa
                        ? 'در حال همگام‌سازی زمان بارداری'
                        : 'Pregnancy dating is syncing')
                    : (fa
                        ? 'هفته‌ی ${cocoonDigits('$week', true)} و روز ${cocoonDigits('$day', true)}'
                        : 'Week $week, day $day'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 5),
              Text(
                fa
                    ? 'این نما از تاریخ‌گذاری معتبر بارداری محاسبه می‌شود.'
                    : 'This view is calculated from verified pregnancy dating.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: CocoonTheme.muted),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [icon, const SizedBox(height: 18), copy],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(child: copy),
            ],
          );
        },
      ),
    );
  }
}

class _GestationalTimeline extends StatelessWidget {
  const _GestationalTimeline({
    required this.fa,
    required this.age,
    this.onOpenWeek,
  });

  final bool fa;
  final CocoonGestationalAge? age;
  final ValueChanged<int>? onOpenWeek;

  @override
  Widget build(BuildContext context) {
    final week = age?.week;
    final currentWeek = week == null ? null : week.clamp(0, 42).toInt();
    final progress = ((age?.totalDays ?? 0) / 280).clamp(0.0, 1.0).toDouble();
    return Semantics(
      label: currentWeek == null
          ? (fa ? 'زمان بارداری نامشخص' : 'Pregnancy dating unavailable')
          : (fa
              ? 'پیشرفت تا هفته ${cocoonDigits('$currentWeek', true)}'
              : 'Progress through week $currentWeek'),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(18, 20, 18, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: CocoonTheme.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: CocoonTheme.coralSoft,
                color: CocoonTheme.coral,
              ),
            ),
            const SizedBox(height: 16),
            _TrimesterGrid(fa: fa, currentWeek: currentWeek),
            const SizedBox(height: 20),
            _NearbyWeeks(
              fa: fa,
              currentWeek: currentWeek,
              onOpenWeek: onOpenWeek,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrimesterGrid extends StatelessWidget {
  const _TrimesterGrid({required this.fa, required this.currentWeek});

  final bool fa;
  final int? currentWeek;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 350 ||
              MediaQuery.textScalerOf(context).scale(14) > 18;
          final entries = [
            _TrimesterLabel(
              title: fa ? 'سه‌ماهه اول' : 'First trimester',
              range: fa ? '۰–۱۳' : '0–13',
              active: currentWeek != null && currentWeek! <= 13,
            ),
            _TrimesterLabel(
              title: fa ? 'سه‌ماهه دوم' : 'Second trimester',
              range: fa ? '۱۴–۲۷' : '14–27',
              active: currentWeek != null &&
                  currentWeek! >= 14 &&
                  currentWeek! <= 27,
            ),
            _TrimesterLabel(
              title: fa ? 'سه‌ماهه سوم' : 'Third trimester',
              range: fa ? '۲۸–۴۰+' : '28–40+',
              active: currentWeek != null && currentWeek! >= 28,
            ),
          ];
          if (stack) {
            return Column(
              children: [
                for (final entry in entries) ...[
                  SizedBox(width: double.infinity, child: entry),
                  if (entry != entries.last) const SizedBox(height: 8),
                ],
              ],
            );
          }
          return Row(
            children: [
              for (final entry in entries) ...[
                Expanded(child: entry),
                if (entry != entries.last) const SizedBox(width: 8),
              ],
            ],
          );
        },
      );
}

class _TrimesterLabel extends StatelessWidget {
  const _TrimesterLabel({
    required this.title,
    required this.range,
    required this.active,
  });

  final String title;
  final String range;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: active ? CocoonTheme.warm : CocoonTheme.cream,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: active ? CocoonTheme.coral : CocoonTheme.line),
        ),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: active ? CocoonTheme.coral : CocoonTheme.muted),
            ),
            const SizedBox(height: 2),
            Text(range, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      );
}

class _NearbyWeeks extends StatelessWidget {
  const _NearbyWeeks({
    required this.fa,
    required this.currentWeek,
    this.onOpenWeek,
  });

  final bool fa;
  final int? currentWeek;
  final ValueChanged<int>? onOpenWeek;

  @override
  Widget build(BuildContext context) {
    if (currentWeek == null) {
      return Text(
        fa
            ? 'پس از دریافت تاریخ معتبر، هفته‌های نزدیک نمایش داده می‌شوند.'
            : 'Nearby weeks appear after verified dating is available.',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: CocoonTheme.muted),
      );
    }
    final start = (currentWeek! - 2).clamp(0, 40).toInt();
    final weeks = List<int>.generate(5, (index) => start + index);
    return Row(
      children: weeks.indexed.map((entry) {
        final index = entry.$1;
        final week = entry.$2;
        final active = week == currentWeek;
        return Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.only(end: index == 4 ? 0 : 6),
            child: Semantics(
              button: onOpenWeek != null,
              selected: active,
              label: fa ? 'هفته ${cocoonDigits('$week', true)}' : 'Week $week',
              child: InkWell(
                onTap: onOpenWeek == null ? null : () => onOpenWeek!(week),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsetsDirectional.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: active ? CocoonTheme.ink : CocoonTheme.cream,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      Text(
                        fa ? 'هفته' : 'Week',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                              color:
                                  active ? Colors.white70 : CocoonTheme.muted,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cocoonDigits('$week', fa),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              color: active ? Colors.white : CocoonTheme.ink,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CarePlanState extends StatelessWidget {
  const _CarePlanState({
    required this.fa,
    required this.state,
    required this.items,
    this.onOpenItem,
    this.onRetry,
  });

  final bool fa;
  final CocoonCalendarLoadState state;
  final List<CocoonCalendarItem> items;
  final ValueChanged<CocoonCalendarItem>? onOpenItem;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (state == CocoonCalendarLoadState.loading) {
      return CocoonLoadingState(
        semanticLabel:
            fa ? 'در حال بارگذاری برنامه مراقبت' : 'Loading care plan',
      );
    }
    if (state == CocoonCalendarLoadState.error) {
      return CocoonEmptyState(
        icon: Icons.cloud_off_rounded,
        title: fa ? 'برنامه مراقبت در دسترس نیست' : 'Care plan unavailable',
        body: fa
            ? 'برای دریافت اطلاعات به‌روز دوباره تلاش کن.'
            : 'Try again to retrieve your current care plan.',
        actionLabel:
            onRetry == null ? null : (fa ? 'تلاش دوباره' : 'Try again'),
        onAction: onRetry,
      );
    }
    if (state == CocoonCalendarLoadState.empty || items.isEmpty) {
      return _CalendarEmptyState(fa: fa);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state == CocoonCalendarLoadState.offlineCached) ...[
          CocoonStatusBadge(
            icon: Icons.cloud_off_outlined,
            label: fa
                ? 'نمایش آخرین برنامه ذخیره‌شده روی دستگاه'
                : 'Showing the last saved device copy',
          ),
          const SizedBox(height: 12),
        ],
        for (final item in items) ...[
          _CarePlanItem(
            item: item,
            fa: fa,
            onTap: onOpenItem == null ? null : () => onOpenItem!(item),
          ),
          const SizedBox(height: 10),
        ],
        if (state == CocoonCalendarLoadState.partial)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 4),
            child: Text(
              fa
                  ? 'بخش دیگری از برنامه پس از همگام‌سازی نمایش داده می‌شود.'
                  : 'More of this care plan will appear after sync.',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: CocoonTheme.muted),
            ),
          ),
      ],
    );
  }
}

class _CarePlanItem extends StatelessWidget {
  const _CarePlanItem({required this.item, required this.fa, this.onTap});

  final CocoonCalendarItem item;
  final bool fa;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.kind) {
      CocoonCalendarItemKind.appointment => Icons.event_outlined,
      CocoonCalendarItemKind.reminder => Icons.notifications_none_rounded,
      CocoonCalendarItemKind.milestone => Icons.flag_outlined,
    };
    return Semantics(
      button: onTap != null,
      label: '${item.title}، ${item.dateLabel}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CocoonRadii.card),
        child: Ink(
          padding: const EdgeInsetsDirectional.all(CocoonSpacing.lg),
          decoration: BoxDecoration(
            color: CocoonColors.surfaceRaised,
            borderRadius: BorderRadius.circular(CocoonRadii.card),
            border: Border.all(color: CocoonColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: CocoonColors.sky,
                  borderRadius: BorderRadius.circular(CocoonRadii.control),
                ),
                child: Icon(icon, color: CocoonColors.skyStrong),
              ),
              const SizedBox(width: CocoonSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        item.dateLabel,
                        item.timeLabel,
                      ].whereType<String>().join(' · '),
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: CocoonColors.muted),
                    ),
                    if (item.supporting != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        item.supporting!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (item.pendingSync)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Icon(
                    Icons.sync_rounded,
                    size: 18,
                    color: CocoonColors.skyStrong,
                    semanticLabel: fa ? 'در انتظار همگام‌سازی' : 'Pending sync',
                  ),
                )
              else if (onTap != null)
                const Padding(
                  padding: EdgeInsetsDirectional.only(start: 8),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: CocoonColors.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarEmptyState extends StatelessWidget {
  const _CalendarEmptyState({required this.fa});

  final bool fa;

  @override
  Widget build(BuildContext context) => CocoonEmptyState(
        icon: Icons.event_available_outlined,
        title: fa ? 'برنامه‌ای ثبت نشده' : 'No saved care plan',
        body: fa
            ? 'وقتی قرار یا یادآوری معتبر ثبت شود، اینجا به‌ترتیب زمان دیده می‌شود.'
            : 'Saved appointments and reminders will appear here in time order.',
      );
}

class _DatingNote extends StatelessWidget {
  const _DatingNote({required this.fa});

  final bool fa;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 19,
            color: CocoonTheme.muted,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              fa
                  ? 'سن بارداری ممکن است پس از ارزیابی پزشک یا سونوگرافی به‌روزرسانی شود.'
                  : 'Pregnancy dating may be updated after clinician or ultrasound assessment.',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      );
}
