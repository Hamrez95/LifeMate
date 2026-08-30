import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';

class WomenCycleAnalyticsScreen extends StatefulWidget {
  const WomenCycleAnalyticsScreen({super.key});

  @override
  State<WomenCycleAnalyticsScreen> createState() => _WomenCycleAnalyticsScreenState();
}

class _WomenCycleAnalyticsScreenState extends State<WomenCycleAnalyticsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _episodes = const [];
  List<Map<String, dynamic>> _logs = const [];

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final dashboard = await context.read<LifeMateApiClient>().getWomenCalendarDashboard(
        fromDate: now.subtract(const Duration(days: 365)),
        toDate: now,
      );
      if (!mounted) return;
      setState(() {
        _episodes = (dashboard['episodes'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
        _logs = (dashboard['dailyLogs'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = _rtl ? 'آمار دریافت نشد. دوباره تلاش کن.' : 'Analytics could not be loaded. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8FC),
      appBar: AppBar(
        title: Text(_rtl ? 'آمار و الگوهای من' : 'My stats & patterns'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(_error!),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
                    children: _buildContent(context),
                  ),
                ),
    );
  }

  List<Widget> _buildContent(BuildContext context) {
    final starts = _episodes
        .map((e) => DateTime.tryParse(e['startedOn']?.toString() ?? ''))
        .whereType<DateTime>()
        .toList()
      ..sort();
    final cycleLengths = <int>[];
    for (var i = 1; i < starts.length; i++) {
      final days = starts[i].difference(starts[i - 1]).inDays;
      if (days >= 21 && days <= 45) cycleLengths.add(days);
    }
    final periodDurations = <int>[];
    for (final episode in _episodes) {
      final start = DateTime.tryParse(episode['startedOn']?.toString() ?? '');
      final end = DateTime.tryParse(episode['endedOn']?.toString() ?? '');
      if (start == null || end == null) continue;
      final days = end.difference(start).inDays + 1;
      if (days >= 1 && days <= 14) periodDurations.add(days);
    }
    final pains = _logs
        .map((e) => int.tryParse(e['painLevel']?.toString() ?? ''))
        .whereType<int>()
        .where((v) => v >= 0 && v <= 5)
        .toList();
    final symptoms = <String, int>{};
    final flows = <String, int>{};
    final appearances = <String, int>{};
    final textures = <String, int>{};
    for (final log in _logs) {
      for (final id in (log['symptoms'] as List<dynamic>? ?? const []).map((e) => e.toString().toLowerCase()).toSet()) {
        if (id != 'no_symptom') symptoms[id] = (symptoms[id] ?? 0) + 1;
      }
      _count(flows, log['periodFlow']);
      _count(appearances, log['bloodAppearance']);
      _count(textures, log['bloodTexture']);
    }
    final recurring = symptoms.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final variation = cycleLengths.length < 2
        ? null
        : cycleLengths.reduce((a, b) => a > b ? a : b) - cycleLengths.reduce((a, b) => a < b ? a : b);

    if (_episodes.isEmpty && _logs.isEmpty) {
      return [
        _card(
          icon: Icons.insights_outlined,
          title: _rtl ? 'هنوز داده کافی نداریم' : 'Not enough data yet',
          child: Text(
            _rtl ? 'با ثبت دوره‌ها و حال روزانه، این صفحه به‌مرور الگوهای شخصی خودت را نشان می‌دهد.' : 'As you log periods and daily observations, this page will gradually show your own patterns.',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.6),
          ),
        ),
      ];
    }

    return [
      _card(
        icon: Icons.fact_check_outlined,
        title: _rtl ? 'خلاصه ثبت‌های واقعی' : 'Recorded facts summary',
        child: Column(
          children: [
            Row(children: [
              Expanded(child: _metric(context, _rtl ? 'میانگین چرخه' : 'Avg cycle', _formatDays(context, _avg(cycleLengths)))),
              const SizedBox(width: 8),
              Expanded(child: _metric(context, _rtl ? 'میانگین دوره' : 'Avg period', _formatDays(context, _avg(periodDurations)))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _metric(context, _rtl ? 'میانگین درد ثبت‌شده' : 'Avg recorded pain', pains.isEmpty ? '—' : '${_avg(pains)}/5')),
              const SizedBox(width: 8),
              Expanded(child: _metric(context, _rtl ? 'تغییر طول چرخه' : 'Cycle variation', variation == null ? '—' : _formatDays(context, variation))),
            ]),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _card(
        icon: Icons.timeline_rounded,
        title: _rtl ? 'الگوی چرخه' : 'Cycle pattern',
        child: Text(
          cycleLengths.length < 2
              ? (_rtl ? 'برای مقایسه طول چرخه‌ها حداقل چند دوره ثبت‌شده لازم است.' : 'A few recorded cycles are needed before comparing cycle lengths.')
              : variation != null && variation <= 7
                  ? (_rtl ? 'طول چرخه‌های ثبت‌شده اخیر نسبتاً نزدیک به هم بوده‌اند.' : 'Your recently recorded cycle lengths have been relatively close to one another.')
                  : (_rtl ? 'طول چرخه‌های ثبت‌شده اخیر تغییر بیشتری داشته‌اند.' : 'Your recently recorded cycle lengths have varied more.'),
          style: const TextStyle(color: AppColors.textSecondary, height: 1.6),
        ),
      ),
      const SizedBox(height: 12),
      _distributionCard(context, _rtl ? 'شدت خون‌ریزی ثبت‌شده' : 'Recorded flow', flows, _flowLabel),
      const SizedBox(height: 12),
      _distributionCard(context, _rtl ? 'ظاهر خون ثبت‌شده' : 'Recorded blood appearance', appearances, _appearanceLabel),
      const SizedBox(height: 12),
      _distributionCard(context, _rtl ? 'بافت ثبت‌شده' : 'Recorded texture', textures, _textureLabel),
      const SizedBox(height: 12),
      _card(
        icon: Icons.auto_awesome_outlined,
        title: _rtl ? 'علائم تکرارشونده' : 'Recurring symptoms',
        child: recurring.isEmpty
            ? Text(_rtl ? 'هنوز علامتی با شواهد تکرار کافی دیده نشده.' : 'No symptom has enough repeated observations yet.', style: const TextStyle(color: AppColors.textSecondary))
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recurring.take(8).map((e) => Chip(label: Text('${_symptomLabel(e.key)} · ${localizeDigits(context, e.value)}'))).toList(),
              ),
      ),
      const SizedBox(height: 14),
      Text(
        _rtl
            ? 'این صفحه فقط ثبت‌های خودت را خلاصه می‌کند و تشخیص پزشکی یا برچسب «طبیعی/غیرطبیعی» ارائه نمی‌دهد.'
            : 'This page summarizes only your own recorded observations and does not provide a diagnosis or “normal/abnormal” label.',
        style: const TextStyle(fontSize: 11, color: Color(0xFF8A7489), height: 1.6),
      ),
    ];
  }

  Widget _distributionCard(
    BuildContext context,
    String title,
    Map<String, int> values,
    String Function(String) label,
  ) {
    final sorted = values.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return _card(
      icon: Icons.bar_chart_rounded,
      title: title,
      child: sorted.isEmpty
          ? Text(_rtl ? 'هنوز ثبت کافی وجود ندارد.' : 'No recorded data yet.', style: const TextStyle(color: AppColors.textSecondary))
          : Column(
              children: sorted.map((e) {
                final total = values.values.fold<int>(0, (sum, value) => sum + value);
                final fraction = total == 0 ? 0.0 : e.value / total;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(child: Text(label(e.key), style: const TextStyle(fontWeight: FontWeight.w700))),
                        Text(localizeDigits(context, e.value), style: const TextStyle(color: AppColors.textSecondary)),
                      ]),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: fraction, minHeight: 7, borderRadius: BorderRadius.circular(8)),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _card({required IconData icon, required String title, required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFEAD7E2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: const Color(0xFF8765B4)),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _metric(BuildContext context, String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFF8F3FB), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ]),
      );

  int? _avg(List<int> values) => values.isEmpty ? null : (values.reduce((a, b) => a + b) / values.length).round();
  String _formatDays(BuildContext context, int? value) => value == null ? '—' : '${localizeDigits(context, value)} ${_rtl ? 'روز' : 'days'}';
  void _count(Map<String, int> target, dynamic raw) {
    final key = raw?.toString().trim().toLowerCase();
    if (key == null || key.isEmpty) return;
    target[key] = (target[key] ?? 0) + 1;
  }

  String _symptomLabel(String id) {
    const fa = {'cramps':'گرفتگی','headache':'سردرد','migraine':'میگرن','lower_back_pain':'کمردرد','bloating':'نفخ','fatigue':'خستگی','nausea':'تهوع','breast_tenderness':'حساسیت سینه','mood_changes':'تغییرات خلق','sleep_changes':'تغییرات خواب','appetite_changes':'تغییر اشتها','other':'سایر'};
    const en = {'cramps':'Cramps','headache':'Headache','migraine':'Migraine','lower_back_pain':'Lower-back pain','bloating':'Bloating','fatigue':'Fatigue','nausea':'Nausea','breast_tenderness':'Breast tenderness','mood_changes':'Mood changes','sleep_changes':'Sleep changes','appetite_changes':'Appetite changes','other':'Other'};
    return (_rtl ? fa[id] : en[id]) ?? id;
  }
  String _flowLabel(String id) => {'light':_rtl?'کم':'Light','medium':_rtl?'متوسط':'Medium','heavy':_rtl?'زیاد':'Heavy'}[id] ?? id;
  String _appearanceLabel(String id) => {'bright_red':_rtl?'قرمز روشن':'Bright red','red':_rtl?'قرمز':'Red','dark_red':_rtl?'قرمز تیره':'Dark red','brown':_rtl?'قهوه‌ای':'Brown'}[id] ?? id;
  String _textureLabel(String id) => {'usual':_rtl?'معمول':'Usual','watery':_rtl?'آبکی':'Watery','thick':_rtl?'غلیظ':'Thick','clot_observed':_rtl?'لخته مشاهده شد':'Clot observed'}[id] ?? id;
}
