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
        CocoonEntryState.loading =>
          const Center(child: CircularProgressIndicator()),
        CocoonEntryState.unauthenticated => _gate(
            Icons.lock_outline,
            t('Sign in to continue', 'برای ادامه وارد شوید'),
            t('Sign in', 'ورود'),
            host.openLogin,
          ),
        CocoonEntryState.runtimeUnavailable => _gate(
            Icons.cloud_off_outlined,
            t('CocoonMate is temporarily unavailable',
                'کوکون‌میت موقتاً در دسترس نیست'),
            t('Retry', 'تلاش دوباره'),
            host.refresh,
          ),
        CocoonEntryState.notEnrolled => _gate(
            Icons.favorite_border,
            t('CocoonMate is ready for you', 'کوکون‌میت آماده است'),
            t('Continue', 'ادامه'),
            host.refresh,
          ),
        CocoonEntryState.notEntitled => _gate(
            Icons.workspace_premium_outlined,
            t('Choose access to CocoonMate', 'دسترسی کوکون‌میت را انتخاب کنید'),
            t('View options', 'مشاهده گزینه‌ها'),
            host.openCommerce,
          ),
        CocoonEntryState.noPregnancy => _gate(
            Icons.spa_outlined,
            t('No active pregnancy yet', 'هنوز بارداری فعالی ثبت نشده'),
            t('Start setup', 'شروع ثبت'),
            host.beginPregnancySetup,
          ),
        CocoonEntryState.offline => _gate(
            Icons.wifi_off_outlined,
            t('You are offline', 'آفلاین هستید'),
            t('Retry', 'تلاش دوباره'),
            host.refresh,
          ),
        CocoonEntryState.activePregnancy => _productShell(host),
      },
    );
  }

  Widget _gate(IconData icon, String title, String action,
      Future<void> Function() onPressed) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsetsDirectional.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 40),
                    const SizedBox(height: 16),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: () => onPressed(), child: Text(action)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _productShell(CocoonHostContract host) {
    final labels = [
      t('Home', 'خانه'),
      t('Calendar', 'تقویم'),
      t('Add', 'افزودن'),
      t('Records', 'سوابق'),
      t('More', 'بیشتر'),
    ];
    final icons = const [
      Icons.home_outlined,
      Icons.calendar_month_outlined,
      Icons.add_circle_outline,
      Icons.folder_outlined,
      Icons.more_horiz,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('CocoonMate'),
        actions: [
          IconButton(
            tooltip: t('Profile', 'پروفایل'),
            onPressed: host.openGlobalProfile,
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Semantics(
            header: true,
            child: Text(labels[_index],
                style: Theme.of(context).textTheme.headlineSmall),
          ),
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
}
