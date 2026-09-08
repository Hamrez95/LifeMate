part of '../cocoonmate_module.dart';

class CocoonShell extends StatefulWidget {
  const CocoonShell({required this.config, super.key});
  final CocoonModuleConfig config;

  @override
  State<CocoonShell> createState() => _CocoonShellState();
}

class _CocoonShellState extends State<CocoonShell> {
  late int _index = widget.config.initialTab.clamp(0, 4);

  bool get _fa => widget.config.host.locale.languageCode == 'fa';
  String t(String en, String fa) => _fa ? fa : en;

  @override
  Widget build(BuildContext context) {
    final host = widget.config.host;
    return Directionality(
      textDirection: _fa ? TextDirection.rtl : TextDirection.ltr,
      child: switch (host.entryState) {
        CocoonEntryState.loading => _loading(),
        CocoonEntryState.unauthenticated => _gate(
            Icons.lock_outline,
            t('Private by design', 'حریم تو، از همان ابتدا'),
            t('Sign in to continue', 'برای ادامه وارد شوید'),
            t(
              'Your pregnancy information stays connected to your protected LifeMate account.',
              'اطلاعات بارداری‌ات به حساب محافظت‌شدهٔ LifeMate متصل می‌ماند.',
            ),
            t('Sign in', 'ورود'),
            host.openLogin,
          ),
        CocoonEntryState.runtimeUnavailable => _gate(
            Icons.cloud_off_outlined,
            t('A short pause', 'یک مکث کوتاه'),
            t(
              'CocoonMate is temporarily unavailable',
              'کوکون‌میت موقتاً در دسترس نیست',
            ),
            t(
              'We could not verify the latest protected information. Nothing has been changed.',
              'نتوانستیم تازه‌ترین اطلاعات محافظت‌شده را تأیید کنیم؛ چیزی تغییر نکرده است.',
            ),
            t('Retry', 'تلاش دوباره'),
            host.refresh,
          ),
        CocoonEntryState.notEnrolled => _gate(
            Icons.favorite_border,
            t('Welcome to CocoonMate', 'به کوکون‌میت خوش آمدی'),
            t('CocoonMate is ready for you', 'کوکون‌میت آماده است'),
            t(
              'A calm place for pregnancy moments, care steps and your shared LifeMate records.',
              'فضایی آرام برای لحظه‌های بارداری، قدم‌های مراقبتی و سوابق مشترک LifeMate.',
            ),
            t('Continue', 'ادامه'),
            () => _beginPregnancySetup(host),
          ),
        CocoonEntryState.notEntitled => _gate(
            Icons.workspace_premium_outlined,
            t('Access', 'دسترسی'),
            t('Choose access to CocoonMate', 'دسترسی کوکون‌میت را انتخاب کنید'),
            t(
              'Your health information is separate from subscription. Review the available options before continuing.',
              'اطلاعات سلامت از اشتراک جداست؛ پیش از ادامه گزینه‌های موجود را ببین.',
            ),
            t('View options', 'مشاهده گزینه‌ها'),
            host.openCommerce,
          ),
        CocoonEntryState.noPregnancy => _gate(
            Icons.spa_outlined,
            t('Begin gently', 'آرام شروع کنیم'),
            t('No active pregnancy yet', 'هنوز بارداری فعالی ثبت نشده'),
            t(
              'Answer only the essentials. You can review the dating source before anything is activated.',
              'فقط اطلاعات ضروری را وارد می‌کنی و پیش از فعال‌سازی، منبع تاریخ‌گذاری را می‌بینی.',
            ),
            t('Start setup', 'شروع ثبت'),
            () => _beginPregnancySetup(host),
            secondary: t(
              'This does not share anything with a partner or caregiver.',
              'این کار چیزی را با همسر یا مراقب به اشتراک نمی‌گذارد.',
            ),
          ),
        CocoonEntryState.offline => _gate(
            Icons.wifi_off_outlined,
            t('No saved pregnancy yet', 'هنوز اطلاعات ذخیره‌شده‌ای نداریم'),
            t('You are offline', 'آفلاین هستید'),
            t(
              'Connect once so we can verify your account and prepare protected offline access.',
              'یک‌بار متصل شو تا حساب تأیید و دسترسی آفلاین محافظت‌شده آماده شود.',
            ),
            t('Retry', 'تلاش دوباره'),
            host.refresh,
          ),
        CocoonEntryState.activePregnancy => _productShell(host),
        CocoonEntryState.offlineOwnerPregnancy => _productShell(
            host,
            offline: true,
          ),
      },
    );
  }

  Widget _gate(
    IconData icon,
    String eyebrow,
    String title,
    String body,
    String action,
    Future<void> Function() onPressed, {
    String? secondary,
  }) {
    return CocoonStatePage(
      icon: icon,
      eyebrow: eyebrow,
      title: title,
      body: body,
      action: action,
      onPressed: () => onPressed(),
      secondary: secondary,
    );
  }

  Widget _loading() => Scaffold(
        body: SafeArea(
          child: Center(
            child: Semantics(
              liveRegion: true,
              label: t('Loading CocoonMate', 'در حال آماده‌سازی کوکون‌میت'),
              child: const SizedBox.square(
                dimension: 72,
                child: CircularProgressIndicator(
                  strokeWidth: 5,
                  color: CocoonTheme.coral,
                  backgroundColor: CocoonTheme.coralSoft,
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> _beginPregnancySetup(CocoonHostContract host) async {
    final pickDate = widget.config.pickPregnancyDate;
    final activate = widget.config.activatePregnancy;
    if (pickDate == null || activate == null) {
      await host.beginPregnancySetup();
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Directionality(
          textDirection: _fa ? TextDirection.rtl : TextDirection.ltr,
          child: CocoonPregnancyOnboardingScreen(
            fa: _fa,
            timezone: widget.config.timezone,
            onPickDate: pickDate,
            onActivate: activate,
          ),
        ),
      ),
    );
    await host.refresh();
  }

  Widget _productShell(CocoonHostContract host, {bool offline = false}) {
    final labels = [
      t('Home', 'خانه'),
      t('Calendar', 'تقویم'),
      t('Add', 'افزودن'),
      t('Records', 'سوابق'),
      t('Learn', 'آموزش'),
    ];
    final icons = const [
      Icons.home_outlined,
      Icons.calendar_month_outlined,
      Icons.add_rounded,
      Icons.folder_outlined,
      Icons.auto_stories_outlined,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? 'CocoonMate' : labels[_index]),
        actions: [
          IconButton(
            tooltip: t('Profile', 'پروفایل'),
            onPressed: host.openGlobalProfile,
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (offline)
              CocoonOfflineStrip(
                message: t(
                  'Last protected information saved on this device',
                  'آخرین اطلاعات محافظت‌شدهٔ ذخیره‌شده روی این دستگاه',
                ),
                retryLabel: t('Retry', 'تلاش دوباره'),
                onRetry: host.refresh,
              ),
            Expanded(child: _tabBody(host, labels, offline: offline)),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() => _index = value);
          host.recordSafeEvent('cocoon_navigation_changed');
        },
        destinations: List.generate(
          labels.length,
          (i) => NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
        ),
      ),
    );
  }

  Widget _tabBody(
    CocoonHostContract host,
    List<String> labels, {
    required bool offline,
  }) =>
      switch (_index) {
        0 => CocoonPregnancyHome(
            host: host,
            fa: _fa,
            onOpenWeek: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Directionality(
                  textDirection: _fa ? TextDirection.rtl : TextDirection.ltr,
                  child: CocoonWeekDetail(host: host, fa: _fa),
                ),
              ),
            ),
          ),
        1 => CocoonPregnancyCalendar(host: host, fa: _fa),
        2 => CocoonQuickAddScreen(
            fa: _fa,
            enabled: {
              ...widget.config.quickAddEnabled,
              if (widget.config.onSubmitCheckIn != null)
                CocoonQuickAddKind.checkIn,
              if (widget.config.onSubmitSymptom != null &&
                  widget.config.symptomOptions.isNotEmpty)
                CocoonQuickAddKind.symptom,
            },
            onOpen: _openQuickAdd,
          ),
        3 => CocoonRecordsScreen(
            fa: _fa,
            state: widget.config.recordsState,
            items: widget.config.records,
            onOpen: widget.config.onOpenRecord,
            onRetry: widget.config.onRetryRecords ?? host.refresh,
            onAdd:
                widget.config.onAddRecord ?? () => setState(() => _index = 2),
          ),
        4 => CocoonPregnancyEducation(host: host, fa: _fa, offline: offline),
        _ => _DestinationState(
            icon: switch (_index) {
              2 => Icons.add_rounded,
              3 => Icons.folder_outlined,
              _ => Icons.people_outline_rounded,
            },
            title: labels[_index],
            body: switch (_index) {
              2 => t(
                  'Log a check-in without leaving your current context.',
                  'بدون خارج‌شدن از مسیر فعلی، یک ثبت سریع انجام بده.',
                ),
              3 => t(
                  'Shared LifeMate records remain connected to the same Person.',
                  'سوابق مشترک LifeMate به همان پروندهٔ شخص متصل می‌مانند.',
                ),
              _ => '',
            },
          ),
      };

  void _openQuickAdd(CocoonQuickAddKind kind) {
    final submitCheckIn = widget.config.onSubmitCheckIn;
    if (kind == CocoonQuickAddKind.checkIn && submitCheckIn != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(t('Today’s check-in', 'حال امروز'))),
            body: CocoonQuickCheckInScreen(
              fa: _fa,
              syncState: widget.config.checkInSyncState,
              onSubmit: submitCheckIn,
            ),
          ),
        ),
      );
      return;
    }
    final submitSymptom = widget.config.onSubmitSymptom;
    if (kind == CocoonQuickAddKind.symptom && submitSymptom != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CocoonSymptomLogScreen(
            fa: _fa,
            options: widget.config.symptomOptions,
            submitState: widget.config.symptomSubmitState,
            onSubmit: submitSymptom,
            onOpenMedicalAttention: widget.config.onOpenMedicalAttention,
          ),
        ),
      );
      return;
    }
    widget.config.onOpenQuickAdd?.call(kind);
  }
}

class _DestinationState extends StatelessWidget {
  const _DestinationState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: CocoonTheme.sage,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: CocoonTheme.sageStrong, size: 32),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: CocoonTheme.muted),
                ),
              ],
            ),
          ),
        ),
      );
}
