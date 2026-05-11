import 'package:flutter/material.dart';
import '../../core/theme/app_style.dart';
import '../../core/widgets/wellmate_app_header.dart';
import '../../core/widgets/wellmate_bottom_nav.dart';
import '../calendar/calendar_screen.dart';
import '../profile/profile_screen.dart';
import 'home_screen_content.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 3; // ایندکس خانه حالا 3 است

  final List<Widget> _pages = [
    const CalendarScreen(), // ایندکس 0: تقویم
    Container(), // ایندکس 1: داروها
    Container(), // ایندکس 2: افزودن درمان
    const HomeScreenContent(), // ایندکس 3: خانه
  ];

  void _onItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  MaterialPageRoute(
                      builder: (context) => const ProfileScreen()),
                );
              },
            ),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: _pages,
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
