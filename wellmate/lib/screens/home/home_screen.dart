import 'package:flutter/material.dart';
import '../../localization/app_localizations.dart';
import '../../core/theme/app_style.dart';
import '../../core/widgets/glass_bottom_nav.dart';
import '../calendar/calendar_screen.dart'; // مسیرها رو با پروژه خودت چک کن
import '../profile/profile_screen.dart';
import 'home_screen_content.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 1; // صفحه اصلی پیش‌فرض

  final List<Widget> _pages = [
    const CalendarScreen(), // ایندکس 0
    const HomeScreenContent(), // ایندکس 1 (تب اصلی)
    const ProfileScreen(), // ایندکس 2
    Container(), // ایندکس 3 (مثلا تنظیمات)
  ];

  void _onItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final font = AppTextStyles.body(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: GlassBottomNav(
        currentIndex: _currentIndex,
        onTap: _onItemTapped,
        addText: loc['home_add_medicine'] ?? 'افزودن',
        font: font,
      ),
    );
  }
}
