import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';
import 'package:provider/provider.dart';

import 'women_circle_card.dart';
import 'women_cycle_analytics_screen.dart';
import 'women_cycle_insight_notification_scheduler.dart';
import 'women_daily_log_api.dart';
import 'women_daily_log_offline_bridge.dart';
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
  bool pendingSync = false;
  bool syncConflict = false;

  Future<void> open() async {
    if (busy) return;
    setState(() => busy = true);
    final api = WomenDailyLogApi.fromEnvironment();
    WomenDailyLogOfflineBridge? offline;
    try {
      try {
        offline = await WomenDailyLogOfflineBridge.open(
          apiClient: context.read<LifeMateApiClient>(),
        );
      } on UnsupportedError {
        offline = null;
      } on LifeMateApiException {
        offline = null;
      } on StateError {
        offline = null;
      }

      if (offline != null) {
        await offline.flush();
      }

      List<Map<String, dynamic>> serverLogs;
      var canonicalRefreshSucceeded = false;
      try {
        serverLogs = await api.list(from: widget.date, to: widget.date);
        canonicalRefreshSucceeded = true;
        if (offline != null) {
          await offline.cacheServerDay(date: widget.date, serverRows: serverLogs);
        }
      } on LifeMateApiException catch (error) {
        if (offline == null || !_canQueueOffline(error)) rethrow;
        final cached = await offline.readCachedServerDay(widget.date);
        if (cached == null) rethrow;
        serverLogs = cached;
      }

      if (canonicalRefreshSucceeded) {
        await _refreshCanonicalReminders();
      }

      var logs = serverLogs;
      if (offline != null) {
        final projection = await offline.project(
          serverRows: serverLogs,
          fromDate: widget.date,
          toDate: widget.date,
        );
        logs = projection.rows;
        if (mounted) {
          setState(() {
            pendingSync = projection.hasPending;
            syncConflict = projection.hasConflict;
          });
        }
      }

      final row = logs.isEmpty ? null : logs.first;
      final initial = row == null
          ? null
          : WomenDailyLogDraft(
              loggedOn: widget.date,
              version: int.tryParse(row['version']?.toString() ?? '') ?? 0,
              periodFlow: row['periodFlow']?.toString(),
              bloodAppearance: row['bloodAppearance']?.toString(),
              bloodTexture: row['bloodTexture']?.toString(),
              painLevel: row['painLevel'] is int
                  ? row['painLevel'] as int
                  : int.tryParse(row['painLevel']?.toString() ?? ''),
              symptoms: (row['symptoms'] as List<dynamic>? ?? const [])
                  .map((e) => e.toString())
                  .toSet(),
              privateNotes: row['privateNotes']?.toString(),
            );
      if (!mounted) return;
      final draft = await showWomenDailyLogSheet(
        context,
        loggedOn: widget.date,
        initial: initial,
      );
      if (draft == null) return;

      final requestId = LifeMateApiClient.createClientRequestId();
      var queuedOffline = false;
      try {
        final saved = await api.save(draft, clientRequestId: requestId);
        if (offline != null) {
          await offline.cacheServerDay(
            date: draft.loggedOn,
            serverRows: <Map<String, dynamic>>[saved],
          );
        }
        await _refreshCanonicalReminders();
      } on LifeMateApiException catch (error) {
        if (offline == null || !_canQueueOffline(error)) rethrow;
        await offline.enqueueUpsert(
          mutationId: requestId,
          loggedOn: draft.loggedOn,
          version: draft.version,
          periodFlow: draft.periodFlow,
          bloodAppearance: draft.bloodAppearance,
          bloodTexture: draft.bloodTexture,
          painLevel: draft.painLevel,
          symptoms: draft.symptoms,
          privateNotes: draft.privateNotes,
        );
        queuedOffline = true;
      }

      widget.onSaved?.call();
      if (mounted) {
        setState(() {
          pendingSync = queuedOffline;
          if (queuedOffline) syncConflict = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                if (queuedOffline) ...[
                  const Icon(Icons.schedule_send_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Expanded(child: Text(context.tr('common.saved'))),
              ],
            ),
          ),
        );
      }
    } finally {
      offline?.close();
      api.close();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _refreshCanonicalReminders() async {
    if (!mounted) return;
    final client = context.read<LifeMateApiClient>();
    try {
      final dashboard = await client.getWomenCalendarDashboard(
        fromDate: widget.date.subtract(const Duration(days: 45)),
        toDate: widget.date.add(const Duration(days: 45)),
      );
      final profile = dashboard['profile'];
      if (profile is! Map<String, dynamic>) return;
      await WomenCycleInsightNotificationScheduler().sync(
        profile: profile,
        isPersian: Directionality.of(context) == TextDirection.rtl,
      );
    } on LifeMateApiException {
      // A reminder refresh is best-effort and must never turn a successful
      // canonical daily-log read/write into a failed health-data operation.
    } on StateError {
      // Runtime/account transitions can invalidate the dashboard client between
      // the canonical data operation and local scheduler reconciliation.
    }
  }

  static bool _canQueueOffline(LifeMateApiException error) =>
      error.statusCode == 0 ||
      error.statusCode == 408 ||
      error.statusCode == 429 ||
      error.statusCode == 500 ||
      error.statusCode == 502 ||
      error.statusCode == 503 ||
      error.statusCode == 504;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          button: true,
          label: context.tr('women.dailyLog.title'),
          child: FilledButton.icon(
            key: const ValueKey('women-daily-log-launcher'),
            onPressed: busy ? null : open,
            style: FilledButton.styleFrom(
              backgroundColor: womenLogPrimary,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    syncConflict
                        ? Icons.warning_amber_rounded
                        : pendingSync
                            ? Icons.schedule_send_rounded
                            : Icons.edit_calendar_rounded,
                  ),
            label: Text(
              syncConflict
                  ? context.tr('common.retry')
                  : context.tr('women.dailyLog.logToday'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const WomenInsightsAnalyticsCards(),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('women-full-analytics-launcher'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const WomenCycleAnalyticsScreen(),
              ),
            ),
            icon: const Icon(Icons.insights_rounded),
            label: Text(context.tr('women.analytics.full')),
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
