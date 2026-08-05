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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label ثبت شد.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
        toolbarHeight: 64,
        titleSpacing: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تقویم بانوان ${widget.patientName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.primaryText,
              ),
            ),
            const Text(
              'خلاصه مجاز و حمایت‌های غیرپزشکی',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                    children: [
                      _EstimateCard(summary: _summary),
                      const SizedBox(height: 12),
                      _SupportActions(
                        saving: _saving,
                        onAction: _recordAction,
                      ),
                      const SizedBox(height: 12),
                      _RecentActions(summary: _summary),
                      const SizedBox(height: 12),
                      const _PrivacyNotice(),
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
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [Color(0xFFFFEAF4), Color(0xFFF1EEFF)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD95B93).withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD95B93).withValues(alpha: 0.08),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.water_drop_rounded,
                  size: 17,
                  color: Color(0xFFD95B93),
                ),
                Text(
                  cycleDay,
                  style: const TextStyle(
                    fontSize: 25,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF8B4A7B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'وضعیت امروز',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  phaseLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF704363),
                  ),
                ),
                if (next != null) ...[
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.58),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'شروع تخمینی بعدی: ${formatAppDate(context, next)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.secondaryText,
                      ),
                    ),
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

  static const actions = <_SupportDefinition>[
    _SupportDefinition(
      type: 'hydration',
      label: 'آب و نوشیدنی',
      detail: 'آماده کردم',
      icon: Icons.local_drink_rounded,
      color: Color(0xFF4C9BE8),
    ),
    _SupportDefinition(
      type: 'rest',
      label: 'زمان استراحت',
      detail: 'فراهم کردم',
      icon: Icons.bedtime_rounded,
      color: Color(0xFF7772D7),
    ),
    _SupportDefinition(
      type: 'warmth',
      label: 'کیسه آب گرم',
      detail: 'آماده کردم',
      icon: Icons.device_thermostat_rounded,
      color: Color(0xFFE58970),
    ),
    _SupportDefinition(
      type: 'chores',
      label: 'کارهای خانه',
      detail: 'کمک کردم',
      icon: Icons.home_work_rounded,
      color: Color(0xFF55A77A),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.volunteer_activism_rounded,
            title: 'حمایت‌های غیرپزشکی',
            subtitle: 'فقط کاری را ثبت کنید که واقعاً انجام داده‌اید.',
          ),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 330;
              final itemWidth = compact
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: actions
                    .map(
                      (action) => SizedBox(
                        width: itemWidth,
                        child: _SupportActionCard(
                          definition: action,
                          enabled: !saving,
                          onTap: () => onAction(
                            action.type,
                            '${action.label} ${action.detail}',
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          if (saving) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }
}

class _SupportDefinition {
  const _SupportDefinition({
    required this.type,
    required this.label,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final String type;
  final String label;
  final String detail;
  final IconData icon;
  final Color color;
}

class _SupportActionCard extends StatelessWidget {
  const _SupportActionCard({
    required this.definition,
    required this.enabled,
    required this.onTap,
  });

  final _SupportDefinition definition;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${definition.label} ${definition.detail}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(17),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
            decoration: BoxDecoration(
              color: definition.color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: definition.color.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 35,
                  height: 35,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    definition.icon,
                    size: 19,
                    color: definition.color,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        definition.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primaryText,
                        ),
                      ),
                      Text(
                        definition.detail,
                        style: TextStyle(
                          fontSize: 9,
                          color: definition.color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.add_circle_outline_rounded,
                  size: 17,
                  color: definition.color.withValues(
                    alpha: enabled ? 0.86 : 0.34,
                  ),
                ),
              ],
            ),
          ),
        ),
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
    final labels = <String, (String, IconData, Color)>{
      'hydration': (
        'آب و نوشیدنی',
        Icons.local_drink_rounded,
        const Color(0xFF4C9BE8),
      ),
      'rest': (
        'فراهم‌کردن استراحت',
        Icons.bedtime_rounded,
        const Color(0xFF7772D7),
      ),
      'warmth': (
        'آماده‌کردن گرما',
        Icons.device_thermostat_rounded,
        const Color(0xFFE58970),
      ),
      'chores': (
        'کمک در کارهای خانه',
        Icons.home_work_rounded,
        const Color(0xFF55A77A),
      ),
    };

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.history_rounded,
            title: 'حمایت‌های اخیر',
            subtitle: 'آخرین کارهای ثبت‌شده برای این حساب',
          ),
          const SizedBox(height: 10),
          if (actions.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.70),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.favorite_border_rounded,
                    color: AppColors.secondaryText,
                  ),
                  SizedBox(height: 6),
                  Text(
                    'هنوز حمایتی ثبت نشده است.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            )
          else
            ...List.generate(actions.take(8).length, (index) {
              final action = actions[index];
              final definition = labels[action['actionType']?.toString()] ??
                  (
                    'حمایت ثبت‌شده',
                    Icons.volunteer_activism_rounded,
                    AppColors.primaryBlue,
                  );
              final performedAt = DateTime.tryParse(
                action['performedAtUtc']?.toString() ?? '',
              )?.toLocal();
              return Column(
                children: [
                  if (index > 0)
                    Divider(
                      height: 1,
                      indent: 48,
                      color: AppColors.primaryBlue.withValues(alpha: 0.06),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: definition.$3.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            definition.$2,
                            size: 19,
                            color: definition.$3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            definition.$1,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (performedAt != null)
                          Text(
                            formatAppDate(context, performedAt),
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.secondaryText,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.055),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEDF6),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFFD95B93)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0DDAF)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 21,
            color: Color(0xFFB78326),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'این صفحه فقط خلاصه‌ای را نشان می‌دهد که صاحب حساب صریحاً اجازه داده است. یادداشت‌های خصوصی نمایش داده نمی‌شوند و زمان‌ها تخمینی‌اند. برای نگرانی پزشکی، خون‌ریزی غیرعادی یا درد شدید با پزشک تماس بگیرید.',
              style: TextStyle(
                fontSize: 10,
                height: 1.65,
                color: Color(0xFF795F2B),
              ),
            ),
          ),
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
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 48,
                  color: AppColors.primaryBlue,
                ),
                const SizedBox(height: 10),
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
        ),
      );
}
