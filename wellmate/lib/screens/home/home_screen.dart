import 'package:flutter/material.dart';
import '../../core/theme/app_style.dart';
import '../../core/widgets/wellmate_app_header.dart';
import '../../core/widgets/wellmate_bottom_nav.dart';
import '../calendar/calendar_screen.dart';
import '../profile/profile_screen.dart';
import '../treatments/add_treatment_screen.dart';
import '../treatments/treatments_screen.dart';
import 'home_screen_content.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 3;
  int _refreshToken = 0;

  void _treatmentCreated() {
    setState(() {
      _refreshToken++;
      _currentIndex = 3;
    });
  }

  void _onItemTapped(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const CalendarScreen(),
      TreatmentsScreen(refreshToken: _refreshToken),
      TabbedAddTreatmentScreen(onCreated: _treatmentCreated),
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
              onProfileTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ProfileScreen(),
                  ),
                );
              },
            ),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: pages,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: WellMateBottomNav(
        currentIndex: _currentIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
