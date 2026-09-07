part of '../cocoonmate_module.dart';

class CocoonPregnancyCalendar extends StatelessWidget {
  const CocoonPregnancyCalendar({
    required this.host,
    required this.fa,
    super.key,
  });

  final CocoonHostContract host;
  final bool fa;

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
                _GestationalTimeline(fa: fa, age: age),
                const SizedBox(height: 32),
                CocoonSectionHeading(
                  title: t('Care plan', 'برنامه‌ی مراقبت'),
                  supporting: t(
                    'Appointments and reminders appear only after they are saved',
                    'قرارها و یادآوری‌ها فقط پس از ثبت نمایش داده می‌شوند',
                  ),
                ),
                const SizedBox(height: 14),
                _CalendarEmptyState(fa: fa),
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
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: CocoonTheme.sageStrong),
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
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: CocoonTheme.muted),
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
  const _GestationalTimeline({required this.fa, required this.age});

  final bool fa;
  final CocoonGestationalAge? age;

  @override
  Widget build(BuildContext context) {
    final currentWeek = age?.week.clamp(0, 42).toInt();
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
            Row(
              children: [
                _TrimesterLabel(
                  title: fa ? 'سه‌ماهه اول' : 'First',
                  range: fa ? '۰–۱۳' : '0–13',
                  active: currentWeek != null && currentWeek <= 13,
                ),
                const SizedBox(width: 8),
                _TrimesterLabel(
                  title: fa ? 'سه‌ماهه دوم' : 'Second',
                  range: fa ? '۱۴–۲۷' : '14–27',
                  active: currentWeek != null &&
                      currentWeek >= 14 &&
                      currentWeek <= 27,
                ),
                const SizedBox(width: 8),
                _TrimesterLabel(
                  title: fa ? 'سه‌ماهه سوم' : 'Third',
                  range: fa ? '۲۸–۴۰+' : '28–40+',
                  active: currentWeek != null && currentWeek >= 28,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _NearbyWeeks(fa: fa, currentWeek: currentWeek),
          ],
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: active ? CocoonTheme.warm : CocoonTheme.cream,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? CocoonTheme.coral : CocoonTheme.line,
            ),
          ),
          child: Column(
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: active ? CocoonTheme.coral : CocoonTheme.muted,
                    ),
              ),
              const SizedBox(height: 2),
              Text(range, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      );
}

class _NearbyWeeks extends StatelessWidget {
  const _NearbyWeeks({required this.fa, required this.currentWeek});

  final bool fa;
  final int? currentWeek;

  @override
  Widget build(BuildContext context) {
    if (currentWeek == null) {
      return Text(
        fa
            ? 'پس از دریافت تاریخ معتبر، هفته‌های نزدیک نمایش داده می‌شوند.'
            : 'Nearby weeks appear after verified dating is available.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: CocoonTheme.muted),
      );
    }
    final start = (currentWeek! - 2).clamp(0, 40).toInt();
    final weeks = List<int>.generate(5, (index) => start + index);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: weeks.map((week) {
          final active = week == currentWeek;
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Semantics(
              selected: active,
              label: fa ? 'هفته ${cocoonDigits('$week', true)}' : 'Week $week',
              child: Container(
                width: 62,
                padding: const EdgeInsetsDirectional.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: active ? CocoonTheme.ink : CocoonTheme.cream,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Text(
                      fa ? 'هفته' : 'Week',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: active ? Colors.white70 : CocoonTheme.muted,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cocoonDigits('$week', fa),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: active ? Colors.white : CocoonTheme.ink,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CalendarEmptyState extends StatelessWidget {
  const _CalendarEmptyState({required this.fa});

  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.all(20),
        decoration: BoxDecoration(
          color: CocoonTheme.sky,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.event_available_outlined,
                color: CocoonTheme.skyStrong,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fa ? 'برنامه‌ای ثبت نشده' : 'No saved care plan',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    fa
                        ? 'وقتی قرار یا یادآوری معتبر ثبت شود، اینجا به‌ترتیب زمان دیده می‌شود.'
                        : 'Saved appointments and reminders will appear here in time order.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: CocoonTheme.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
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
