import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../circle/api_camp_companion_selection_source.dart';
import '../circle/camp_companion_selection.dart';
import '../circle/camp_companion_selection_view.dart';
import '../living_camp/camp_home.dart';
import '../living_camp/camp_scene_renderer.dart';
import '../modules/module_registry.dart';
import '../modules/module_route_host.dart';
import '../navigation/shell_navigation.dart';
import '../profile/profile_you_screen.dart';
import '../today/notification_center_contract.dart';
import '../today/notification_center_view.dart';
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
    this.notificationSource,
    this.campCompanionSource,
    this.campZonePresentations,
  });

  final LifeMateApiClient? apiClient;
  final ValueChanged<Locale>? onLocaleChanged;
  final ShellDestination initialDestination;
  final LifeMateModuleRegistry? moduleRegistry;
  final TodaySnapshotSource? todaySource;
  final NotificationCenterSource? notificationSource;
  final CampCompanionSelectionSource? campCompanionSource;

  /// Privacy-safe localized snapshot from a reviewed Camp presentation adapter.
  final List<CampZonePresentation>? campZonePresentations;

  @override
  State<LifeMateShell> createState() => _LifeMateShellState();
}

class _LifeMateShellState extends State<LifeMateShell> {
  late ShellDestination _destination = widget.initialDestination;
  bool _overlayOpen = false;
  LifeMateApiClient? _defaultCampCompanionClient;
  ApiCampCompanionSelectionSource? _defaultCampCompanionSource;

  bool get _isPersian => Localizations.localeOf(context).languageCode == 'fa';

  LifeMateModuleRegistry get _moduleRegistry =>
      widget.moduleRegistry ?? LifeMateModuleRegistry.foundation();

  TodaySnapshotSource get _todaySource =>
      widget.todaySource ?? const UnavailableTodaySource();

  NotificationCenterSource get _notificationSource =>
      widget.notificationSource ?? const UnavailableNotificationCenterSource();

  CampCompanionSelectionSource get _campCompanionSource {
    final injected = widget.campCompanionSource;
    if (injected != null) return injected;

    final apiClient = widget.apiClient;
    if (apiClient == null) {
      _defaultCampCompanionClient = null;
      _defaultCampCompanionSource = null;
      return const UnavailableCampCompanionSelectionSource();
    }

    if (!identical(_defaultCampCompanionClient, apiClient) ||
        _defaultCampCompanionSource == null) {
      _defaultCampCompanionClient = apiClient;
      _defaultCampCompanionSource = ApiCampCompanionSelectionSource(
        apiClient: apiClient,
        isPersian: _isPersian,
      );
    } else {
      _defaultCampCompanionSource!.updateLocale(isPersian: _isPersian);
    }
    return _defaultCampCompanionSource!;
  }

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
    setState(() => _overlayOpen = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      await openLifeMateModule(
        context,
        module: module,
        isPersian: _isPersian,
        apiClient: widget.apiClient,
      );
    } finally {
      if (mounted) setState(() => _overlayOpen = false);
    }
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
        await openLifeMateModule(
          context,
          module: module,
          isPersian: _isPersian,
          apiClient: widget.apiClient,
        );
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
    setState(() => _overlayOpen = true);
    try {
      await showTodayPeekSheet(
        context: context,
        source: _todaySource,
        isPersian: _isPersian,
        onViewFullDay: () => _select(ShellDestination.today),
        onAction: _openTodayAction,
      );
    } finally {
      if (mounted) setState(() => _overlayOpen = false);
    }
  }

  Future<void> _showNotificationCenter() async {
    setState(() => _overlayOpen = true);
    try {
      await showNotificationCenter(
        context: context,
        source: _notificationSource,
        isPersian: _isPersian,
        onAction: _openTodayAction,
      );
    } finally {
      if (mounted) setState(() => _overlayOpen = false);
    }
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
    final primaryDestinations = shellPrimaryDestinationOrder;
    return PopScope<Object?>(
      canPop: _destination == ShellDestination.home,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        extendBody: _destination == ShellDestination.home,
        extendBodyBehindAppBar: _destination == ShellDestination.home,
        appBar: AppBar(
          leading: _destination == ShellDestination.today
              ? IconButton(
                  tooltip: _t('Back to Home', 'بازگشت به خانه'),
                  onPressed: () => _select(ShellDestination.home),
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          toolbarHeight: _destination == ShellDestination.home ? 76 : 68,
          backgroundColor: _destination == ShellDestination.home
              ? Colors.transparent
              : null,
          elevation: 0,
          systemOverlayStyle: _destination == ShellDestination.home
              ? SystemUiOverlayStyle.light
              : null,
          title: _destination == ShellDestination.home
              ? _HomeShellTitle(isPersian: _isPersian)
              : Text(
                  _title(_destination),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
          actions: [
            IconButton(
              tooltip: _t('Notifications', 'اعلان‌ها'),
              onPressed: _showNotificationCenter,
              style: _destination == ShellDestination.home
                  ? IconButton.styleFrom(
                      backgroundColor: const Color(0xB52A3444),
                      foregroundColor: Colors.white,
                    )
                  : null,
              icon: const Icon(Icons.notifications_none_rounded),
            ),
            if (_destination != ShellDestination.you)
              IconButton(
                key: const ValueKey('shell-open-profile'),
                tooltip: _t('Open profile', 'باز کردن پروفایل'),
                onPressed: () => _select(ShellDestination.you),
                icon: CircleAvatar(
                  radius: 19,
                  backgroundColor: _destination == ShellDestination.home
                      ? const Color(0xFFE8D8C8)
                      : null,
                  child: const Icon(Icons.person_outline_rounded, size: 21),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: IndexedStack(
          index: destinations.indexOf(_destination),
          children: destinations.map(_buildDestination).toList(growable: false),
        ),
        bottomNavigationBar: _destination == ShellDestination.today
            ? null
            : _destination == ShellDestination.home
            ? SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        navigationBarTheme: NavigationBarThemeData(
                          labelTextStyle: WidgetStateProperty.resolveWith(
                            (states) => TextStyle(
                              color: states.contains(WidgetState.selected)
                                  ? const Color(0xFFFFE2A0)
                                  : Colors.white,
                              fontWeight: states.contains(WidgetState.selected)
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          iconTheme: WidgetStateProperty.resolveWith(
                            (states) => IconThemeData(
                              color: states.contains(WidgetState.selected)
                                  ? const Color(0xFFFFE2A0)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      child: _navigationBar(
                        primaryDestinations,
                        isOverlay: true,
                      ),
                    ),
                  ),
                ),
              )
            : _navigationBar(primaryDestinations),
      ),
    );
  }

  NavigationBar _navigationBar(
    List<ShellDestination> destinations, {
    bool isOverlay = false,
  }) => NavigationBar(
    height: isOverlay ? 76 : null,
    backgroundColor: isOverlay
        ? const Color(0xEC232E38)
        : Theme.of(context).colorScheme.surface,
    indicatorColor: isOverlay
        ? const Color(0x333A4D50)
        : Theme.of(context).colorScheme.primaryContainer,
    selectedIndex: destinations.contains(_destination)
        ? destinations.indexOf(_destination)
        : 0,
    onDestinationSelected: (index) => _select(destinations[index]),
    destinations: [
      for (final destination in destinations)
        NavigationDestination(
          icon: Icon(destination.icon),
          selectedIcon: Icon(destination.selectedIcon),
          label: _title(destination),
        ),
    ],
  );

  Widget _buildDestination(ShellDestination destination) {
    return switch (destination) {
      ShellDestination.home => TickerMode(
        enabled: _destination == ShellDestination.home && !_overlayOpen,
        child: CampHome(
          isPersian: _isPersian,
          onOpenToday: _showTodayPeek,
          onOpenWellMate: () => _openModule(LifeMateModuleId.wellMate),
          onOpenCareMate: () => _openModule(LifeMateModuleId.careMate),
          onOpenReproductiveContext: () =>
              _openModule(LifeMateModuleId.womenHealth),
          onOpenFitMate: () => _openModule(LifeMateModuleId.fitMate),
          zonePresentations: widget.campZonePresentations,
        ),
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
      ShellDestination.circle => CampCompanionSelectionView(
        source: _campCompanionSource,
        isPersian: _isPersian,
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
    final productSections = <Widget>[];
    for (final module in _moduleRegistry.modules) {
      if (module.availability != ModuleAvailability.available ||
          module.profileSectionsBuilder == null) {
        continue;
      }
      try {
        productSections.addAll(
          module.profileSectionsBuilder!(context, apiClient, _isPersian),
        );
      } catch (_) {
        // A product profile extension must not take down the global profile.
      }
    }
    return ProfileYouScreen(
      apiClient: apiClient,
      isPersian: _isPersian,
      onLocaleChanged: widget.onLocaleChanged ?? (_) {},
      productSections: productSections,
    );
  }

  String _title(ShellDestination destination) => switch (destination) {
    ShellDestination.home => _t('Home', 'خانه'),
    ShellDestination.today => _t('Today', 'امروز'),
    ShellDestination.journey => _t('Journey', 'مسیر'),
    ShellDestination.circle => _t('Circle', 'دایره'),
    ShellDestination.you => _t('You', 'شما'),
  };
}

class _HomeShellTitle extends StatelessWidget {
  const _HomeShellTitle({required this.isPersian});

  final bool isPersian;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.max,
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFFFFE2A0),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(4),
        child: Image.asset(
          'assets/branding/lifemate_logo.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
      const SizedBox(width: 9),
      Flexible(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LifeMate',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            Text(
              isPersian ? 'زندگی، با هم' : 'Your Life. Together.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ],
        ),
      ),
    ],
  );
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
