import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/widgets/wellmate_app_header.dart';
import '../../core/widgets/wellmate_bottom_nav.dart';
import '../../models/schedule_item_model.dart';
import '../calendar/calendar_screen.dart';
import '../profile/profile_screen.dart';
import '../treatments/care_plan_hub_screen.dart';
import '../treatments/treatments_screen.dart';
import '../women_calendar/women_calendar_screen.dart';
import 'home_screen_content.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 4;
  int _refreshToken = 0;
  bool _womenCalendarEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadWomenCalendarState();
    });
  }

  Future<void> _loadWomenCalendarState() async {
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
      if (mounted) {
        setState(() {
          _womenCalendarEnabled = false;
          if (_currentIndex == 3) _currentIndex = 4;
        });
      }
      return;
    }
    try {
      final profile = await context
          .read<LifeMateApiClient>()
          .getWomenCalendarProfile();
      if (mounted) {
        final enabled = profile['enabled'] == true;
        setState(() {
          _womenCalendarEnabled = enabled;
          if (!enabled && _currentIndex == 3) _currentIndex = 4;
        });
      }
    } catch (_) {
      debugPrint('Women calendar navigation state failed.');
      if (mounted && _currentIndex == 3) {
        setState(() => _currentIndex = 4);
      }
    }
  }

  void _treatmentCreated() {
    setState(() {
      _refreshToken++;
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
      setState(() => _refreshToken++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.title} به عنوان مصرف‌شده ثبت شد.')),
      );
      return true;
    } on LifeMateApiException catch (error) {
      if (!mounted) return false;
      final message = error.code == 'stale_dose_occurrence'
          ? 'وضعیت دارو تغییر کرده است؛ برنامه تازه‌سازی شد.'
          : 'ثبت مصرف انجام نشد؛ دوباره تلاش کنید.';
      setState(() => _refreshToken++);
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
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      CalendarScreen(refreshToken: _refreshToken),
      TreatmentsScreen(refreshToken: _refreshToken),
      CarePlanHubScreen(onCreated: _treatmentCreated),
      WomenCalendarScreen(onProfileChanged: _loadWomenCalendarState),
      HomeScreenContent(
        key: ValueKey(_refreshToken),
        onOpenTreatments: () => _onItemTapped(1),
        onAddTreatment: () => _onItemTapped(2),
      ),
    ];
    return PopScope<void>(
      canPop: _currentIndex == 4,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != 4) {
          setState(() => _currentIndex = 4);
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
                  await _loadWomenCalendarState();
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
