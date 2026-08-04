// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';

class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  State<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<LifeMateApiClient>().getCurrentUser();
  }

  void _retry() => setState(
    () => _future = context.read<LifeMateApiClient>().getCurrentUser(),
  );

  @override
  Widget build(BuildContext context) {
    return _WellMateDestinationScaffold(
      title: 'اطلاعات شخصی',
      subtitle: 'اطلاعات حساب متصل به LifeMate',
      icon: Icons.person_rounded,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _LoadingCard();
          }
          if (snapshot.hasError) {
            return _ErrorCard(
              message: 'اطلاعات حساب دریافت نشد.',
              onRetry: _retry,
            );
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          final user = data['user'] as Map<String, dynamic>? ?? const {};
          final profile = data['profile'] as Map<String, dynamic>? ?? const {};
          return Column(
            children: [
              _SoftCard(
                child: Column(
                  children: [
                    const _ProfileAvatar(icon: Icons.person_rounded),
                    const SizedBox(height: 16),
                    _InformationRow(
                      label: 'نام نمایشی',
                      value: _value(profile['displayName']),
                      icon: Icons.badge_outlined,
                    ),
                    _InformationRow(
                      label: 'ایمیل',
                      value: _value(user['email'] ?? profile['email']),
                      icon: Icons.alternate_email_rounded,
                      ltr: true,
                    ),
                    _InformationRow(
                      label: 'شماره تماس',
                      value: _value(profile['phoneNumber']),
                      icon: Icons.phone_outlined,
                      ltr: true,
                    ),
                    _InformationRow(
                      label: 'زبان',
                      value: _value(profile['locale'], fallback: 'fa'),
                      icon: Icons.language_rounded,
                    ),
                    _InformationRow(
                      label: 'منطقه زمانی',
                      value: _value(
                        profile['timeZone'],
                        fallback: 'Asia/Tehran',
                      ),
                      icon: Icons.schedule_rounded,
                      ltr: true,
                      showDivider: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const _DevelopmentNotice(
                message:
                    'نمایش اطلاعات از حساب واقعی انجام می‌شود. ویرایش اطلاعات پس از اضافه‌شدن قرارداد امن Backend فعال خواهد شد.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: null,
                  icon: Icon(Icons.edit_outlined),
                  label: Text('ویرایش اطلاعات — در دست توسعه'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class HealthRecordScreen extends StatefulWidget {
  const HealthRecordScreen({super.key});

  @override
  State<HealthRecordScreen> createState() => _HealthRecordScreenState();
}

class _HealthRecordScreenState extends State<HealthRecordScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final api = context.read<LifeMateApiClient>();
    final now = DateTime.now();
    return Future.wait<dynamic>([
      api.getTreatmentPlans(),
      api.getDoseOccurrences(fromDate: now, toDate: now),
    ]);
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return _WellMateDestinationScaffold(
      title: 'پرونده سلامت',
      subtitle: 'خلاصه درمان و پایبندی امروز',
      icon: Icons.assignment_rounded,
      accent: Colors.orangeAccent,
      child: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _LoadingCard();
          }
          if (snapshot.hasError) {
            return _ErrorCard(
              message: 'خلاصه پرونده سلامت دریافت نشد.',
              onRetry: _retry,
            );
          }
          final plans =
              snapshot.data?[0] as List<Map<String, dynamic>>? ??
              const <Map<String, dynamic>>[];
          final doses =
              snapshot.data?[1] as List<Map<String, dynamic>>? ??
              const <Map<String, dynamic>>[];
          final active = plans
              .where((plan) => plan['status'] == 'active')
              .length;
          final taken = doses.where((dose) => dose['status'] == 'taken').length;
          final skipped = doses
              .where((dose) => dose['status'] == 'skipped')
              .length;
          final missed = doses
              .where((dose) => dose['status'] == 'missed')
              .length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      value: '$active',
                      label: 'درمان فعال',
                      icon: Icons.medication_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      value: '$taken',
                      label: 'مصرف‌شده امروز',
                      icon: Icons.check_circle_rounded,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      value: '$skipped',
                      label: 'مصرف‌نشده',
                      icon: Icons.remove_circle_outline_rounded,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      value: '$missed',
                      label: 'فراموش‌شده',
                      icon: Icons.error_outline_rounded,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'برنامه‌های درمان',
                style: AppTextStyles.heading(context).copyWith(fontSize: 18),
              ),
              const SizedBox(height: 12),
              if (plans.isEmpty)
                const _EmptyCard(
                  icon: Icons.medication_liquid_rounded,
                  message: 'هنوز برنامه درمانی ثبت نشده است.',
                )
              else
                ...plans.map((plan) => _TreatmentSummaryCard(plan: plan)),
              const SizedBox(height: 8),
              const _DevelopmentNotice(
                message:
                    'این صفحه فقط داده‌های درمانی موجود در Backend را نشان می‌دهد. آزمایش‌ها، علائم حیاتی و اسناد پزشکی هنوز ذخیره نمی‌شوند.',
              ),
            ],
          );
        },
      ),
    );
  }
}

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    final today = DateTime.now();
    return context.read<LifeMateApiClient>().getDoseOccurrences(
      fromDate: today,
      toDate: today,
    );
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return _WellMateDestinationScaffold(
      title: 'اعلان‌ها',
      subtitle: 'یادآوری‌ها و وضعیت برنامه امروز',
      icon: Icons.notifications_none_rounded,
      accent: AppColors.primaryBlue,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _LoadingCard();
          }
          if (snapshot.hasError) {
            return _ErrorCard(
              message: 'اعلان‌های امروز دریافت نشدند.',
              onRetry: _retry,
            );
          }
          final doses = List<Map<String, dynamic>>.from(
            snapshot.data ?? const <Map<String, dynamic>>[],
          );
          doses.sort((a, b) => _doseTime(a).compareTo(_doseTime(b)));
          if (doses.isEmpty) {
            return const _EmptyCard(
              icon: Icons.notifications_off_outlined,
              message: 'برای امروز یادآوری دارویی وجود ندارد.',
            );
          }
          return Column(
            children: doses
                .map((dose) => _NotificationDoseCard(dose: dose))
                .toList(growable: false),
          );
        },
      ),
    );
  }
}

class ReferralScreen extends StatelessWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _WellMateDestinationScaffold(
      title: 'کد معرف',
      subtitle: 'دعوت دوستان و اعضای خانواده',
      icon: Icons.card_giftcard_rounded,
      accent: Colors.redAccent,
      child: Column(
        children: [
          _SoftCard(
            child: Column(
              children: [
                _ProfileAvatar(icon: Icons.card_giftcard_rounded),
                SizedBox(height: 18),
                Text(
                  'کد معرف شما',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 10),
                Text(
                  'پس از فعال‌شدن سرویس دعوت، کد اختصاصی در این قسمت نمایش داده می‌شود.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.7, color: AppColors.textSecondary),
                ),
                SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: Icon(Icons.share_outlined),
                    label: Text('اشتراک‌گذاری — در دست توسعه'),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          _DevelopmentNotice(
            message:
                'تا زمان آماده‌شدن Backend معرفی و پاداش، هیچ کد ساختگی تولید یا نمایش داده نمی‌شود.',
          ),
        ],
      ),
    );
  }
}

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _WellMateDestinationScaffold(
      title: 'پشتیبانی',
      subtitle: 'راهنما و ارتباط با تیم LifeMate',
      icon: Icons.support_agent_rounded,
      accent: Colors.indigo,
      child: Column(
        children: [
          _SupportTile(
            icon: Icons.help_outline_rounded,
            title: 'چطور یک درمان اضافه کنم؟',
            description:
                'از نوار پایین وارد «افزودن درمان» شوید، نام دارو، مقدار و زمان مصرف را ثبت کنید.',
          ),
          SizedBox(height: 12),
          _SupportTile(
            icon: Icons.family_restroom_rounded,
            title: 'چطور مراقب اضافه کنم؟',
            description:
                'در پروفایل وارد بخش «مراقبان» شوید و دعوت امن را برای فرد موردنظر بسازید.',
          ),
          SizedBox(height: 12),
          _SupportTile(
            icon: Icons.lock_outline_rounded,
            title: 'حریم خصوصی چگونه حفظ می‌شود؟',
            description:
                'دسترسی مراقب فقط با رضایت شما ایجاد می‌شود و هر زمان قابل لغو است.',
          ),
          SizedBox(height: 16),
          _DevelopmentNotice(
            message:
                'کانال تیکت و گفت‌وگوی پشتیبانی هنوز Backend ندارد؛ دکمه تماس تا آماده‌شدن مسیر رسمی غیرفعال است.',
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: null,
              icon: Icon(Icons.chat_bubble_outline_rounded),
              label: Text('ارتباط با پشتیبانی — در دست توسعه'),
            ),
          ),
        ],
      ),
    );
  }
}

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic> _profile = const {};

  bool get _enabled => _profile['enabled'] == true;
  int get _version =>
      _profile['version'] is int ? _profile['version'] as int : 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final profile = await context
          .read<LifeMateApiClient>()
          .getWomenCalendarProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (error) {
      debugPrint('Subscription women calendar load failed.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _activate() async {
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('این قابلیت در Build فعلی فعال نیست.')),
      );
      return;
    }
    final selected = await showAppDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
      title: 'شروع آخرین دوره',
    );
    if (selected == null || !mounted) return;
    await _save(enabled: true, lastPeriodStart: selected);
  }

  Future<void> _deactivate() async {
    final currentStart = DateTime.tryParse(
      _profile['lastPeriodStart']?.toString() ?? '',
    );
    await _save(enabled: false, lastPeriodStart: currentStart);
  }

  Future<void> _save({
    required bool enabled,
    required DateTime? lastPeriodStart,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final profile = await context
          .read<LifeMateApiClient>()
          .updateWomenCalendarProfile(
            version: _version,
            enabled: enabled,
            lastPeriodStart: lastPeriodStart,
            cycleLength: _profile['cycleLength'] is int
                ? _profile['cycleLength'] as int
                : 28,
            periodLength: _profile['periodLength'] is int
                ? _profile['periodLength'] as int
                : 5,
            remindersEnabled: _profile['remindersEnabled'] != false,
          );
      if (!mounted) return;
      setState(() => _profile = profile);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'تقویم بانوان برای نسخه داخلی فعال شد.'
                : 'تقویم بانوان غیرفعال شد.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _WellMateDestinationScaffold(
      title: 'اشتراک LifeMate',
      subtitle: 'امکانات پایه و قابلیت‌های اختیاری',
      icon: Icons.emoji_events_rounded,
      accent: Colors.amber,
      child: Column(
        children: [
          const _SubscriptionPlanCard(
            title: 'نسخه پایه',
            description:
                'ثبت درمان، برنامه روزانه، اعلان محلی و اتصال امن یک مراقب',
            current: true,
            statusLabel: 'فعال',
            buttonLabel: 'نسخه فعلی',
          ),
          const SizedBox(height: 14),
          _SubscriptionPlanCard(
            title: 'تقویم بانوان',
            description:
                'تقویم شمسی، خط زمانی چرخه، ثبت شروع و پایان دوره و اشتراک‌گذاری اختیاری با مراقب',
            current: _enabled,
            statusLabel: _loading
                ? 'در حال بررسی'
                : _enabled
                ? 'فعال'
                : 'غیرفعال',
            buttonLabel: _enabled ? 'غیرفعال‌سازی' : 'فعال‌سازی آزمایشی',
            onPressed: _loading || _saving
                ? null
                : (_enabled ? _deactivate : _activate),
            accent: const Color(0xFFD95B93),
          ),
          const SizedBox(height: 14),
          const _SubscriptionPlanCard(
            title: 'نسخه خانواده',
            description:
                'گزارش‌های پیشرفته، چند مراقب، پرونده سلامت و پشتیبانی ویژه',
            current: false,
            statusLabel: 'در دست توسعه',
            buttonLabel: 'خرید — در دست توسعه',
          ),
          const SizedBox(height: 16),
          const _DevelopmentNotice(
            message:
                'در این نسخه داخلی، فعال‌سازی تقویم بانوان آزمایشی است و هیچ پرداخت یا ارتباطی با درگاه بانکی انجام نمی‌شود.',
          ),
        ],
      ),
    );
  }
}

class _WellMateDestinationScaffold extends StatelessWidget {
  const _WellMateDestinationScaffold({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.accent = AppColors.primary,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'بازگشت',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    color: AppColors.darkBlue,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: AppColors.darkBlue,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accent),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [child],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.55),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 10,
            offset: Offset(-4, -4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.16),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Icon(icon, color: AppColors.primary, size: 38),
    );
  }
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({
    required this.label,
    required this.value,
    required this.icon,
    this.ltr = false,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool ltr;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primaryBlue, size: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      textDirection: ltr ? TextDirection.ltr : null,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.09),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TreatmentSummaryCard extends StatelessWidget {
  const _TreatmentSummaryCard({required this.plan});
  final Map<String, dynamic> plan;

  @override
  Widget build(BuildContext context) {
    final medication = plan['medication'] as Map<String, dynamic>? ?? const {};
    final schedules = plan['schedules'] as List<dynamic>? ?? const [];
    final time = schedules.isEmpty
        ? 'بدون زمان'
        : _shortTime((schedules.first as Map<String, dynamic>)['localTime']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _SoftCard(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.medication_rounded,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _value(medication['name'], fallback: 'دارو'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_value(plan['doseText'])} • $time',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Chip(
              label: Text(plan['status'] == 'active' ? 'فعال' : 'متوقف'),
              backgroundColor: plan['status'] == 'active'
                  ? AppColors.primary.withOpacity(0.12)
                  : Colors.grey.shade100,
              side: BorderSide.none,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationDoseCard extends StatelessWidget {
  const _NotificationDoseCard({required this.dose});
  final Map<String, dynamic> dose;

  @override
  Widget build(BuildContext context) {
    final status = dose['status']?.toString() ?? 'scheduled';
    final style = _statusStyle(status);
    final medicationName = _value(
      dose['medicationName'],
      fallback: 'یادآوری دارو',
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _SoftCard(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: style.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(style.icon, color: style.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medicationName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_doseTime(dose)} • ${_value(dose['doseText'])}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: style.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                style.label,
                style: TextStyle(
                  color: style.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportTile extends StatelessWidget {
  const _SupportTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: AppColors.primaryBlue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  description,
                  style: const TextStyle(
                    height: 1.65,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionPlanCard extends StatelessWidget {
  const _SubscriptionPlanCard({
    required this.title,
    required this.description,
    required this.current,
    required this.statusLabel,
    required this.buttonLabel,
    this.onPressed,
    this.accent = AppColors.primary,
  });

  final String title;
  final String description;
  final bool current;
  final String statusLabel;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  title == 'تقویم بانوان'
                      ? Icons.water_drop_rounded
                      : Icons.workspace_premium_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Chip(
                label: Text(statusLabel),
                side: BorderSide.none,
                backgroundColor: current
                    ? accent.withOpacity(0.12)
                    : Colors.amber.withOpacity(0.15),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(height: 1.7, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onPressed,
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _DevelopmentNotice extends StatelessWidget {
  const _DevelopmentNotice({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.construction_rounded, color: Colors.amber.shade800),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(height: 1.65))),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const _SoftCard(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 44),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.error),
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
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          children: [
            Icon(icon, size: 46, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _StatusStyle {
  const _StatusStyle(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

_StatusStyle _statusStyle(String status) => switch (status) {
  'taken' => const _StatusStyle(
    'مصرف شد',
    Icons.check_circle_rounded,
    Colors.green,
  ),
  'skipped' => const _StatusStyle(
    'مصرف نشد',
    Icons.remove_circle_outline_rounded,
    Colors.orange,
  ),
  'missed' => const _StatusStyle(
    'فراموش شد',
    Icons.error_outline_rounded,
    Colors.redAccent,
  ),
  _ => const _StatusStyle(
    'برنامه‌ریزی‌شده',
    Icons.schedule_rounded,
    AppColors.primaryBlue,
  ),
};

String _value(dynamic value, {String fallback = 'ثبت نشده'}) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String _shortTime(dynamic value) {
  final raw = value?.toString() ?? '';
  return raw.length >= 5 ? raw.substring(0, 5) : _value(raw);
}

String _doseTime(Map<String, dynamic> dose) =>
    _shortTime(dose['scheduledLocalTime']);
