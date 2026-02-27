import 'package:flutter/material.dart';
import 'app_style.dart'; // فایل استایل بالا

// --- کانتینر نئومورفیک پایه ---
class NeumorphicContainer extends StatelessWidget {
  final Widget child;
  final double padding;
  final BoxShape shape;
  final Color? color;

  const NeumorphicContainer({
    Key? key, 
    required this.child, 
    this.padding = 10,
    this.shape = BoxShape.circle,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: color ?? AppColors.bgLight,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? BorderRadius.circular(20) : null,
        boxShadow: [
          BoxShadow(color: AppColors.shadowLight, offset: const Offset(-4, -4), blurRadius: 10),
          BoxShadow(color: AppColors.shadowDark, offset: const Offset(4, 4), blurRadius: 10),
        ],
      ),
      child: child,
    );
  }
}

// --- هدر مشترک صفحات ---
class CustomHeader extends StatelessWidget {
  final String title;
  final VoidCallback onProfileTap;
  final VoidCallback? onNotificationTap;

  const CustomHeader({
    Key? key,
    required this.title,
    required this.onProfileTap,
    this.onNotificationTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: onNotificationTap,
          child: NeumorphicContainer(
            child: const Icon(Icons.notifications_none_rounded, color: Color(0xFF4B5563), size: 24),
          ),
        ),
        Text(title, style: AppTextStyles.title(context)),
        GestureDetector(
          onTap: onProfileTap,
          child: NeumorphicContainer(
            padding: 3,
            child: const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFFE2D4C8),
              child: Icon(Icons.person, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

// --- دکمه عملیات نئومورفیک ---
class NeumorphicButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final bool isLoading;

  const NeumorphicButton({
    Key? key, 
    required this.text, 
    required this.onTap, 
    this.isLoading = false
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 55,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: AppColors.bgLight,
        border: Border.all(color: Colors.black, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0, 4), blurRadius: 8),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Center(
            child: isLoading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : Text(text, style: AppTextStyles.get(context, fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black)),
          ),
        ),
      ),
    );
  }
}

// --- نوار ناوبری شیشه‌ای (Global Navigation) ---
class GlobalBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final String addBtnLabel;

  const GlobalBottomNav({
    Key? key,
    required this.currentIndex,
    required this.onTap,
    required this.addBtnLabel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 95,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withOpacity(0.0), Colors.white],
        ),
      ),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            height: 70,
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF2F7),
              borderRadius: BorderRadius.circular(35),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10)),
                const BoxShadow(color: Colors.white, blurRadius: 10, offset: Offset(0, -5)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _navItem(0, Icons.home_filled),
                _navItem(1, Icons.calendar_today_rounded), // جابجایی بر اساس منطق شما
                const SizedBox(width: 60),
                _navItem(2, Icons.sticky_note_2_outlined), // مثال: History
                _navItem(3, Icons.medication_outlined),
              ],
            ),
          ),
          Positioned(
            bottom: 25,
            child: GestureDetector(
              onTap: () => onTap(4), // فرض می‌کنیم 4 برای دکمه وسط است
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 65,
                    height: 65,
                    decoration: BoxDecoration(
                      color: const Color(0xFF283054),
                      shape: BoxShape.circle,
                      boxShadow: [
                         BoxShadow(color: const Color(0xFF283054).withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: const [
                        Icon(Icons.medication, color: Colors.white, size: 28),
                        Positioned(right: 14, bottom: 14, child: Icon(Icons.add_circle, color: Colors.white, size: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(addBtnLabel, style: AppTextStyles.get(context, fontSize: 10, fontWeight: FontWeight.w500, color: const Color(0xFF283054))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData icon) {
    final bool isActive = index == currentIndex;
    return GestureDetector(
      onTap: () => onTap(index),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: isActive ? BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)) : null,
        child: Icon(icon, size: 26, color: isActive ? Colors.white : const Color(0xFFA0A5B5)),
      ),
    );
  }
}
