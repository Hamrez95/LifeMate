import 'package:flutter/material.dart';

class CareMateBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CareMateBottomNav({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4F9),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10)),
          const BoxShadow(color: Colors.white, blurRadius: 10, offset: Offset(0, -5)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _navIcon(Icons.calendar_today_rounded, 0),
          _navIcon(Icons.person_outline_rounded, 1),
          // Floating Add Button
          Transform.translate(
            offset: const Offset(0, -25),
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF2C3E50),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: const Color(0xFF2C3E50).withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 10)),
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 30),
            ),
          ),
          _navIcon(Icons.notifications_none_rounded, 2),
          GestureDetector(
            onTap: () => onTap(3),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: currentIndex == 3 ? const Color(0xFF2C3E50) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.home_rounded, color: currentIndex == 3 ? Colors.white : Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navIcon(IconData icon, int index) {
    return GestureDetector(
      onTap: () => onTap(index),
      child: Icon(icon, color: currentIndex == index ? Colors.black : Colors.grey[500], size: 28),
    );
  }
}
