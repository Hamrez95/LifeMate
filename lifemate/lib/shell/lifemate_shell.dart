import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../living_camp/camp_home.dart';
import '../modules/module_registry.dart';
import '../modules/module_route_host.dart';
import '../navigation/shell_navigation.dart';
import '../profile/profile_you_screen.dart';
import '../today/today_contract.dart';
import '../today/today_views.dart';

class LifeMateShell extends StatefulWidget {
  const LifeMateShell({
    super.key,
    this.apiClient,
    this.onLocaleChanged,
    this.initialDestination = ShellDestination.home,
    this.moduleRegistry,
    this.todaySource,
  });

  final LifeMateApiClient? apiClient;
  final ValueChanged<Locale>? onLocaleChanged;
  final ShellDestination initialDestination;
  final LifeMateModuleRegistry? moduleRegistry;
  final TodaySnapshotSource? todaySource;

  @override
  State<LifeMateShell> createState() => _LifeMateShellState();
}

class _LifeMateShellState extends State<LifeMateShell> {
  late ShellDestination _destination = widget.initialDestination;

  bool get _isPersian => Localizations.localeOf(context).languageCode == 'fa';

  LifeMateModuleRegistry get _moduleRegistry =>
      widget.moduleRegistry ?? LifeMateModuleRegistry.foundation();

  TodaySnapshotSource get _todaySource =>
      widget.todaySource ?? const UnavailableTodaySource();

  String _t(String en, String fa) => _isPersian ? fa : en;

  void _select(ShellDestination destination) {
    if (_destination == destination) return;
    setState(() => _destination = destination);
  }

  void _handleBack(bool didPop, Object? result) {
    if (didPop || _destination == ShellDestination.home) return;
    setState(() => _destination = ShellDestination.home);
  }

  Future<void> _openModule(LifeMateModuleId moduleId) async {
    final module = _moduleRegistry.byId(moduleId);
    if (module == null || !mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    await openLifeMateModule(context, module: module, isPersian: _isPersian);
  }

  Future<void> _openTodayAction(TodayActionIntent intent) async {
    if (!mounted) return;

    switch (intent.kind) {
      case TodayActionKind.moduleRoute:
        final module = _moduleRegistry.byRoute(intent.routeId);
        if (module == null) {
          _showActionUnavailable();
          return;
        }
        await openLifeMateModule(context, module: module, isPersian: _isPersian);
        return;
      case TodayActionKind.shellRoute:
        if (intent.routeId == '/today') {
          _select(ShellDestination.today);
          return;
        }
        _showActionUnavailable();
        return;
      case TodayActionKind.refreshOnly:
        return;
    }
  }

  Future<void> _showTodayPeek() async {
    await showTodayPeekSheet(
      context: context,
      source: _todaySource,
      isPersian: _isPersian,
      onViewFullDay: () => _select(ShellDestination.today),
      onAction: _openTodayAction,
    );
  }

  void _showActionUnavailable() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            'This action is not available in the parent app yet.',
            'این اقدام هنوز در اپ مادر در دسترس نیست.',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = shellDestinationOrder;
    return PopScope<Object?>(
      canPop: _destination == ShellDestination.home,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title(_destination)),
          actions: [
            IconButton(
              tooltip: _t('Notifications', 'اعلان‌ها'),
              onPressed: () => _showSecondaryPlaceholder(
                title: _t('Notifications', 'اعلان‌ها'),
                message: _t(
                  'The Notification Center will be implemented under the Today / Alerts epic.',
                  'مرکز اعلان‌ها در اپیک Today / Alerts پیاده‌سازی می‌شود.',
                ),
              ),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          ],
        ),
        body: IndexedStack(
          index: destinations.indexOf(_destination),
          children: destinations.map(_buildDestination).toList(growable: false),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: destinations.indexOf(_destination),
          onDestinationSelected: (index) => _select(destinations[index]),
          destinations: [
            for (final destination in destinations)
              NavigationDestination(
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.selectedIcon),
                label: _title(destination),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDestination(ShellDestination destination) {
    return switch (destination) {
      ShellDestination.home => CampHome(
        isPersian: _isPersian,
        onOpenToday: _showTodayPeek,
        onOpenWellMate: () => _openModule(LifeMateModuleId.wellMate),
      ),
      ShellDestination.today => TodayFullDay(
        source: _todaySource,
        isPersian: _isPersian,
        onAction: _openTodayAction,
      ),
      ShellDestination.journey => _StagedDestination(
        icon: Icons.route_outlined,
        title: _t('Journey', 'مسیر زندگی'),
        description: _t(
          'Journey remains intentionally staged until #1095–#1097 define and implement chapters.',
          'Journey تا زمان طراحی و پیاده‌سازی فصل‌ها در #1095 تا #1097 عمداً در حالت آماده‌سازی می‌ماند.',
        ),
      ),
      ShellDestination.circle => _StagedDestination(
        icon: Icons.people_outline,
        title: _t('Circle', 'دایره'),
        description: _t(
          'Relationships, companion selection and consent-safe presentation land in #1091–#1094.',
          'روابط، انتخاب همراه و نمایش امن مبتنی بر رضایت در #1091 تا #1094 پیاده‌سازی می‌شود.',
        ),
      ),
      ShellDestination.you => _buildYouDestination(),
    };
  }

  Widget _buildYouDestination() {
    final apiClient = widget.apiClient;
    if (apiClient == null) {
      return _StagedDestination(
        icon: Icons.person_outline,
        title: _t('You', 'شما'),
        description: _t(
          'Profile needs an authenticated API session. This fallback is only used by isolated shell tests and preview hosts.',
          'پروفایل به نشست API احراز هویت‌شده نیاز دارد. این حالت فقط در تست‌های مستقل shell و preview استفاده می‌شود.',
        ),
      );
    }
    return ProfileYouScreen(
      apiClient: apiClient,
      isPersian: _isPersian,
      onLocaleChanged: widget.onLocaleChanged ?? (_) {},
    );
  }

  String _title(ShellDestination destination) => switch (destination) {
    ShellDestination.home => _t('Home', 'خانه'),
    ShellDestination.today => _t('Today', 'امروز'),
    ShellDestination.journey => _t('Journey', 'مسیر'),
    ShellDestination.circle => _t('Circle', 'دایره'),
    ShellDestination.you => _t('You', 'شما'),
  };

  void _showSecondaryPlaceholder({
    required String title,
    required String message,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(message),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_t('Close', 'بستن')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StagedDestination extends StatelessWidget {
  const _StagedDestination({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Semantics(
              container: true,
              label: title,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(description, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
