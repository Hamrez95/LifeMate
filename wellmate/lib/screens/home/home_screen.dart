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

  int _currentIndex = 4;
  final Set<int> _visitedTabs = <int>{4};
  int _calendarRevision = 0;
  int _treatmentsRevision = 0;
  int _womenRevision = 0;
  int _homeRevision = 0;
  bool _womenCalendarEnabled = LifeMateFeatureFlags.womenCalendarPilotEnabled;
  bool _womenCalendarLoading = false;
  DateTime? _womenCalendarLoadedAt;
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WellMateRefreshSignal.revision.addListener(_handleExternalRefresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadWomenCalendarState(force: true));
    });
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
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
          if (_currentIndex == 3) _currentIndex = 4;
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
        if (!enabled && _currentIndex == 3) _currentIndex = 4;
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
      _homeRevision++;
      _currentIndex = 4;
    });
  }

  Future<bool> _reportMissedDoseFromHeader(ScheduleItemModel item) async {
    try {
      await context.read<LifeMateApiClient>().reportDose(
        occurrenceId: item.id,
        clientRequestId: LifeMateApiClient.createClientRequestId(),
        version: item.version,
        status: 'taken',
        occurredAtUtc: DateTime.now().toUtc(),
      );
      if (!mounted) return true;
      setState(() {
        _calendarRevision++;
        _homeRevision++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.title} به عنوان مصرف‌شده ثبت شد.')),
      );
      return true;
    } on LifeMateApiException catch (error) {
      if (!mounted) return false;
      final message = error.code == 'stale_dose_occurrence'
          ? 'وضعیت دارو تغییر کرده است؛ برنامه تازه‌سازی شد.'
          : 'ثبت مصرف انجام نشد؛ دوباره تلاش کنید.';
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
            content: Text('ثبت مصرف انجام نشد؛ اتصال را بررسی کنید.'),
          ),
        );
      }
      return false;
    }
  }

  void _onItemTapped(int index) {
    if (index == 3 && !_womenCalendarEnabled) return;
    setState(() {
      _visitedTabs.add(index);
      _currentIndex = index;
      switch (index) {
        case 0:
          _calendarRevision++;
          break;
        case 1:
          _treatmentsRevision++;
          break;
        case 3:
          _womenRevision++;
          break;
        case 4:
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
      3 => WomenCompanionScreen(
        key: ValueKey<int>(_womenRevision),
        onProfileChanged: () => _loadWomenCalendarState(force: true),
      ),
      _ => HomeScreenContent(
        key: ValueKey<int>(_homeRevision),
        onOpenTreatments: () => _onItemTapped(1),
        onAddTreatment: () => _onItemTapped(2),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pages = List<Widget>.generate(5, _buildTab);
    return PopScope<void>(
      canPop: _currentIndex == 4,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != 4) {
          setState(() {
            _currentIndex = 4;
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
                onMissedMedicationTaken: _reportMissedDoseFromHeader,
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
