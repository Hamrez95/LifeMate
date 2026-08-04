import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/widgets/wellmate_app_header.dart';
import '../../core/widgets/wellmate_bottom_nav.dart';
import '../calendar/calendar_screen.dart';
import '../profile/profile_destination_screens.dart';
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
      if (mounted) setState(() => _womenCalendarEnabled = false);
      return;
    }
    try {
      final profile = await context
          .read<LifeMateApiClient>()
          .getWomenCalendarProfile();
      if (mounted) {
        setState(() => _womenCalendarEnabled = profile['enabled'] == true);
      }
    } catch (error) {
      debugPrint('Women calendar navigation state failed.');
    }
  }

  void _treatmentCreated() {
    setState(() {
      _refreshToken++;
      _currentIndex = 4;
    });
  }

  Future<void> _onItemTapped(int index) async {
    if (index == 3 && !_womenCalendarEnabled) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const SubscriptionScreen()),
      );
      await _loadWomenCalendarState();
      if (!_womenCalendarEnabled) return;
    }
    if (mounted) setState(() => _currentIndex = index);
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
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            WellMateAppHeader(
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
    );
  }
}
