import 'package:flutter/material.dart';
import '../theme/app_style.dart';

class GlobalBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const GlobalBottomNav({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: BottomNavigationBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        currentIndex: currentIndex,
        onTap: onTap,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: AppTextStyles.caption(context)
            .copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
        unselectedLabelStyle: AppTextStyles.caption(context),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded, size: 28), label: 'خانه'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_rounded, size: 28),
              label: 'تقویم'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded, size: 28), label: 'پروفایل'),
        ],
      ),
    );
  }
}
