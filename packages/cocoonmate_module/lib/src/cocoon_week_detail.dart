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
            Container(
              padding: const EdgeInsetsDirectional.all(24),
              decoration: BoxDecoration(
                color: CocoonTheme.warm,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Column(
                children: [
                  CocoonGrowthOrb(
                    progress: ((age?.totalDays ?? 0) / 280)
                        .clamp(0.0, 1.0)
                        .toDouble(),
                    semanticLabel: fa
                        ? 'نمایش انتزاعی پیشرفت بارداری'
                        : 'Abstract pregnancy progress visualization',
                    size: 188,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    selection?.content.title ??
                        (fa
                            ? 'زمان‌بندی در حال همگام‌سازی'
                            : 'Dating is syncing'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    selection?.content.body ??
                        (fa
                            ? 'برای نمایش محتوای دقیق، تاریخ بارداری باید از منبع معتبر دریافت شود.'
                            : 'Verified pregnancy dating is required for precise content.'),
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: CocoonTheme.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            CocoonSectionHeading(
              title: fa ? 'آنچه می‌توانی دنبال کنی' : 'What you can follow',
              supporting: fa
                  ? 'اطلاعات مادر و رشد بارداری جدا اما هماهنگ‌اند'
                  : 'Maternal and pregnancy information, clearly separated',
            ),
            const SizedBox(height: 16),
            _WeekLane(
              icon: Icons.favorite_border_rounded,
              color: CocoonTheme.coral,
              background: CocoonTheme.coralSoft,
              title: fa ? 'رشد بارداری' : 'Pregnancy development',
              body: fa
                  ? 'فقط محتوای پزشکی تأییدشده برای این هفته نمایش داده می‌شود.'
                  : 'Only approved medical content for this week is shown.',
            ),
            const SizedBox(height: 12),
            _WeekLane(
              icon: Icons.self_improvement_rounded,
              color: CocoonTheme.sageStrong,
              background: CocoonTheme.sage,
              title: fa ? 'بدن و حال تو' : 'Your body and wellbeing',
              body: fa
                  ? 'ثبت علائم از توصیه‌های پزشکی جدا نگه داشته می‌شود.'
                  : 'Symptom logging stays distinct from medical guidance.',
            ),
            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 19,
                  color: CocoonTheme.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fa
                        ? 'نسخه و تاریخ بازبینی محتوای پزشکی در هر مطلب قابل مشاهده است.'
                        : 'Clinical review date and version remain available on every article.',
                    style: Theme.of(context).textTheme.labelMedium,
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

class _WeekLane extends StatelessWidget {
  const _WeekLane({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration:
                  BoxDecoration(color: background, shape: BoxShape.circle),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    body,
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
