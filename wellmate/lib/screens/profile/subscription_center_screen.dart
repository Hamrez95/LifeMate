import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';

/// The subscription centre renders the server snapshot only.  It deliberately
/// has no local product catalogue, price, promotion, trial or quota constants.
class LifeMateSubscriptionCenterScreen extends StatefulWidget {
  const LifeMateSubscriptionCenterScreen({super.key, this.focusPeriod = false});

  final bool focusPeriod;

  @override
  State<LifeMateSubscriptionCenterScreen> createState() =>
      _LifeMateSubscriptionCenterScreenState();
}

class _LifeMateSubscriptionCenterScreenState
    extends State<LifeMateSubscriptionCenterScreen> {
  late Future<Map<String, dynamic>> _snapshot;
  bool _busy = false;

  LifeMateSubscriptionTheme get _theme => const LifeMateSubscriptionTheme(
        accent: AppColors.primary,
        softSurface: Color(0xffeef8f1),
      );

  @override
  void initState() {
    super.initState();
    _snapshot = context.read<LifeMateApiClient>().getSubscriptionSnapshot();
  }

  void _reload() {
    setState(
      () => _snapshot = context.read<LifeMateApiClient>().getSubscriptionSnapshot(),
    );
  }

  Future<void> _startTrial() async {
    await _run(() async {
      await context.read<LifeMateApiClient>().startPeriodTrial(
            idempotencyKey: LifeMateApiClient.createClientRequestId(),
          );
      _reload();
    });
  }

  Future<void> _claimGift() async {
    final controller = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('دریافت هدیه'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'کد هدیه',
              hintText: 'کد دریافت‌شده را وارد کنید',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('دریافت'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (token == null || token.trim().isEmpty) return;
    await _run(() async {
      await context.read<LifeMateApiClient>().claimSubscriptionGift(
            claimToken: token,
            idempotencyKey: LifeMateApiClient.createClientRequestId(),
          );
      _reload();
    });
  }

  Future<void> _convertPeriod() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تبدیل به CocoonMate'),
          content: const Text(
            'ارزش باقی‌ماندهٔ اشتراک شما به‌صورت خودکار منتقل می‌شود. '
            'پس از تبدیل، بازگشت به Period نیازمند اشتراک جدید است. '
            'تاریخچهٔ تقویم شما حفظ می‌شود.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('تبدیل'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    await _run(() async {
      await context.read<LifeMateApiClient>().convertPeriodToCocoon(
            idempotencyKey: LifeMateApiClient.createClientRequestId(),
          );
      _reload();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('وضعیت اشتراک به‌روزرسانی شد.'),
        ),
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(error.message),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.darkBlue,
          elevation: 0,
          title: const Text(
            'اشتراک‌ها',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            IconButton(
              tooltip: 'تازه‌سازی',
              onPressed: _busy ? null : _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _snapshot,
          builder: (context, state) {
            if (state.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.hasError) {
              return _Failure(onRetry: _reload);
            }
            return _SubscriptionBody(
              snapshot: state.data ?? const <String, dynamic>{},
              theme: _theme,
              busy: _busy,
              onStartTrial: _startTrial,
              onClaimGift: _claimGift,
              onConvertPeriod: _convertPeriod,
              onRefresh: () async { _reload(); },
            );
          },
        ),
      ),
    );
  }
}

class _SubscriptionBody extends StatelessWidget {
  const _SubscriptionBody({
    required this.snapshot,
    required this.theme,
    required this.busy,
    required this.onStartTrial,
    required this.onClaimGift,
    required this.onConvertPeriod,
    required this.onRefresh,
  });

  final Map<String, dynamic> snapshot;
  final LifeMateSubscriptionTheme theme;
  final bool busy;
  final VoidCallback onStartTrial;
  final VoidCallback onClaimGift;
  final VoidCallback onConvertPeriod;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final trials = _objects(snapshot['trials']);
    final entitlements = _objects(snapshot['entitlements']);
    final policies = _objects(snapshot['policies']);
    final offers = _objects(snapshot['offers']);
    final period = _firstByCode(trials, 'period') ?? _firstByCode(entitlements, 'period');
    final periodDays = _asInt(period?['remainingDays']);
    final periodTrialAvailable = period?['trialAvailable'] == true;
    final canConvert = period?['canConvert'] == true ||
        snapshot['periodConversionAvailable'] == true;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _HeroCard(theme: theme),
          const SizedBox(height: 16),
          if (periodDays != null && periodDays > 0) ...[
            LifeMateTrialStatus(
              remainingDays: periodDays,
              theme: theme,
              onTap: () {},
            ),
            const SizedBox(height: 12),
          ],
          if (periodTrialAvailable)
            _ActionCard(
              icon: Icons.hourglass_bottom_rounded,
              title: 'دورهٔ آزمایشی تقویم',
              message: 'مدت دوره از سرور تعیین می‌شود و با نصب دوباره بازنشانی نمی‌شود.',
              accent: const Color(0xffd95b93),
              cta: 'شروع دورهٔ آزمایشی',
              onPressed: busy ? null : onStartTrial,
            ),
          if (canConvert) ...[
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.auto_awesome_rounded,
              title: 'تبدیل به CocoonMate',
              message: 'ارزش واقعیِ باقی‌مانده منتقل می‌شود؛ اطلاعات سلامت و تاریخچه محفوظ می‌ماند.',
              accent: const Color(0xff6c63ff),
              cta: 'بررسی و تبدیل',
              onPressed: busy ? null : onConvertPeriod,
            ),
          ],
          if (offers.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionTitle('پیشنهادهای فعال'),
            const SizedBox(height: 10),
            ...offers.map(
              (offer) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LifeMateOfferCard(
                  title: _text(offer['title'] ?? offer['name'], fallback: 'اشتراک ویژه'),
                  priceLabel: _text(offer['priceLabel'], fallback: 'قیمت در حال دریافت'),
                  compareAtPriceLabel: _nullableText(offer['compareAtPriceLabel']),
                  badge: _nullableText(offer['promotionLabel']),
                  theme: theme,
                  selected: offer['activeForCurrentUser'] == true,
                  onSelect: () => _showOfferNotice(context),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          const _SectionTitle('وضعیت دسترسی'),
          const SizedBox(height: 10),
          if (entitlements.isEmpty)
            const _EmptyState('دسترسی ویژهٔ فعالی ندارید.')
          else
            ...entitlements.map((item) => _EntitlementTile(item: item, theme: theme)),
          const SizedBox(height: 16),
          const _SectionTitle('سقف نسخهٔ رایگان'),
          const SizedBox(height: 10),
          if (policies.isEmpty)
            const _EmptyState('سقف‌های حساب از سرور دریافت نشد.')
          else
            ...policies.map((policy) => _PolicyTile(policy: policy, theme: theme)),
          const SizedBox(height: 18),
          _ActionCard(
            icon: Icons.card_giftcard_rounded,
            title: 'دریافت اشتراک هدیه',
            message: 'هدیه فقط اشتراک را فعال می‌کند و هیچ دسترسی یا اطلاعات سلامتی را تغییر نمی‌دهد.',
            accent: const Color(0xffe66d52),
            cta: 'وارد کردن کد هدیه',
            onPressed: busy ? null : onClaimGift,
          ),
          const SizedBox(height: 18),
          const Text(
            'قیمت، تخفیف، سقف‌ها و مدت آزمایشی از حساب شما در سرور دریافت می‌شوند.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.7),
          ),
        ],
      ),
    );
  }

  void _showOfferNotice(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('روش‌های پرداخت فعال هنگام تکمیل خرید نمایش داده می‌شوند.'),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.theme});
  final LifeMateSubscriptionTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.accent, const Color(0xff2f8158)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(26),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 32),
            SizedBox(height: 14),
            Text(
              'اشتراک متناسب با نیاز شما',
              style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 6),
            Text(
              'دسترسی‌ها و پیشنهادها را امن و شفاف مدیریت کنید.',
              style: TextStyle(color: Color(0xffe8fff0), height: 1.6),
            ),
          ],
        ),
      );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.accent,
    required this.cta,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color accent;
  final String cta;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withOpacity(.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(message, style: const TextStyle(color: AppColors.textSecondary, height: 1.6)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: onPressed,
                child: Text(cta),
              ),
            ),
          ],
        ),
      );
}

class _EntitlementTile extends StatelessWidget {
  const _EntitlementTile({required this.item, required this.theme});
  final Map<String, dynamic> item;
  final LifeMateSubscriptionTheme theme;

  @override
  Widget build(BuildContext context) {
    final active = item['active'] == true || item['status'] == 'active';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(active ? Icons.verified_rounded : Icons.lock_outline_rounded,
          color: active ? theme.accent : AppColors.textSecondary),
      title: Text(_text(item['label'] ?? item['productName'], fallback: 'اشتراک')),
      subtitle: Text(_text(item['expiresAtLabel'] ?? item['statusLabel'],
          fallback: active ? 'فعال' : 'غیرفعال')),
    );
  }
}

class _PolicyTile extends StatelessWidget {
  const _PolicyTile({required this.policy, required this.theme});
  final Map<String, dynamic> policy;
  final LifeMateSubscriptionTheme theme;

  @override
  Widget build(BuildContext context) => LifeMateLockedFeatureIndicator(
        label: _text(policy['label'] ?? policy['title'], fallback: 'سقف استفاده'),
        theme: theme,
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.value);
  final String value;
  @override
  Widget build(BuildContext context) =>
      Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(value, style: const TextStyle(color: AppColors.textSecondary)),
      );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text('وضعیت اشتراک دریافت نشد.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('تلاش دوباره')),
          ]),
        ),
      );
}

List<Map<String, dynamic>> _objects(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList(growable: false);
}

Map<String, dynamic>? _firstByCode(List<Map<String, dynamic>> values, String code) {
  for (final value in values) {
    if (value['productCode'] == code || value['familyCode'] == code) return value;
  }
  return null;
}

int? _asInt(dynamic value) => value is int ? value : int.tryParse(value?.toString() ?? '');
String _text(dynamic value, {required String fallback}) {
  final result = value?.toString().trim();
  return result == null || result.isEmpty ? fallback : result;
}
String? _nullableText(dynamic value) {
  final result = value?.toString().trim();
  return result == null || result.isEmpty ? null : result;
}
