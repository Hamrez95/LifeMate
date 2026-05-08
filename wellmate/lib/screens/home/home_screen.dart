import 'package:flutter/material.dart';
import '../../core/theme/app_style.dart';
import '../../core/widgets/wellmate_app_header.dart'; // ایمپورت هدر اضافه شد
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
  int _currentIndex = 4; // خانه (ایندکس 1 بر اساس ترتیب جدید)

  final List<Widget> _pages = [
    const CalendarScreen(), // ایندکس 0: تقویم
    Container(), // ایندکس 1: داروها / درمان‌ها (فعلا خالی تا زمانی که صفحه‌اش را بسازید)
    Container(), // ایندکس 2: افزودن درمان
    Container(), // ایندکس 3: مراقب جدید
    const HomeScreenContent(), // ایندکس 4: خانه (محتوای اصلی باید اینجا باشد)
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
      // با این ویژگی اجازه می‌دهیم محتوا به زیر نویگیشن بار برود (مثل CareMate)
      extendBody: true,

      body: SafeArea(
        bottom:
            false, // پایین را false می‌گذاریم تا لیست‌ها تا پشت نویگیشن بار اسکرول شوند
        child: Column(
          children: [
            // --- هدر اپلیکیشن ---
            // هدر همیشه در بالای تمام تب‌ها ثابت می‌ماند
            WellMateAppHeader(
              onProfileTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ProfileScreen()),
                );
              },
            ),

            // --- محتوای تب‌ها ---
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: _pages,
              ),
            ),
          ],
        ),
      ),

      // نویگیشن بار دقیقاً مثل CareMate به پایین Scaffold متصل می‌شود
      bottomNavigationBar: WellMateBottomNav(
        currentIndex: _currentIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
