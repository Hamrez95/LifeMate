import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../circle/api_camp_companion_selection_source.dart';
import '../circle/camp_companion_selection.dart';
import '../circle/camp_companion_selection_view.dart';
import '../living_camp/camp_home.dart';
import '../living_camp/camp_introduction.dart';
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
  LifeMateModuleRegistry? _capabilityRegistry;
  LifeMateApiClient? _capabilityClient;
  String? _capabilityAccountId;
  int _capabilityRequestGeneration = 0;
  bool _capabilityRequestPending = false;
  bool _campIntroductionScheduled = false;
  LifeMateApiClient? _defaultCampCompanionClient;
  ApiCampCompanionSelectionSource? _defaultCampCompanionSource;
  Map<String, dynamic> _currentProfile = const <String, dynamic>{};
  int _profileRequestGeneration = 0;

  @override
  void initState() {
    super.initState();
    LifeMateProfileRefresh.revision.addListener(_refreshCurrentProfile);
    _refreshCurrentProfile();
    _ensureCapabilityRegistry();
    _scheduleCampIntroduction();
  }

  @override
  void didUpdateWidget(covariant LifeMateShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient ||
        oldWidget.moduleRegistry != widget.moduleRegistry) {
      _capabilityRegistry = null;
      _capabilityClient = null;
      _capabilityRequestPending = false;
      if (oldWidget.apiClient != widget.apiClient) {
        _currentProfile = const <String, dynamic>{};
        _refreshCurrentProfile();
      }
      _ensureCapabilityRegistry();
    }
  }

  @override
  void dispose() {
    LifeMateProfileRefresh.revision.removeListener(_refreshCurrentProfile);
    _profileRequestGeneration++;
    super.dispose();
  }

  void _refreshCurrentProfile() {
    final apiClient = widget.apiClient;
    final generation = ++_profileRequestGeneration;
    if (apiClient == null) {
      if (mounted && _currentProfile.isNotEmpty) {
        setState(() => _currentProfile = const <String, dynamic>{});
      }
      return;
    }

    unawaited(
      apiClient
          .getCurrentUser()
          .then((currentUser) {
            if (!mounted || generation != _profileRequestGeneration) return;
            final rawProfile = currentUser['profile'];
            final profile = rawProfile is Map<String, dynamic>
                ? rawProfile
                : const <String, dynamic>{};
            final savedLanguage = switch (profile['locale']) {
              'fa' => const Locale('fa'),
              'en' => const Locale('en'),
              _ => null,
            };
            if (savedLanguage != null) {
              widget.onLocaleChanged?.call(savedLanguage);
            }
            // Keep only presentation fields in shell memory. Contact and health
            // fields from /me are not needed for the Camp header.
            final presentation = <String, dynamic>{
              if (profile['displayName'] is String)
                'displayName': profile['displayName'],
              if (profile['avatarKey'] is String)
                'avatarKey': profile['avatarKey'],
              if (profile['profilePhotoUrl'] is String)
                'profilePhotoUrl': profile['profilePhotoUrl'],
            };
            setState(() => _currentProfile = presentation);
          })
          .catchError((Object _) {
            if (!mounted || generation != _profileRequestGeneration) return;
            setState(() => _currentProfile = const <String, dynamic>{});
          }),
    );
  }

  bool get _isPersian => Localizations.localeOf(context).languageCode == 'fa';

  LifeMateModuleRegistry get _moduleRegistry =>
      widget.moduleRegistry ??
      _capabilityRegistry ??
      LifeMateModuleRegistry.production();

  String? get _currentAccountId {
    try {
      return LifeMateAuth.currentAccountId;
    } on Object {
      return null;
    }
  }

  void _scheduleCampIntroduction() {
    if (_campIntroductionScheduled ||
        widget.apiClient == null ||
        widget.moduleRegistry != null) {
      return;
    }
    final accountId = _currentAccountId;
    if (accountId == null) return;
    _campIntroductionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!MediaQuery.disableAnimationsOf(context)) {
        await Future<void>.delayed(const Duration(milliseconds: 3100));
      }
      if (!mounted || _currentAccountId != accountId) return;

      var completed = false;
      try {
        completed = await const CampIntroductionPreferences().hasCompleted;
      } on Object {
        // The Camp remains usable if the device preference store is unavailable.
      }
      if (!mounted || _currentAccountId != accountId || completed) return;
      await _showCampIntroduction();
    });
  }

  Future<void> _showCampIntroduction() async {
    if (!mounted) return;
    await showCampIntroduction(context: context, isPersian: _isPersian);
    try {
      await const CampIntroductionPreferences().markCompleted();
    } on Object {
      // The profile keeps a replay entry even if completion could not persist.
    }
  }

  void _ensureCapabilityRegistry() {
    final apiClient = widget.apiClient;
    if (widget.moduleRegistry != null || apiClient == null) return;

    final accountId = _currentAccountId;
    if (_capabilityRequestPending ||
        (identical(_capabilityClient, apiClient) &&
            _capabilityAccountId == accountId &&
            _capabilityRegistry != null)) {
      return;
    }

    final generation = ++_capabilityRequestGeneration;
    _capabilityClient = apiClient;
    _capabilityAccountId = accountId;
    _capabilityRequestPending = true;
    // Keep product houses closed until the authenticated server snapshot has
    // been resolved. The shell remains usable while the request is pending.
    _capabilityRegistry = LifeMateModuleRegistry.production().withCapabilities(
      const LifeMateCapabilitySnapshot(
        accountId: 'pending',
        selfPersonId: null,
        applications: <String>{},
        features: <String>{},
      ),
    );

    unawaited(() async {
      LifeMateModuleRegistry? resolved;
      try {
        final snapshot = await apiClient.getCapabilities();
        if (accountId == null || _currentAccountId == accountId) {
          resolved = LifeMateModuleRegistry.production().withCapabilities(
            snapshot,
          );
        }
      } on Object {
        // Keep the shell navigable if the snapshot is temporarily unavailable;
        // product APIs still enforce authorization on every data request.
      }
      if (!mounted || generation != _capabilityRequestGeneration) return;
      final accountChanged =
          accountId != null && _currentAccountId != accountId;
      setState(() {
        _capabilityRequestPending = false;
        if (resolved != null) _capabilityRegistry = resolved;
        // The capability snapshot is presentation data only. If it cannot be
        // loaded, leave routing visible; each product API still authorizes its
        // own data access on the server.
        if (resolved == null && !accountChanged) {
          _capabilityRegistry = LifeMateModuleRegistry.production();
        }
      });
      if (accountChanged) _ensureCapabilityRegistry();
    }());
  }

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
        hostActions: LifeMateModuleHostActions(
          onOpenGlobalProfile: _openGlobalProfileFromModule,
          onReturnHome: () => Navigator.of(context).pop(),
        ),
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
          hostActions: LifeMateModuleHostActions(
            onOpenGlobalProfile: _openGlobalProfileFromModule,
            onReturnHome: () => Navigator.of(context).pop(),
          ),
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

  void _openGlobalProfileFromModule() {
    Navigator.of(context).pop();
    _select(ShellDestination.you);
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
    _ensureCapabilityRegistry();
    final destinations = shellDestinationOrder;
    final primaryDestinations = shellPrimaryDestinationOrder;
    return PopScope<Object?>(
      canPop: _destination == ShellDestination.home,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        extendBody: _destination == ShellDestination.home,
        extendBodyBehindAppBar: _destination == ShellDestination.home,
        appBar: _destination == ShellDestination.you
            ? null
            : AppBar(
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
                  if (widget.apiClient is DurableLifeMateApiClient)
                    _OfflineRuntimeStatusAction(
                      client: widget.apiClient! as DurableLifeMateApiClient,
                      isPersian: _isPersian,
                    ),
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
                        child: _currentProfile.isEmpty
                            ? const Icon(Icons.person_outline_rounded, size: 21)
                            : LifeMateProfileAvatar(
                                avatarKey: _currentProfile['avatarKey']
                                    ?.toString(),
                                photoUrl: _currentProfile['profilePhotoUrl']
                                    ?.toString(),
                                radius: 19,
                                showBorder: false,
                              ),
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
          onOpenWellMate: _canOpenModule(LifeMateModuleId.wellMate)
              ? () => _openModule(LifeMateModuleId.wellMate)
              : null,
          onOpenCareMate: _canOpenModule(LifeMateModuleId.careMate)
              ? () => _openModule(LifeMateModuleId.careMate)
              : null,
          onOpenReproductiveContext: _canOpenModule(LifeMateModuleId.cocoonMate)
              ? () => _openModule(LifeMateModuleId.cocoonMate)
              : null,
          onOpenFitMate: _canOpenModule(LifeMateModuleId.fitMate)
              ? () => _openModule(LifeMateModuleId.fitMate)
              : null,
          zonePresentations: widget.campZonePresentations,
          welcomeName: _currentProfile['displayName']?.toString(),
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
      onBack: () => _select(ShellDestination.home),
      onNotifications: _showNotificationCenter,
      onOpenWellMate: () => _openModule(LifeMateModuleId.wellMate),
      onOpenCareMate: () => _openModule(LifeMateModuleId.careMate),
      productSections: [
        ...productSections,
        CampIntroductionTile(
          isPersian: _isPersian,
          onTap: () => unawaited(_showCampIntroduction()),
        ),
      ],
    );
  }

  String _title(ShellDestination destination) => switch (destination) {
    ShellDestination.home => _t('Home', 'خانه'),
    ShellDestination.today => _t('Today', 'امروز'),
    ShellDestination.journey => _t('Journey', 'مسیر'),
    ShellDestination.circle => _t('Circle', 'دایره'),
    ShellDestination.you => _t('You', 'شما'),
  };

  bool _canOpenModule(LifeMateModuleId moduleId) =>
      _moduleRegistry.byId(moduleId)?.canOpen ?? false;
}

class _OfflineRuntimeStatusAction extends StatelessWidget {
  const _OfflineRuntimeStatusAction({
    required this.client,
    required this.isPersian,
  });

  final DurableLifeMateApiClient client;
  final bool isPersian;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: client.offlineRuntimeAvailable,
    builder: (context, available, _) {
      if (available) return const SizedBox.shrink();
      return IconButton(
        tooltip: isPersian
            ? 'ذخیره‌سازی آفلاین آماده نیست؛ برای تلاش دوباره بزنید'
            : 'Offline storage is unavailable; tap to retry',
        onPressed: () async {
          try {
            await client.retryOfflineRuntimeInitialization();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isPersian
                      ? 'ذخیره‌سازی آفلاین آماده شد.'
                      : 'Offline storage is ready.',
                ),
              ),
            );
          } on Object {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isPersian
                      ? 'ذخیره‌سازی آفلاین آماده نشد. اطلاعات صف‌شده حفظ شده؛ بعداً دوباره تلاش کنید.'
                      : 'Offline storage is still unavailable. Queued data is preserved; try again later.',
                ),
              ),
            );
          }
        },
        icon: const Icon(Icons.sync_problem_rounded),
      );
    },
  );
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
