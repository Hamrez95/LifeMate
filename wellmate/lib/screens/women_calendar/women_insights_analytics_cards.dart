import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';

class WomenInsightsAnalyticsCards extends StatefulWidget {
  const WomenInsightsAnalyticsCards({super.key});

  @override
  State<WomenInsightsAnalyticsCards> createState() => _WomenInsightsAnalyticsCardsState();
}

class _WomenInsightsAnalyticsCardsState extends State<WomenInsightsAnalyticsCards> {
  bool _loading = true;
  Map<String, dynamic>? _dashboard;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final value = await context.read<LifeMateApiClient>().getWomenCalendarDashboard(
        fromDate: now.subtract(const Duration(days: 180)),
        toDate: now,
      );
      if (mounted) setState(() => _dashboard = value);
    } catch (_) {
      // These cards are additive. The canonical calendar remains usable if
      // analytics/insight refresh cannot be loaded.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    final dashboard = _dashboard;
    if (dashboard == null) return const SizedBox.shrink();
    final episodes = (dashboard['episodes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final logs = (dashboard['dailyLogs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final profile = dashboard['profile'] as Map<String, dynamic>? ?? const {};
    return Column(
      children: [
        const SizedBox(height: 14),
        _CycleInsightCard(profile: profile, episodes: episodes, logs: logs),
        const SizedBox(height: 12),
        _CycleAnalyticsCard(episodes: episodes, logs: logs),
      ],
    );
  }
}

class _CycleInsightCard extends StatelessWidget {
  const _CycleInsightCard({
    required this.profile,
    required this.episodes,
    required this.logs,
  });

  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> episodes;
  final List<Map<String, dynamic>> logs;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final insight = _buildInsight(rtl);
    return Semantics(
      container: true,
      label: rtl ? 'بینش چرخه شخصی' : 'Personal cycle insight',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFFFEDF4), Color(0xFFF4EDFF)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFEAD7E2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFC83B60)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rtl ? 'بینش چرخه' : 'Cycle insight',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    insight,
                    style: const TextStyle(color: AppColors.textSecondary, height: 1.55),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    rtl
                        ? 'بر اساس ثبت‌های خودت؛ این متن تشخیص پزشکی نیست.'
                        : 'Based on your own logs; this is not a medical diagnosis.',
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF8A7489)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildInsight(bool rtl) {
    final symptomCounts = <String, int>{};
    for (final row in logs) {
      final values = (row['symptoms'] as List<dynamic>? ?? const [])
          .map((e) => e.toString().toLowerCase())
          .toSet();
      for (final id in values) {
        if (id == 'no_symptom') continue;
        symptomCounts[id] = (symptomCounts[id] ?? 0) + 1;
      }
    }
    final repeated = symptomCounts.entries
        .where((e) => e.value >= 2)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (repeated.isNotEmpty) {
      final name = _symptomLabel(repeated.first.key, rtl);
      return rtl
          ? 'در ثبت‌های اخیر «$name» چند بار تکرار شده. اگر امروز هم تجربه‌اش کردی می‌توانی سریع ثبتش کنی.'
          : '“$name” appeared repeatedly in recent logs. If you notice it today, you can log it quickly.';
    }
    final lastStart = DateTime.tryParse(profile['lastPeriodStart']?.toString() ?? '');
    final cycleLength = profile['cycleLength'] is int ? profile['cycleLength'] as int : 28;
    if (lastStart != null) {
      final predicted = lastStart.add(Duration(days: cycleLength));
      final days = predicted.difference(DateTime.now()).inDays;
      if (days >= -1 && days <= 4) {
        return rtl
            ? 'بر اساس تاریخچه فعلی، شروع دوره بعدی ممکن است نزدیک باشد. اگر خواستی حال امروزت را ثبت کن.'
            : 'Based on your current history, your next period may be approaching. Log today if you want.';
      }
    }
    if (episodes.length < 3) {
      return rtl
          ? 'هنوز در حال یادگیری الگوی چرخه‌ات هستیم. با چند ثبت دیگر، بینش‌ها شخصی‌تر می‌شوند.'
          : 'We are still learning your cycle pattern. A few more logs will make insights more personal.';
    }
    return rtl
        ? 'ثبت‌های اخیرت ذخیره شده‌اند. فقط وقتی الگوی قابل اتکایی وجود داشته باشد، بینش شخصی نمایش می‌دهیم.'
        : 'Your recent logs are saved. Personal insights appear only when there is enough evidence.';
  }
}

class _CycleAnalyticsCard extends StatelessWidget {
  const _CycleAnalyticsCard({required this.episodes, required this.logs});

  final List<Map<String, dynamic>> episodes;
  final List<Map<String, dynamic>> logs;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final lengths = <int>[];
    final sorted = episodes
        .map((e) => DateTime.tryParse(e['startedOn']?.toString() ?? ''))
        .whereType<DateTime>()
        .toList()
      ..sort();
    for (var i = 1; i < sorted.length; i++) {
      final days = sorted[i].difference(sorted[i - 1]).inDays;
      if (days >= 21 && days <= 45) lengths.add(days);
    }
    final durations = <int>[];
    for (final e in episodes) {
      final start = DateTime.tryParse(e['startedOn']?.toString() ?? '');
      final end = DateTime.tryParse(e['endedOn']?.toString() ?? '');
      if (start == null || end == null) continue;
      final days = end.difference(start).inDays + 1;
      if (days >= 1 && days <= 14) durations.add(days);
    }
    final avgCycle = _average(lengths);
    final avgPeriod = _average(durations);
    final symptomCounts = <String, int>{};
    for (final row in logs) {
      for (final id in (row['symptoms'] as List<dynamic>? ?? const []).map((e) => e.toString().toLowerCase()).toSet()) {
        if (id != 'no_symptom') symptomCounts[id] = (symptomCounts[id] ?? 0) + 1;
      }
    }
    final recurring = symptomCounts.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Semantics(
      button: false,
      label: rtl ? 'آمار و الگوهای من' : 'My stats and patterns',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFEAD7E2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights_rounded, color: Color(0xFF8765B4)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rtl ? 'آمار و الگوهای من' : 'My stats & patterns',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _metric(context, rtl ? 'میانگین چرخه' : 'Avg cycle', avgCycle == null ? '—' : '${localizeDigits(context, avgCycle)} ${rtl ? 'روز' : 'days'}')),
                const SizedBox(width: 8),
                Expanded(child: _metric(context, rtl ? 'میانگین دوره' : 'Avg period', avgPeriod == null ? '—' : '${localizeDigits(context, avgPeriod)} ${rtl ? 'روز' : 'days'}')),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              recurring.isEmpty
                  ? (rtl ? 'برای شناسایی الگوهای علائم، چند ثبت دیگر لازم است.' : 'A few more logs are needed to identify symptom patterns.')
                  : (rtl
                      ? 'الگوی تکرارشونده: ${_symptomLabel(recurring.first.key, true)} در ${localizeDigits(context, recurring.first.value)} ثبت اخیر.'
                      : 'Recurring pattern: ${_symptomLabel(recurring.first.key, false)} in ${recurring.first.value} recent logs.'),
              style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              rtl ? 'فقط داده‌های ثبت‌شده؛ پیش‌بینی‌ها داخل این آمار محاسبه نمی‌شوند.' : 'Recorded facts only; predictions are not counted in these stats.',
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF8A7489)),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _metric(BuildContext context, String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F3FB),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      );

  static int? _average(List<int> values) {
    if (values.isEmpty) return null;
    return (values.reduce((a, b) => a + b) / values.length).round();
  }
}

String _symptomLabel(String id, bool rtl) {
  const fa = <String, String>{
    'cramps': 'گرفتگی',
    'headache': 'سردرد',
    'migraine': 'میگرن',
    'lower_back_pain': 'کمردرد',
    'bloating': 'نفخ',
    'fatigue': 'خستگی',
    'nausea': 'تهوع',
    'breast_tenderness': 'حساسیت سینه',
    'mood_changes': 'تغییرات خلق',
    'sleep_changes': 'تغییرات خواب',
    'appetite_changes': 'تغییر اشتها',
    'other': 'سایر',
  };
  const en = <String, String>{
    'cramps': 'Cramps',
    'headache': 'Headache',
    'migraine': 'Migraine',
    'lower_back_pain': 'Lower-back pain',
    'bloating': 'Bloating',
    'fatigue': 'Fatigue',
    'nausea': 'Nausea',
    'breast_tenderness': 'Breast tenderness',
    'mood_changes': 'Mood changes',
    'sleep_changes': 'Sleep changes',
    'appetite_changes': 'Appetite changes',
    'other': 'Other',
  };
  return (rtl ? fa[id] : en[id]) ?? id;
}
