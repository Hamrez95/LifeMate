// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';

class CareMatePersonalInformationScreen extends StatefulWidget {
  const CareMatePersonalInformationScreen({super.key});

  @override
  State<CareMatePersonalInformationScreen> createState() =>
      _CareMatePersonalInformationScreenState();
}

class _CareMatePersonalInformationScreenState
    extends State<CareMatePersonalInformationScreen> {
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
  Widget build(BuildContext context) => _DestinationScaffold(
    title: 'اطلاعات شخصی',
    icon: Icons.person_rounded,
    accent: Colors.blueAccent,
    child: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingCard();
        }
        if (snapshot.hasError) {
          return _ErrorCard(onRetry: _retry);
        }
        final data = snapshot.data ?? const <String, dynamic>{};
        final user = data['user'] as Map<String, dynamic>? ?? const {};
        final profile = data['profile'] as Map<String, dynamic>? ?? const {};
        final displayName = profile['displayName']?.toString().trim();
        return Column(
          children: [
            _InformationCard(
              children: [
                _InformationRow(
                  icon: Icons.badge_outlined,
                  label: 'نام نمایشی',
                  value: displayName == null || displayName.isEmpty
                      ? 'ثبت نشده'
                      : displayName,
                ),
                const Divider(height: 28),
                _InformationRow(
                  icon: Icons.email_outlined,
                  label: 'ایمیل',
                  value: user['email']?.toString() ?? 'ثبت نشده',
                  ltr: true,
                ),
                const Divider(height: 28),
                _InformationRow(
                  icon: Icons.phone_outlined,
                  label: 'شماره تماس',
                  value:
                      profile['phoneNumber']?.toString().trim().isNotEmpty ==
                          true
                      ? profile['phoneNumber'].toString()
                      : 'ثبت نشده',
                  ltr: true,
                ),
                const Divider(height: 28),
                _InformationRow(
                  icon: Icons.language_rounded,
                  label: 'زبان حساب',
                  value: profile['locale']?.toString() ?? 'fa',
                ),
                const Divider(height: 28),
                _InformationRow(
                  icon: Icons.schedule_rounded,
                  label: 'منطقه زمانی',
                  value: profile['timeZone']?.toString() ?? 'Asia/Tehran',
                  ltr: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _DevelopmentNotice(
              title: 'ویرایش امن اطلاعات حساب',
              description:
                  'اطلاعات واقعی حساب از Supabase و LifeMate API خوانده می‌شود. تا اضافه‌شدن قرارداد ویرایش پروفایل، تغییر این اطلاعات غیرفعال است.',
            ),
          ],
        );
      },
    ),
  );
}

class CareMateNotificationsScreen extends StatefulWidget {
  const CareMateNotificationsScreen({super.key});

  @override
  State<CareMateNotificationsScreen> createState() =>
      _CareMateNotificationsScreenState();
}

class _CareMateNotificationsScreenState
    extends State<CareMateNotificationsScreen> {
  late Future<_CareNotificationData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_CareNotificationData> _load() async {
    final api = context.read<LifeMateApiClient>();
    final values = await Future.wait([
      api.getCurrentUser(),
      api.getCareRelationships(),
    ]);
    final me = values[0] as Map<String, dynamic>;
    final relationships = values[1] as List<Map<String, dynamic>>;
    final user = me['user'] as Map<String, dynamic>? ?? const {};
    final userId = user['id']?.toString();
    final active = relationships
        .where(
          (item) =>
              item['status']?.toString() == 'active' &&
              item['caregiverUserId']?.toString() == userId,
        )
        .toList(growable: false);
    final now = DateTime.now();
    final groups = <_PatientNotifications>[];
    for (final relationship in active) {
      final doses = await api.getCareRecipientDoseOccurrences(
        patientUserId: relationship['patientUserId'].toString(),
        fromDate: now,
        toDate: now,
      );
      doses.sort((a, b) => _time(a).compareTo(_time(b)));
      groups.add(
        _PatientNotifications(
          name:
              relationship['patientDisplayName']
                      ?.toString()
                      .trim()
                      .isNotEmpty ==
                  true
              ? relationship['patientDisplayName'].toString()
              : 'فرد تحت مراقبت',
          doses: doses,
        ),
      );
    }
    return _CareNotificationData(groups: groups);
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) => _DestinationScaffold(
    title: 'مرکز اعلان‌ها',
    icon: Icons.notifications_active_rounded,
    accent: AppColors.primaryBlue,
    child: FutureBuilder<_CareNotificationData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingCard();
        }
        if (snapshot.hasError) {
          return _ErrorCard(onRetry: _retry);
        }
        final groups = snapshot.data?.groups ?? const [];
        if (groups.isEmpty) {
          return const _EmptyCard(
            icon: Icons.group_off_rounded,
            title: 'فردی به CareMate متصل نیست',
            description:
                'پس از فعال‌شدن ارتباط مراقبتی، اعلان‌های واقعی دارویی اینجا نمایش داده می‌شوند.',
          );
        }
        final alerts = <({String patient, Map<String, dynamic> dose})>[];
        for (final group in groups) {
          for (final dose in group.doses) {
            final status = dose['status']?.toString();
            if (status == 'missed' || status == 'skipped') {
              alerts.add((patient: group.name, dose: dose));
            }
          }
        }
        if (alerts.isEmpty) {
          return const _EmptyCard(
            icon: Icons.notifications_paused_rounded,
            title: 'هشدار فعالی وجود ندارد',
            description: 'برای امروز دوز فراموش‌شده یا ردشده‌ای ثبت نشده است.',
          );
        }
        return Column(
          children: alerts
              .map(
                (alert) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AlertCard(patient: alert.patient, dose: alert.dose),
                ),
              )
              .toList(growable: false),
        );
      },
    ),
  );

  static String _time(Map<String, dynamic> dose) {
    final raw = dose['scheduledLocalTime']?.toString() ?? '--:--';
    return raw.length >= 5 ? raw.substring(0, 5) : raw;
  }
}

class CareMateReferralScreen extends StatelessWidget {
  const CareMateReferralScreen({super.key});

  @override
  Widget build(BuildContext context) => const _StaticDestinationScreen(
    title: 'کد معرف',
    icon: Icons.card_giftcard_rounded,
    accent: Colors.redAccent,
    heading: 'دعوت دوستان به LifeMate',
    description:
        'این صفحه بخشی از طراحی اصلی محصول است. کد ساختگی نمایش داده نمی‌شود و اشتراک‌گذاری تا ایجاد سرویس معرفی غیرفعال می‌ماند.',
    features: [
      'پاداش شفاف و قابل رهگیری',
      'حفظ حریم خصوصی دعوت‌شونده',
      'اشتراک‌گذاری فقط با رضایت کاربر',
    ],
    actionLabel: 'اشتراک‌گذاری کد معرف',
  );
}

class CareMateSupportScreen extends StatelessWidget {
  const CareMateSupportScreen({super.key});

  @override
  Widget build(BuildContext context) => _DestinationScaffold(
    title: 'پشتیبانی',
    icon: Icons.support_agent_rounded,
    accent: Colors.indigo,
    child: Column(
      children: [
        const _InformationCard(
          children: [
            _HelpItem(
              icon: Icons.person_add_alt_1_rounded,
              title: 'پذیرش دعوت چگونه انجام می‌شود؟',
              description:
                  'در بخش مراقبت خانواده، کد ارسال‌شده توسط بیمار را وارد و رضایت‌نامه را تأیید کنید.',
            ),
            Divider(height: 28),
            _HelpItem(
              icon: Icons.security_rounded,
              title: 'چرا بعضی اطلاعات قابل ویرایش نیست؟',
              description:
                  'CareMate فقط در محدوده رضایت بیمار اطلاعات درمان را نمایش می‌دهد و تغییر درمان از سمت مراقب غیرفعال است.',
            ),
            Divider(height: 28),
            _HelpItem(
              icon: Icons.sync_problem_rounded,
              title: 'اطلاعات تازه نمی‌شود',
              description:
                  'اتصال اینترنت را بررسی و صفحه را به پایین بکشید. در صورت انقضای نشست دوباره وارد شوید.',
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _DevelopmentNotice(
          title: 'ارسال تیکت پشتیبانی',
          description:
              'راهنمای کاربردی در دسترس است، اما ارسال تیکت تا اتصال سرویس پشتیبانی غیرفعال باقی می‌ماند.',
        ),
      ],
    ),
  );
}

class CareMateSubscriptionScreen extends StatelessWidget {
  const CareMateSubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) => _DestinationScaffold(
    title: 'اشتراک CareMate',
    icon: Icons.workspace_premium_rounded,
    accent: Colors.amber,
    child: Column(
      children: [
        const _PlanCard(
          title: 'مراقبت پایه',
          description: 'اتصال امن به یک عضو خانواده و مشاهده برنامه درمان',
          current: true,
        ),
        const SizedBox(height: 14),
        const _PlanCard(
          title: 'مراقبت خانواده',
          description: 'اعضای بیشتر، گزارش‌های هفتگی و هماهنگی تیم مراقبت',
          current: false,
        ),
        const SizedBox(height: 16),
        const _DevelopmentNotice(
          title: 'پرداخت هنوز فعال نیست',
          description:
              'هیچ خرید یا پرداختی در این نسخه انجام نمی‌شود. فعال‌سازی پس از قرارداد پرداخت، قیمت‌گذاری و بازبینی حقوقی خواهد بود.',
        ),
      ],
    ),
  );
}

class _DestinationScaffold extends StatelessWidget {
  const _DestinationScaffold({
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 20, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'بازگشت',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  color: AppColors.primaryBlue,
                ),
                const SizedBox(width: 4),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: child,
            ),
          ),
        ],
      ),
    ),
  );
}

class _StaticDestinationScreen extends StatelessWidget {
  const _StaticDestinationScreen({
    required this.title,
    required this.icon,
    required this.accent,
    required this.heading,
    required this.description,
    required this.features,
    required this.actionLabel,
  });
  final String title;
  final IconData icon;
  final Color accent;
  final String heading;
  final String description;
  final List<String> features;
  final String actionLabel;

  @override
  Widget build(BuildContext context) => _DestinationScaffold(
    title: title,
    icon: icon,
    accent: accent,
    child: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: AppColors.softDecoration(),
          child: Column(
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 40),
              ),
              const SizedBox(height: 18),
              Text(
                heading,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  height: 1.7,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 18),
              ...features.map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded, size: 20, color: accent),
                      const SizedBox(width: 10),
                      Expanded(child: Text(feature)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.lock_outline_rounded),
                  label: Text('$actionLabel — در دست توسعه'),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InformationCard extends StatelessWidget {
  const _InformationCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: AppColors.softDecoration(),
    child: Column(children: children),
  );
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({
    required this.icon,
    required this.label,
    required this.value,
    this.ltr = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF4FF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: AppColors.primaryBlue, size: 21),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              textDirection: ltr ? TextDirection.ltr : null,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _DevelopmentNotice extends StatelessWidget {
  const _DevelopmentNotice({required this.title, required this.description});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.amber.shade50,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.amber.shade100),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.construction_rounded, color: Colors.amber.shade800),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(description, style: const TextStyle(height: 1.65)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.lock_outline_rounded),
            label: const Text('در دست توسعه'),
          ),
        ),
      ],
    ),
  );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.patient, required this.dose});
  final String patient;
  final Map<String, dynamic> dose;

  @override
  Widget build(BuildContext context) {
    final status = dose['status']?.toString();
    final skipped = status == 'skipped';
    final raw = dose['scheduledLocalTime']?.toString() ?? '--:--';
    final time = raw.length >= 5 ? raw.substring(0, 5) : raw;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: skipped ? const Color(0xFFFFF6E8) : const Color(0xFFFFEEF0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: skipped ? Colors.orange.shade100 : Colors.red.shade100,
        ),
      ),
      child: Row(
        children: [
          Icon(
            skipped ? Icons.block_rounded : Icons.warning_amber_rounded,
            color: skipped ? Colors.orange : Colors.redAccent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dose['medicationName']?.toString() ?? 'دارو',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '$patient • ${skipped ? 'ردشده' : 'فراموش‌شده'}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            time,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _HelpItem extends StatelessWidget {
  const _HelpItem({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF4FF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: AppColors.primaryBlue),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(
              description,
              style: const TextStyle(
                height: 1.6,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.description,
    required this.current,
  });
  final String title;
  final String description;
  final bool current;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: current ? AppColors.primaryBlue : Colors.transparent,
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.primaryBlue.withOpacity(0.08),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryText,
                ),
              ),
            ),
            if (current)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'فعلی',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: const TextStyle(height: 1.6, color: AppColors.secondaryText),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: null,
            child: Text(current ? 'اشتراک فعلی' : 'در دست توسعه'),
          ),
        ),
      ],
    ),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 70),
    decoration: AppColors.softDecoration(),
    child: const Center(child: CircularProgressIndicator()),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => _EmptyCard(
    icon: Icons.cloud_off_rounded,
    title: 'اطلاعات دریافت نشد',
    description: 'اتصال اینترنت را بررسی و دوباره تلاش کنید.',
    action: OutlinedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('تلاش دوباره'),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: AppColors.softDecoration(),
    child: Column(
      children: [
        Icon(icon, color: AppColors.primaryBlue, size: 54),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.6, color: AppColors.secondaryText),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class _CareNotificationData {
  const _CareNotificationData({required this.groups});
  final List<_PatientNotifications> groups;
}

class _PatientNotifications {
  const _PatientNotifications({required this.name, required this.doses});
  final String name;
  final List<Map<String, dynamic>> doses;
}

class CareMateComingFeatureScreen extends StatelessWidget {
  const CareMateComingFeatureScreen({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    super.key,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => _DestinationScaffold(
    title: title,
    icon: icon,
    accent: accent,
    child: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(26),
          decoration: AppColors.softDecoration(),
          child: Column(
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 42),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  height: 1.7,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.amber.shade100),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Colors.amber),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'این صفحه و مسیر مطابق طراحی اصلی حفظ شده است؛ تا ایجاد Backend معتبر هیچ داده ساختگی ثبت یا نمایش داده نمی‌شود.',
                        style: TextStyle(height: 1.55),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.lock_outline_rounded),
                  label: const Text('در دست توسعه'),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
