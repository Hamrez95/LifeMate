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
import '../women_calendar/women_companion_screen.dart';
import 'home_screen_content.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _womenStateTtl = Duration(seconds: 20);
  static const _refreshDebounceDuration = Duration(milliseconds: 180);
  static const _backgroundRefreshInterval = Duration(seconds: 8);
  static const _prewarmDelay = Duration(milliseconds: 350);

  int _currentIndex = 5;
  final Set<int> _visitedTabs = <int>{5};
  int _calendarRevision = 0;
  int _treatmentsRevision = 0;
  int _healthRevision = 0;
  int _womenRevision = 0;
  int _homeRevision = 0;
  bool _womenCalendarEnabled = LifeMateFeatureFlags.womenCalendarPilotEnabled;
  bool _womenCalendarLoading = false;
  DateTime? _womenCalendarLoadedAt;
  Timer? _refreshDebounce;
  Timer? _backgroundRefreshTimer;
  Timer? _prewarmTimer;
  DateTime _lastBackgroundRefresh = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WellMateRefreshSignal.revision.addListener(_handleExternalRefresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadWomenCalendarState(force: true));
    });
    _backgroundRefreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshActiveTabIfStale(),
    );
    _prewarmTimer = Timer(_prewarmDelay, () {
      if (!mounted) return;
      setState(() => _visitedTabs.addAll(const <int>{0, 1, 2, 3, 4, 5}));
    });
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _backgroundRefreshTimer?.cancel();
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
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
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
    if (_womenCalendarLoading) return;
    _womenCalendarLoading = true;

    try {
      final profile = await context
          .read<LifeMateApiClient>()
          .getWomenCalendarProfile();
      if (!mounted) return;
      final enabled = profile['enabled'] == true;
      setState(() {
        _womenCalendarEnabled = enabled;
        _womenCalendarLoadedAt = DateTime.now();
        if (!enabled && _currentIndex == 4) _currentIndex = 5;
      });
    } catch (_) {
      // Preserve the last known feature state on transient failures.
      debugPrint('Women calendar navigation state failed.');
    } finally {
      _womenCalendarLoading = false;
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

  Future<bool> _reportMissedItemFromHeader(ScheduleItemModel item) async {
    try {
      if (item.type == 'medicine') {
        await context.read<LifeMateApiClient>().reportDose(
          occurrenceId: item.id,
          clientRequestId: LifeMateApiClient.createClientRequestId(),
          version: item.version,
          status: 'taken',
          occurredAtUtc: DateTime.now().toUtc(),
        );
      } else {
        final eventId = item.seriesId ?? item.id;
        if (item.seriesId != null && item.id != item.seriesId) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'ثبت وضعیت یک نوبت تکرارشونده از اعلان‌ها هنوز پشتیبانی نمی‌شود.',
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
            item.type == 'medicine'
                ? '${item.title} به عنوان مصرف‌شده ثبت شد.'
                : '${item.title} به عنوان انجام‌شده ثبت شد.',
          ),
        ),
      );
      return true;
    } on LifeMateOfflineQueuedException {
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${item.title} روی گوشی ذخیره شد و بعد از اتصال اینترنت همگام می‌شود.',
          ),
        ),
      );
      return true;
    } on LifeMateApiException catch (error) {
      if (!mounted) return false;
      final message =
          error.code == 'stale_dose_occurrence' ||
              error.code == 'stale_care_event'
          ? 'وضعیت برنامه تغییر کرده است؛ صفحه تازه‌سازی شد.'
          : 'ثبت وضعیت انجام نشد؛ دوباره تلاش کنید.';
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
          const SnackBar(
            content: Text('ثبت وضعیت انجام نشد؛ اتصال را بررسی کنید.'),
          ),
        );
      }
      return false;
    }
  }

  void _onItemTapped(int index) {
    if (index == 4 && !_womenCalendarEnabled) return;
    if (_currentIndex != index) {
      setState(() {
        _visitedTabs.add(index);
        _currentIndex = index;
      });
    }
    _refreshActiveTabIfStale();
  }

  void _refreshActiveTabIfStale() {
    final now = DateTime.now();
    if (now.difference(_lastBackgroundRefresh) < _backgroundRefreshInterval) {
      return;
    }
    _lastBackgroundRefresh = now;
    if (!mounted) return;
    setState(() {
      switch (_currentIndex) {
        case 0:
          _calendarRevision++;
          break;
        case 1:
          _treatmentsRevision++;
          break;
        case 3:
          _healthRevision++;
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
      3 => HealthScreen(refreshToken: _healthRevision),
      4 => WomenCompanionScreen(
        refreshToken: _womenRevision,
        onProfileChanged: () => _loadWomenCalendarState(force: true),
      ),
      _ => HomeScreenContent(
        refreshToken: _homeRevision,
        onOpenTreatments: () => _onItemTapped(1),
        onAddTreatment: () => _onItemTapped(2),
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
