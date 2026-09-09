part of '../cocoonmate_module.dart';

class CocoonWeekDetail extends StatelessWidget {
  const CocoonWeekDetail({required this.host, required this.fa, super.key});

  final CocoonHostContract host;
  final bool fa;

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
    final selection = week == null
        ? null
        : bundledPregnancyClinicalContent.weekly(
            gestationalWeek: _safeWeek(week),
            locale: fa ? 'fa' : 'en',
            atUtc: DateTime.now().toUtc(),
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          week == null
              ? (fa ? 'این هفته' : 'This week')
              : (fa ? 'هفته ${cocoonDigits('$week', true)}' : 'Week $week'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 32),
          children: [
            _WeekHero(
              fa: fa,
              week: week,
              day: day,
              progress:
                  ((age?.totalDays ?? 0) / 280).clamp(0.0, 1.0).toDouble(),
            ),
            const SizedBox(height: 24),
            _GestationalProgressSummary(fa: fa, age: age),
            const SizedBox(height: 32),
            Semantics(
              header: true,
              child: CocoonSectionHeading(
                title: fa ? 'راهنمای بازبینی‌شده' : 'Reviewed weekly guide',
                supporting: fa
                    ? 'محتوا فقط از مجموعه‌ی تأییدشده نمایش داده می‌شود'
                    : 'Content is shown only from the approved registry',
              ),
            ),
            const SizedBox(height: 16),
            _ReviewedWeeklyNote(fa: fa, selection: selection),
            const SizedBox(height: 32),
            Semantics(
              header: true,
              child: CocoonSectionHeading(
                title: fa ? 'جزئیات این هفته' : 'This week in detail',
                supporting: fa
                    ? 'بخش‌های فاقد محتوای تأییدشده، شفاف مشخص شده‌اند'
                    : 'Sections without approved content are marked clearly',
              ),
            ),
            const SizedBox(height: 16),
            _WeekTopicGrid(fa: fa),
            const SizedBox(height: 26),
            _AttentionBoundary(fa: fa),
            const SizedBox(height: 30),
            _ClinicalMetadata(fa: fa, selection: selection),
          ],
        ),
      ),
    );
  }

  int _safeWeek(int value) => value < 1 ? 1 : (value > 42 ? 42 : value);
}

class _WeekHero extends StatelessWidget {
  const _WeekHero({
    required this.fa,
    required this.week,
    required this.day,
    required this.progress,
  });

  final bool fa;
  final int? week;
  final int? day;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final hasAge = week != null && day != null;
    return Semantics(
      container: true,
      label: hasAge
          ? (fa ? 'هفته $week و $day روز' : 'Week $week and $day days')
          : (fa
              ? 'زمان بارداری در دسترس نیست'
              : 'Pregnancy dating unavailable'),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 24, 26),
        decoration: BoxDecoration(
          color: CocoonTheme.warm,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          children: [
            CocoonGrowthOrb(
              progress: progress,
              semanticLabel: fa
                  ? 'نمایش انتزاعی پیشرفت بارداری'
                  : 'Abstract pregnancy progress visualization',
              size: 188,
            ),
            const SizedBox(height: 22),
            Text(
              hasAge
                  ? (fa
                      ? 'هفته ${cocoonDigits('$week', true)}، روز ${cocoonDigits('$day', true)}'
                      : 'Week $week, day $day')
                  : (fa ? 'زمان‌بندی در حال همگام‌سازی' : 'Dating is syncing'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              hasAge
                  ? (fa
                      ? 'یک نمای آرام و روشن از همین مرحله'
                      : 'A calm, clear view of this stage')
                  : (fa
                      ? 'پس از دریافت تاریخ معتبر، جزئیات این مرحله نمایش داده می‌شود.'
                      : 'Details appear after verified dating is available.'),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: CocoonTheme.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _GestationalProgressSummary extends StatelessWidget {
  const _GestationalProgressSummary({required this.fa, required this.age});

  final bool fa;
  final CocoonGestationalAge? age;

  @override
  Widget build(BuildContext context) {
    final progress = ((age?.totalDays ?? 0) / 280).clamp(0.0, 1.0).toDouble();
    return Semantics(
      label: fa
          ? 'پیشرفت بارداری بر پایه تاریخ ثبت‌شده'
          : 'Pregnancy progress based on recorded dating',
      value: age == null
          ? (fa ? 'نامشخص' : 'Unavailable')
          : '${(progress * 100).round()}%',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsetsDirectional.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: CocoonTheme.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fa ? 'مسیر بارداری' : 'Pregnancy timeline',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: age == null ? 0 : progress,
                  backgroundColor: CocoonTheme.coralSoft,
                  color: CocoonTheme.coral,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                age == null
                    ? (fa
                        ? 'تاریخ معتبر برای نمایش پیشرفت در دسترس نیست.'
                        : 'Verified dating is unavailable for progress display.')
                    : (fa
                        ? 'محاسبه‌شده از تاریخ مرجع ثبت‌شده'
                        : 'Calculated from the recorded dating source'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewedWeeklyNote extends StatelessWidget {
  const _ReviewedWeeklyNote({required this.fa, required this.selection});

  final bool fa;
  final ClinicalContentSelection? selection;

  @override
  Widget build(BuildContext context) {
    final unavailable = selection == null || selection!.usedSafetyFallback;
    return Semantics(
      container: true,
      label: unavailable
          ? (fa
              ? 'راهنمای این هفته در دسترس نیست'
              : 'This week’s guide is unavailable')
          : selection!.content.title,
      child: Container(
        padding: const EdgeInsetsDirectional.all(20),
        decoration: BoxDecoration(
          color: CocoonTheme.sky,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              unavailable
                  ? Icons.inventory_2_outlined
                  : Icons.menu_book_rounded,
              color: CocoonTheme.skyStrong,
              size: 28,
            ),
            const SizedBox(height: 16),
            Text(
              selection?.content.title ??
                  (fa ? 'راهنمای این هفته' : 'This week’s guide'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              selection?.content.body ??
                  (fa
                      ? 'محتوای بازبینی‌شده برای این مرحله هنوز در دسترس نیست.'
                      : 'Reviewed content for this stage is not available yet.'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekTopicGrid extends StatelessWidget {
  const _WeekTopicGrid({required this.fa});

  final bool fa;

  @override
  Widget build(BuildContext context) {
    final topics = <(IconData, String)>[
      (
        Icons.favorite_border_rounded,
        fa ? 'رشد بارداری' : 'Pregnancy development',
      ),
      (Icons.self_improvement_rounded, fa ? 'تغییرات تو' : 'Your changes'),
      (Icons.straighten_rounded, fa ? 'اندازه و مقایسه' : 'Size comparison'),
      (
        Icons.restaurant_outlined,
        fa ? 'تغذیه و سبک زندگی' : 'Nutrition and lifestyle',
      ),
      (Icons.fact_check_outlined, fa ? 'آزمایش‌های پیش رو' : 'Upcoming tests'),
      (Icons.checklist_rounded, fa ? 'چک‌لیست هفته' : 'Weekly checklist'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final oneColumn = constraints.maxWidth < 330 ||
            MediaQuery.textScalerOf(context).scale(14) > 19;
        final width =
            oneColumn ? constraints.maxWidth : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final topic in topics)
              SizedBox(
                width: width,
                child: _UnavailableTopic(
                  fa: fa,
                  icon: topic.$1,
                  title: topic.$2,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _UnavailableTopic extends StatelessWidget {
  const _UnavailableTopic({
    required this.fa,
    required this.icon,
    required this.title,
  });

  final bool fa;
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
        label:
            '$title، ${fa ? 'محتوای تأییدشده در دسترس نیست' : 'Approved content unavailable'}',
        child: Container(
          padding: const EdgeInsetsDirectional.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: CocoonTheme.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: CocoonTheme.muted, size: 22),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 5),
              Text(
                fa ? 'در انتظار محتوای تأییدشده' : 'Awaiting approved content',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      );
}

class _AttentionBoundary extends StatelessWidget {
  const _AttentionBoundary({required this.fa});

  final bool fa;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: fa
            ? 'راهنمای توجه پزشکی، مسیر جداگانه'
            : 'Medical attention guidance, separate pathway',
        child: Container(
          padding: const EdgeInsetsDirectional.all(18),
          decoration: BoxDecoration(
            color: CocoonTheme.coralSoft,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                      fa ? 'نشانه‌های نیازمند توجه' : 'Signs needing attention',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fa
                          ? 'راهنمای پزشکی فقط از مسیر بازبینی‌شده‌ی ایمنی نمایش داده می‌شود.'
                          : 'Medical guidance is shown only through the reviewed safety pathway.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _ClinicalMetadata extends StatelessWidget {
  const _ClinicalMetadata({required this.fa, required this.selection});

  final bool fa;
  final ClinicalContentSelection? selection;

  @override
  Widget build(BuildContext context) {
    final content = selection?.content;
    final review = content?.review;
    final reviewDate = review == null
        ? null
        : '${review.reviewedAtUtc.year}-${review.reviewedAtUtc.month.toString().padLeft(2, '0')}-${review.reviewedAtUtc.day.toString().padLeft(2, '0')}';
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(0, 18, 0, 0),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: CocoonTheme.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.verified_user_outlined,
              size: 19,
              color: CocoonTheme.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                content == null
                    ? (fa
                        ? 'اطلاعات بازبینی این مطلب در دسترس نیست.'
                        : 'Review information is unavailable for this guide.')
                    : (fa
                        ? 'نسخه ${cocoonDigits('${content.version}', true)} · بازبینی $reviewDate'
                        : 'Version ${content.version} · reviewed $reviewDate'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
