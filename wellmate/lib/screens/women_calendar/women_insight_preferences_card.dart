import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import 'women_insight_preferences_api.dart';

class WomenInsightPreferencesCard extends StatefulWidget {
  const WomenInsightPreferencesCard({super.key});

  @override
  State<WomenInsightPreferencesCard> createState() => _WomenInsightPreferencesCardState();
}

class _WomenInsightPreferencesCardState extends State<WomenInsightPreferencesCard> {
  bool _loading = true;
  bool _saving = false;
  bool _insightsEnabled = true;
  bool _notificationsEnabled = false;
  bool _expectedPeriod = true;
  bool _loggingReminder = true;
  String _frequency = 'balanced';
  int _version = 0;

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final dashboard = await context.read<LifeMateApiClient>().getWomenCalendarDashboard(
        fromDate: now.subtract(const Duration(days: 7)),
        toDate: now,
      );
      final profile = dashboard['profile'] as Map<String, dynamic>? ?? const {};
      final value = profile['insightPreferences'] as Map<String, dynamic>? ?? const {};
      if (!mounted) return;
      setState(() {
        _insightsEnabled = value['insightsEnabled'] != false;
        _notificationsEnabled = value['notificationsEnabled'] == true;
        _expectedPeriod = value['expectedPeriodNotifications'] != false;
        _loggingReminder = value['loggingReminderNotifications'] != false;
        _frequency = value['frequencyMode']?.toString() ?? 'balanced';
        _version = value['version'] is int ? value['version'] as int : 0;
      });
    } catch (_) {
      // Additive control: calendar stays available when preferences cannot load.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final api = WomenInsightPreferencesApi.fromEnvironment();
    try {
      final profile = await api.update({
        'version': _version,
        'insightsEnabled': _insightsEnabled,
        'notificationsEnabled': _notificationsEnabled,
        'expectedPeriodNotifications': _expectedPeriod,
        'loggingReminderNotifications': _loggingReminder,
        'frequencyMode': _frequency,
      });
      final value = profile['insightPreferences'] as Map<String, dynamic>? ?? const {};
      if (!mounted) return;
      setState(() {
        _version = value['version'] is int ? value['version'] as int : _version + 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_rtl ? 'تنظیمات بینش چرخه ذخیره شد.' : 'Cycle Insight settings saved.')),
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'stale_cycle_insight_preferences') await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_rtl ? 'تنظیمات ذخیره نشد. دوباره تلاش کن.' : 'Settings were not saved. Try again.')),
      );
    } finally {
      api.close();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('women-cycle-insight-preferences'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFD),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEAD7E2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined, color: Color(0xFFC83B60)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _rtl ? 'تنظیمات بینش چرخه' : 'Cycle Insight settings',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            _rtl
                ? 'بینش داخل اپ مستقل از اجازه اعلان گوشی است. اعلان‌ها فقط در صورت فعال بودن این گزینه و مجوز سیستم استفاده می‌شوند.'
                : 'In-app insights work independently of OS notification permission. Notifications are used only when enabled here and allowed by the system.',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _insightsEnabled,
            title: Text(_rtl ? 'بینش‌های شخصی داخل اپ' : 'Personal in-app insights'),
            onChanged: _saving ? null : (v) => setState(() => _insightsEnabled = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _notificationsEnabled,
            title: Text(_rtl ? 'اعلان‌های Cycle Insight' : 'Cycle Insight notifications'),
            subtitle: Text(_rtl ? 'فعلاً فقط مسیرهای اعلان واقعاً پشتیبانی‌شده دستگاه.' : 'Only notification paths actually supported on this device are used.'),
            onChanged: _saving ? null : (v) => setState(() => _notificationsEnabled = v),
          ),
          if (_notificationsEnabled) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _expectedPeriod,
              title: Text(_rtl ? 'نزدیک شدن احتمالی دوره' : 'Expected period window'),
              onChanged: _saving ? null : (v) => setState(() => _expectedPeriod = v ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _loggingReminder,
              title: Text(_rtl ? 'یادآوری ثبت حال' : 'Logging reminder'),
              onChanged: _saving ? null : (v) => setState(() => _loggingReminder = v ?? false),
            ),
          ],
          const SizedBox(height: 6),
          Text(_rtl ? 'تعداد پیام‌ها' : 'Frequency', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'low', label: Text(_rtl ? 'کم' : 'Low')),
              ButtonSegment(value: 'balanced', label: Text(_rtl ? 'متعادل' : 'Balanced')),
              ButtonSegment(value: 'high', label: Text(_rtl ? 'بیشتر' : 'More')),
            ],
            selected: {_frequency},
            onSelectionChanged: _saving ? null : (value) => setState(() => _frequency = value.first),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC83B60)),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_rtl ? 'ذخیره تنظیمات' : 'Save settings'),
            ),
          ),
        ],
      ),
    );
  }
}
