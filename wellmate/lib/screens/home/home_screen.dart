import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/state/wellmate_refresh.dart';
import '../../core/theme/app_style.dart';
import '../../core/widgets/wellmate_app_header.dart';
import '../../core/widgets/wellmate_bottom_nav.dart';
import '../../models/schedule_item_model.dart';
import '../calendar/calendar_screen.dart';
import '../health/health_screen.dart';
import '../profile/profile_screen.dart';
import '../treatments/care_plan_hub_screen.dart';
import '../treatments/treatments_screen.dart';
import '../women_calendar/women_health_entry_screen.dart';
import 'home_offline_status_banner.dart';
import 'home_schedule_loader.dart';
import 'home_screen_content.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _womenStateTtl = Duration(seconds: 20);
  static const _refreshDebounceDuration = Duration(milliseconds: 180);
  static const _prewarmDelay = Duration(milliseconds: 350);

  int _currentIndex = 5;
  final Set<int> _visitedTabs = <int>{5};
  int _calendarRevision = 0;
  int _treatmentsRevision = 0;
  int _healthRevision = 0;
  int _womenRevision = 0;
  int _homeRevision = 0;
  bool _womenCalendarEnabled = LifeMateFeatureFlags.womenCalendarPilotEnabled;
  DateTime? _womenCalendarLoadedAt;
  Timer? _refreshDebounce;
  Timer? _prewarmTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WellMateRefreshSignal.revision.addListener(_handleExternalRefresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadWomenCalendarState(force: true));
    });
    _prewarmTimer = Timer(_prewarmDelay, () {
      if (!mounted) return;
      setState(() => _visitedTabs.addAll(const <int>{0, 1, 2, 4, 5}));
    });
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _prewarmTimer?.cancel();
    WellMateRefreshSignal.revision.removeListener(_handleExternalRefresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleFullRefresh(forceWomenState: true);
    }
  }

  void _handleExternalRefresh() {
    _scheduleFullRefresh(forceWomenState: true);
  }

  void _scheduleFullRefresh({bool forceWomenState = false}) {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(_refreshDebounceDuration, () {
      if (!mounted) return;
      setState(() {
        _calendarRevision++;
        _treatmentsRevision++;
        _healthRevision++;
        _womenRevision++;
        _homeRevision++;
      });
      unawaited(_loadWomenCalendarState(force: forceWomenState));
    });
  }

  Future<void> _loadWomenCalendarState({bool force = false}) async {
    final available = LifeMateFeatureFlags.womenCalendarPilotEnabled;
    if (!available) {
      if (mounted) {
        setState(() {
          _womenCalendarEnabled = false;
          if (_currentIndex == 4) _currentIndex = 5;
        });
      }
      return;
    }

    final loadedAt = _womenCalendarLoadedAt;
    if (!force &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < _womenStateTtl) {
      return;
    }

    // Navigation availability is a feature capability, not profile activation.
    // An inactive profile must still be able to open the Women tab so the V3
    // activation flow is reachable. The entry screen reads canonical profile
    // state and decides activation vs Period Calendar Home.
    if (mounted) {
      setState(() {
        _womenCalendarEnabled = true;
        _womenCalendarLoadedAt = DateTime.now();
      });
    }
  }

  void _treatmentCreated() {
    setState(() {
      _calendarRevision++;
      _treatmentsRevision++;
      _healthRevision++;
      _homeRevision++;
      _currentIndex = 5;
    });
  }

  Future<void> _openHealth() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => HealthScreen(refreshToken: _healthRevision),
      ),
    );
    if (!mounted) return;
    setState(() {
      _healthRevision++;
      _homeRevision++;
    });
  }

  Future<bool> _reportMissedItemFromHeader(ScheduleItemModel item) async {
    try {
      var pendingSync = false;
      if (item.type == 'medicine') {
        final result = await context.read<LifeMateApiClient>().reportDose(
          occurrenceId: item.id,
          clientRequestId: LifeMateApiClient.createClientRequestId(),
          version: item.version,
          status: 'taken',
          occurredAtUtc: DateTime.now().toUtc(),
        );
        pendingSync = result['pendingSync'] == true;
      } else {
        final eventId = item.seriesId ?? item.id;
        if (item.seriesId != null && item.id != item.seriesId) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ثبت وضعیت یک نوبت تکرارشونده از اعلان‌ها هنوز پشتیبانی نمی‌شود.',
                      en: "Recording the status of a recurring notification session is not yet supported.",
                    ),
                    en: "Recording the status of a recurring notification session is not yet supported.",
                  ),
                ),
              ),
            );
          }
          return false;
        }
        await LifeMateEditApi.fromEnvironment().updateCareEventStatus(
          eventId: eventId,
          status: 'completed',
        );
      }
      if (!mounted) return true;
      setState(() {
        _calendarRevision++;
        _homeRevision++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pendingSync
                ? LifeMateRuntimeLocale.select(
                    fa: '${item.title} روی گوشی ذخیره شد و بعد از اتصال اینترنت همگام می‌شود.',
                    en: '${item.title} was saved on this device and will sync when you reconnect.',
                  )
                : item.type == 'medicine'
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: '${item.title} به عنوان مصرف‌شده ثبت شد.',
                      en: "${item.title} was marked as taken.",
                    ),
                    en: "${item.title} registered as spent.",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: '${item.title} به عنوان انجام‌شده ثبت شد.',
                      en: "${item.title} was marked as done.",
                    ),
                    en: "${item.title} registered as done.",
                  ),
          ),
        ),
      );
      return true;
    } on LifeMateApiException catch (error) {
      if (!mounted) return false;
      final message =
          error.code == 'stale_dose_occurrence' ||
              error.code == 'stale_care_event'
          ? LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'وضعیت برنامه تغییر کرده است؛ صفحه تازه‌سازی شد.',
                en: "The application status has changed; The page has been updated.",
              ),
              en: "The application status has changed; The page has been updated.",
            )
          : LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'ثبت وضعیت انجام نشد؛ دوباره تلاش کنید.',
                en: "status registration was not done; Try again.",
              ),
              en: "status registration was not done; Try again.",
            );
      setState(() {
        _calendarRevision++;
        _homeRevision++;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return false;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'ثبت وضعیت انجام نشد؛ اتصال را بررسی کنید.',
                  en: "status registration was not done; Check the connection.",
                ),
                en: "status registration was not done; Check the connection.",
              ),
            ),
          ),
        );
      }
      return false;
    }
  }

  void _onItemTapped(int index) {
    if (index == 4 && !_womenCalendarEnabled) return;
    if (_currentIndex == index) return;

    final alreadyVisited = _visitedTabs.contains(index);
    setState(() {
      _visitedTabs.add(index);
      _currentIndex = index;
      if (!alreadyVisited) return;

      switch (index) {
        case 0:
          _calendarRevision++;
          break;
        case 1:
          _treatmentsRevision++;
          break;
        case 4:
          _womenRevision++;
          break;
        case 5:
          _homeRevision++;
          break;
      }
    });
  }

  Widget _buildTab(int index) {
    if (!_visitedTabs.contains(index)) return const SizedBox.shrink();
    return switch (index) {
      0 => CalendarScreen(refreshToken: _calendarRevision),
      1 => TreatmentsScreen(refreshToken: _treatmentsRevision),
      2 => CarePlanHubScreen(onCreated: _treatmentCreated),
      4 => WomenHealthEntryScreen(
        refreshToken: _womenRevision,
        onProfileChanged: () => _loadWomenCalendarState(force: true),
      ),
      _ => HomeScreenContent(
        refreshToken: _homeRevision,
        onOpenTreatments: () => _onItemTapped(1),
        onAddTreatment: () => _onItemTapped(2),
        onOpenHealth: _openHealth,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pages = List<Widget>.generate(6, _buildTab);
    return PopScope<void>(
      canPop: _currentIndex == 5,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != 5) {
          setState(() {
            _currentIndex = 5;
            _homeRevision++;
          });
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              WellMateAppHeader(
                onMissedMedicationTaken: _reportMissedItemFromHeader,
                onProfileTap: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const ProfileScreen(),
                    ),
                  );
                  _scheduleFullRefresh(forceWomenState: true);
                },
              ),
              if (_currentIndex == 5)
                ValueListenableBuilder<HomeOfflinePresentationState>(
                  valueListenable: homeOfflinePresentationState,
                  builder: (context, state, child) => state.cached
                      ? HomeOfflineStatusBanner(
                          cachedAtUtc: state.cachedAtUtc,
                        )
                      : const SizedBox.shrink(),
                ),
              Expanded(
                child: IndexedStack(index: _currentIndex, children: pages),
              ),
            ],
          ),
        ),
        bottomNavigationBar: WellMateBottomNav(
          currentIndex: _currentIndex,
          womenCalendarEnabled: _womenCalendarEnabled,
          onTap: _onItemTapped,
        ),
      ),
    );
  }
}
