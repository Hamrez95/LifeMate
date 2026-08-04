import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/persian_date_utils.dart';

class CareWomenCalendarScreen extends StatefulWidget {
  const CareWomenCalendarScreen({
    super.key,
    required this.patientUserId,
    required this.patientName,
  });

  final String patientUserId;
  final String patientName;

  @override
  State<CareWomenCalendarScreen> createState() =>
      _CareWomenCalendarScreenState();
}

class _CareWomenCalendarScreenState extends State<CareWomenCalendarScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _summary = const {};

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
      final summary = await context
          .read<LifeMateApiClient>()
          .getCareRecipientWomenCalendar(patientUserId: widget.patientUserId);
      if (mounted) setState(() => _summary = summary);
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          'women_calendar_access_denied' =>
            'دسترسی تقویم بانوان برای شما فعال نیست.',
          'women_calendar_not_active' =>
            'تقویم بانوان برای ${widget.patientName} فعال نیست.',
          'women_calendar_feature_disabled' =>
            'این قابلیت در Build فعلی فعال نیست.',
          _ => 'وضعیت تقویم بانوان دریافت نشد.',
        };
      });
    } catch (error) {
      debugPrint('Care women calendar load failed: $error');
      if (mounted) setState(() => _error = 'وضعیت تقویم بانوان دریافت نشد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recordAction(String actionType, String label) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context
          .read<LifeMateApiClient>()
          .recordCareRecipientWomenSupportAction(
            patientUserId: widget.patientUserId,
            actionType: actionType,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label ثبت شد.')));
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('تقویم بانوان ${widget.patientName}'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _EstimateCard(summary: _summary),
                  const SizedBox(height: 18),
                  _SupportActions(saving: _saving, onAction: _recordAction),
                  const SizedBox(height: 18),
                  _RecentActions(summary: _summary),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF5E6),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      'این صفحه فقط خلاصه‌ای را نشان می‌دهد که صاحب حساب صریحاً اجازه داده است. یادداشت‌های خصوصی نمایش داده نمی‌شوند و زمان‌ها تخمینی‌اند. برای نگرانی پزشکی، خون‌ریزی غیرعادی یا درد شدید با پزشک تماس بگیرید.',
                      style: TextStyle(height: 1.7),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final estimate = summary['estimate'] as Map<String, dynamic>? ?? const {};
    final phase = estimate['phase']?.toString();
    final phaseLabel = switch (phase) {
      'period' => 'دوره احتمالی',
      'pre_period' => 'نزدیک دوره احتمالی',
      'post_period' => 'پس از دوره',
      'cycle' => 'میانه چرخه',
      _ => 'اطلاعات ناکافی',
    };
    final cycleDay = localizeDigits(context, estimate['cycleDay'] ?? '—');
    final next = DateTime.tryParse(
      estimate['nextPeriodStart']?.toString() ?? '',
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFEAF4), Color(0xFFF0ECFF)],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: Colors.white,
            child: Text(
              cycleDay,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Color(0xFF8B4A7B),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'وضعیت امروز',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                Text(phaseLabel),
                if (next != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    'شروع تخمینی بعدی: ${formatAppDate(context, next)}',
                    style: const TextStyle(color: AppColors.secondaryText),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportActions extends StatelessWidget {
  const _SupportActions({required this.saving, required this.onAction});
  final bool saving;
  final Future<void> Function(String, String) onAction;

  @override
  Widget build(BuildContext context) {
    const actions = <(String, String, IconData)>[
      ('hydration', 'آب و نوشیدنی آماده کردم', Icons.local_drink_rounded),
      ('rest', 'زمان استراحت فراهم کردم', Icons.bedtime_rounded),
      ('warmth', 'کیسه آب گرم آماده کردم', Icons.device_thermostat_rounded),
      ('chores', 'بخشی از کارهای خانه را انجام دادم', Icons.home_work_rounded),
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'حمایت‌های غیرپزشکی',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'فقط کارهایی را ثبت کنید که واقعاً انجام داده‌اید.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 12),
          for (final action in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: saving
                      ? null
                      : () => onAction(action.$1, action.$2),
                  icon: Icon(action.$3),
                  label: Text(action.$2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentActions extends StatelessWidget {
  const _RecentActions({required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final actions = (summary['supportActions'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final labels = <String, String>{
      'hydration': 'آب و نوشیدنی',
      'rest': 'فراهم‌کردن استراحت',
      'warmth': 'آماده‌کردن گرما',
      'chores': 'کمک در کارهای خانه',
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'حمایت‌های اخیر',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          if (actions.isEmpty)
            const Text('هنوز حمایتی ثبت نشده است.')
          else
            ...actions.take(8).map((action) {
              final performedAt = DateTime.tryParse(
                action['performedAtUtc']?.toString() ?? '',
              )?.toLocal();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.volunteer_activism_rounded),
                title: Text(
                  labels[action['actionType']?.toString()] ?? 'حمایت ثبت‌شده',
                ),
                subtitle: performedAt == null
                    ? null
                    : Text(formatAppDate(context, performedAt)),
              );
            }),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 52),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('تلاش دوباره'),
          ),
        ],
      ),
    ),
  );
}
