import 'package:flutter/material.dart';
import '../../localization/app_localizations.dart';
import '../../core/theme/app_style.dart';
import '../../core/widgets/simple_bottom_nav.dart';
import '../calendar/calendar_screen.dart'; // مسیرها رو با پروژه خودت چک کن
import '../profile/profile_screen.dart';
import 'home_screen_content.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 1; // صفحه اصلی پیش‌فرض (خانه)

  final List<Widget> _pages = [
    const CalendarScreen(), // ایندکس 0
    const HomeScreenContent(), // ایندکس 1 (خانه)
    Container(), // ایندکس 2 (صفحه افزودن دارو)
    const ProfileScreen(), // ایندکس 3
    Container(), // ایندکس 4 (تنظیمات)
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
      // این خط بسیار مهم است تا محتوا زیر نویگیشن بار شناور برود
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: SimpleBottomNav(
        currentIndex: _currentIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
