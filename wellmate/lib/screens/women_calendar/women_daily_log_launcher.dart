import 'package:flutter/material.dart';

import 'women_circle_card.dart';
import 'women_cycle_analytics_screen.dart';
import 'women_daily_log_api.dart';
import 'women_daily_log_visuals.dart';
import 'women_insight_preferences_card.dart';
import 'women_insights_analytics_cards.dart';

class WomenDailyLogLauncher extends StatefulWidget {
  const WomenDailyLogLauncher({super.key, required this.date, this.onSaved});
  final DateTime date;
  final VoidCallback? onSaved;

  @override
  State<WomenDailyLogLauncher> createState() => _WomenDailyLogLauncherState();
}

class _WomenDailyLogLauncherState extends State<WomenDailyLogLauncher> {
  bool busy = false;

  Future<void> open() async {
    if (busy) return;
    setState(() => busy = true);
    final api = WomenDailyLogApi.fromEnvironment();
    try {
      final logs = await api.list(from: widget.date, to: widget.date);
      final row = logs.isEmpty ? null : logs.first;
      final initial = row == null ? null : WomenDailyLogDraft(
        loggedOn: widget.date,
        version: int.tryParse(row['version']?.toString() ?? '') ?? 0,
        periodFlow: row['periodFlow']?.toString(),
        bloodAppearance: row['bloodAppearance']?.toString(),
        bloodTexture: row['bloodTexture']?.toString(),
        painLevel: row['painLevel'] is int ? row['painLevel'] as int : int.tryParse(row['painLevel']?.toString() ?? ''),
        symptoms: (row['symptoms'] as List<dynamic>? ?? const []).map((e) => e.toString()).toSet(),
        privateNotes: row['privateNotes']?.toString(),
      );
      if (!mounted) return;
      final draft = await showWomenDailyLogSheet(context, loggedOn: widget.date, initial: initial);
      if (draft == null) return;
      await api.save(draft);
      widget.onSaved?.call();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ثبت روزانه ذخیره شد')));
    } finally {
      api.close();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Column(
      children: [
        Semantics(
          button: true,
          label: rtl ? 'ثبت روزانه پریود' : 'Daily period log',
          child: FilledButton.icon(
            key: const ValueKey('women-daily-log-launcher'),
            onPressed: busy ? null : open,
            style: FilledButton.styleFrom(backgroundColor: womenLogPrimary, minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.edit_calendar_rounded),
            label: Text(rtl ? 'ثبت حال امروز' : 'Log today', style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
        const WomenInsightsAnalyticsCards(),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('women-full-analytics-launcher'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const WomenCycleAnalyticsScreen()),
            ),
            icon: const Icon(Icons.insights_rounded),
            label: Text(rtl ? 'مشاهده آمار کامل' : 'View full analytics'),
          ),
        ),
        const SizedBox(height: 12),
        const WomenInsightPreferencesCard(),
        const SizedBox(height: 12),
        const WomenCircleCard(),
      ],
    );
  }
}
