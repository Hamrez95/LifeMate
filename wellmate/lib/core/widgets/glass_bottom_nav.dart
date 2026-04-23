import 'package:flutter/material.dart';
import '../theme/app_style.dart'; // اضافه شدن برای AppColors

class GlassBottomNav extends StatelessWidget {
  final String addText;
  final TextStyle font;
  final int currentIndex; // اضافه شدن برای مدیریت تب
  final Function(int) onTap; // اضافه شدن برای مدیریت تب

  const GlassBottomNav({
    Key? key,
    required this.addText,
    required this.font,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 95,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.background.withOpacity(0.0), AppColors.background],
        ),
      ),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            height: 70,
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(35),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadowDark,
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: AppColors.shadowLight,
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                    onTap: () => onTap(0),
                    child: _navItem(Icons.calendar_today_rounded,
                        isActive: currentIndex == 0)),
                GestureDetector(
                    onTap: () => onTap(1),
                    child: _navItem(Icons.home_filled,
                        isActive: currentIndex == 1)),
                const SizedBox(width: 60), // جای دکمه افزودن
                GestureDetector(
                    onTap: () => onTap(2),
                    child: _navItem(Icons.person, isActive: currentIndex == 2)),
                GestureDetector(
                    onTap: () => onTap(3),
                    child: _navItem(Icons.settings,
                        isActive: currentIndex == 3)), // مثال تب چهارم
              ],
            ),
          ),
          Positioned(
            bottom: 25,
            child: GestureDetector(
              onTap: () {
                // TODO: اکشن افزودن دارو
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 65,
                    height: 65,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: const [
                        Icon(Icons.medication, color: Colors.white, size: 28),
                        Positioned(
                          right: 14,
                          bottom: 14,
                          child: Icon(Icons.add_circle,
                              color: Colors.white, size: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    addText,
                    style: font.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, {required bool isActive}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: isActive
          ? BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(14),
            )
          : null,
      child: Icon(
        icon,
        size: 26,
        color: isActive ? Colors.white : AppColors.textSecondary,
      ),
    );
  }
}
