import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';
import 'package:provider/provider.dart';

import '../../providers/contextual_notification_provider.dart';
import '../treatments/add_treatment_screen.dart';
import 'wellmate_first_value_api.dart';

class WellMateFirstValueGate extends StatefulWidget {
  const WellMateFirstValueGate({
    super.key,
    required this.child,
    this.api,
  });

  final Widget child;
  final WellMateFirstValueApi? api;

  @override
  State<WellMateFirstValueGate> createState() => _WellMateFirstValueGateState();
}

class _WellMateFirstValueGateState extends State<WellMateFirstValueGate> {
  late WellMateFirstValueApi _api;
  late bool _ownsApi;
  WellMateFirstValueProfile? _profile;
  Object? _loadError;
  String? _actionError;
  bool _loading = true;
  bool _busy = false;
  bool _permissionStep = false;
  WellMateNotificationPermissionResult? _permissionResult;

  LifeMateOnboardingTheme get _theme => LifeMateOnboardingTheme.wellMate;
  bool get _isPersian => LifeMateRuntimeLocale.isPersian;

  @override
  void initState() {
    super.initState();
    _ownsApi = widget.api == null;
    _api = widget.api ?? WellMateFirstValueApi.fromEnvironment();
    _load();
  }

  @override
  void dispose() {
    if (_ownsApi) _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _actionError = null;
    });
    try {
      var profile = await _api.getProfile();
      if (!profile.isResolved) {
        final plans = await context.read<LifeMateApiClient>().getTreatmentPlans();
        if (plans.isNotEmpty) {
          profile = await _api.setState(current: profile, state: 'Completed');
          if (!mounted) return;
          setState(() {
            _profile = profile;
            _loading = false;
            _permissionStep = true;
          });
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
      await context
          .read<NotificationProvider>()
          .letContextual()
          ?.refreshExistingPermission();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _skip() async {
    final profile = _profile;
    if (profile == null || _busy) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final updated = await _api.setState(current: profile, state: 'Skipped');
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _busy = false;
      });
    } on LifeMateApiException catch (error) {
      if (error.statusCode == 409) {
        await _load();
        return;
      }
      _failAction();
    } catch (_) {
      _failAction();
    }
  }

  void _failAction() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _actionError = LifeMateRuntimeLocale.select(
        fa: 'ذخیره انجام نشد. اتصال را بررسی و دوباره تلاش کن.',
        en: 'Could not save. Check your connection and try again.',
      );
    });
  }

  Future<void> _addTreatment() async {
    var created = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          backgroundColor: _theme.background,
          appBar: AppBar(
            backgroundColor: _theme.background,
            elevation: 0,
            title: Text(
              LifeMateRuntimeLocale.select(
                fa: 'اولین برنامه دارویی',
                en: 'First medication plan',
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: TabbedAddTreatmentScreen(
              onCreated: () {
                created = true;
                Navigator.of(routeContext).pop();
              },
            ),
          ),
        ),
      ),
    );
    if (!mounted || !created) return;

    final latest = await _api.getProfile();
    final updated = await _api.setState(current: latest, state: 'Completed');
    if (!mounted) return;
    setState(() {
      _profile = updated;
      _permissionStep = true;
      _permissionResult = null;
      _actionError = null;
    });
  }

  Future<void> _requestNotifications() async {
    final contextual = context.read<NotificationProvider>().letContextual();
    if (contextual == null || _busy) return;
    setState(() => _busy = true);
    final result = await contextual.requestAfterExplanation();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _permissionResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (_loading) return _loadingScreen();
    if (_loadError != null || profile == null) return _errorScreen();
    if (_permissionStep) return _permissionScreen();
    if (profile.isResolved) return widget.child;
    return _introScreen();
  }

  Widget _loadingScreen() => _scaffold(
        title: LifeMateRuntimeLocale.select(fa: 'WellMate', en: 'WellMate'),
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'در حال آماده‌سازی', en: 'Preparing'),
        primaryBusy: true,
        body: _question(
          icon: Icons.favorite_outline_rounded,
          title: LifeMateRuntimeLocale.select(
            fa: 'تجربه شخصی تو را آماده می‌کنیم',
            en: 'Preparing your personal experience',
          ),
          description: LifeMateRuntimeLocale.select(
            fa: 'چند لحظه صبر کن.',
            en: 'This only takes a moment.',
          ),
        ),
      );

  Widget _errorScreen() => _scaffold(
        title: 'WellMate',
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'تلاش دوباره', en: 'Try again'),
        onPrimary: _load,
        body: _question(
          icon: Icons.cloud_off_outlined,
          title: LifeMateRuntimeLocale.select(
            fa: 'شروع WellMate فعلاً در دسترس نیست',
            en: 'WellMate setup is temporarily unavailable',
          ),
          description: LifeMateRuntimeLocale.select(
            fa: 'اتصال را بررسی کن. هیچ درمان یا یادآوری جدیدی ساخته نشده است.',
            en: 'Check your connection. No treatment or reminder was created.',
          ),
        ),
      );

  Widget _introScreen() => _scaffold(
        title: LifeMateRuntimeLocale.select(fa: 'شروع WellMate', en: 'Start WellMate'),
        progress: 0.5,
        progressLabel: LifeMateRuntimeLocale.select(fa: 'اختیاری', en: 'Optional'),
        primaryLabel: LifeMateRuntimeLocale.select(
          fa: 'اولین دارو را اضافه کن',
          en: 'Add my first medication',
        ),
        onPrimary: _busy ? null : _addTreatment,
        secondaryLabel: LifeMateRuntimeLocale.select(fa: 'فعلاً رد شو', en: 'Skip for now'),
        onSecondary: _busy ? null : _skip,
        primaryBusy: _busy,
        body: Column(
          children: [
            const Spacer(),
            _question(
              icon: Icons.medication_outlined,
              title: LifeMateRuntimeLocale.select(
                fa: 'یک برنامه واقعی بسازیم؟',
                en: 'Create a real medication plan?',
              ),
              description: LifeMateRuntimeLocale.select(
                fa: 'همان فرم اصلی WellMate باز می‌شود؛ زمان و تکرار مستقیماً در موتور درمان و یادآوری ذخیره می‌شوند.',
                en: 'We open the real WellMate form. Time and recurrence go directly to the treatment and reminder engine.',
              ),
            ),
            const SizedBox(height: 22),
            _valueCard(
              Icons.schedule_rounded,
              LifeMateRuntimeLocale.select(
                fa: 'هر چند ساعت، هر چند روز یا برنامه هفتگی',
                en: 'Hourly, daily or weekly recurrence',
              ),
            ),
            const SizedBox(height: 10),
            _valueCard(
              Icons.home_outlined,
              LifeMateRuntimeLocale.select(
                fa: 'بلافاصله در Home و برنامه‌های آینده',
                en: 'Immediately reflected on Home and future schedules',
              ),
            ),
            if (_actionError != null) ...[
              const SizedBox(height: 12),
              Text(_actionError!, style: TextStyle(color: _theme.error)),
            ],
            const Spacer(flex: 2),
          ],
        ),
      );

  Widget _permissionScreen() {
    final denied = _permissionResult == WellMateNotificationPermissionResult.denied;
    final granted = _permissionResult == WellMateNotificationPermissionResult.granted;
    return _scaffold(
      title: LifeMateRuntimeLocale.select(fa: 'یادآوری WellMate', en: 'WellMate reminders'),
      progress: 1,
      progressLabel: LifeMateRuntimeLocale.select(fa: 'آماده', en: 'Ready'),
      primaryLabel: denied || granted
          ? LifeMateRuntimeLocale.select(fa: 'ورود به WellMate', en: 'Enter WellMate')
          : LifeMateRuntimeLocale.select(fa: 'فعال‌کردن اعلان‌ها', en: 'Enable notifications'),
      onPrimary: _busy
          ? null
          : denied || granted
          ? () => setState(() => _permissionStep = false)
          : _requestNotifications,
      secondaryLabel: denied || granted
          ? null
          : LifeMateRuntimeLocale.select(fa: 'فعلاً نه', en: 'Not now'),
      onSecondary: denied || granted
          ? null
          : () => setState(() => _permissionStep = false),
      primaryBusy: _busy,
      body: Column(
        children: [
          const Spacer(),
          _question(
            icon: denied
                ? Icons.notifications_off_outlined
                : granted
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_rounded,
            title: denied
                ? LifeMateRuntimeLocale.select(
                    fa: 'اعلان‌ها فعال نشدند',
                    en: 'Notifications are still off',
                  )
                : granted
                ? LifeMateRuntimeLocale.select(
                    fa: 'یادآوری‌ها آماده‌اند',
                    en: 'Reminders are ready',
                  )
                : LifeMateRuntimeLocale.select(
                    fa: 'زمان دارو را به تو یادآوری کنیم؟',
                    en: 'Remind you when it is medication time?',
                  ),
            description: denied
                ? LifeMateRuntimeLocale.select(
                    fa: 'برنامه درمان ذخیره شده است. هر زمان خواستی می‌توانی اعلان WellMate را از تنظیمات سیستم فعال کنی.',
                    en: 'Your treatment is saved. You can enable WellMate notifications later from system settings.',
                  )
                : LifeMateRuntimeLocale.select(
                    fa: 'اجازه سیستم فقط برای اعلان روی همین دستگاه است و تنظیمات سرور یا دسترسی مراقب را تغییر نمی‌دهد.',
                    en: 'The OS permission only controls notifications on this device. It does not change server preferences or caregiver access.',
                  ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _question({
    required IconData icon,
    required String title,
    required String description,
  }) => LifeMateOnboardingQuestion(
        theme: _theme,
        icon: icon,
        title: title,
        description: description,
        alignCenter: true,
      );

  Widget _valueCard(IconData icon, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _theme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _theme.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: _theme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: _theme.ink,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _scaffold({
    required String title,
    required String primaryLabel,
    required Widget body,
    VoidCallback? onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    bool primaryBusy = false,
    double? progress,
    String? progressLabel,
  }) => Directionality(
        textDirection: _isPersian ? TextDirection.rtl : TextDirection.ltr,
        child: LifeMateOnboardingScaffold(
          theme: _theme,
          title: title,
          primaryLabel: primaryLabel,
          onPrimary: onPrimary,
          secondaryLabel: secondaryLabel,
          onSecondary: onSecondary,
          primaryBusy: primaryBusy,
          progress: progress,
          progressLabel: progressLabel,
          body: body,
        ),
      );
}

extension on NotificationProvider {
  ContextualNotificationProvider? letContextual() =>
      this is ContextualNotificationProvider
      ? this as ContextualNotificationProvider
      : null;
}
