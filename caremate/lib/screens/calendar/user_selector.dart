import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/app_mock_data.dart';
import '../../../models/user_model.dart';

class UserSelector extends StatelessWidget {
  final String selectedUserId;
  final TextStyle font;
  final Function(String) onUserSelected;

  const UserSelector({
    Key? key,
    required this.selectedUserId,
    required this.font,
    required this.onUserSelected,
  }) : super(key: key);

  // این تابع به عنوان جایگزین (fallback) باقی می‌ماند
  IconData _getIconForRole(String role) {
    switch (role) {
      case 'مادر':
        return Icons.pregnant_woman;
      case 'فرزند':
        return Icons.child_care;
      case 'پدر':
      case 'همسر':
        return Icons.favorite;
      default:
        return Icons.person;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: AppMockData.familyMembers.map((user) {
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _buildUserChip(
              user: user,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUserChip({required UserModel user}) {
    final bool isSelected = selectedUserId == user.id;

    // <<< تغییر کلیدی اینجاست >>>
    // یک ویجت برای نمایش آواتار یا آیکون تعریف می‌کنیم
    final Widget leadingWidget;

    if (user.avatarPath != null && user.avatarPath!.isNotEmpty) {
      // اگر مسیر عکس وجود داشت، از CircleAvatar استفاده کن
      leadingWidget = CircleAvatar(
        radius: 12, // اندازه دایره
        backgroundImage: AssetImage(user.avatarPath!),
      );
    } else {
      // در غیر این صورت، از همان آیکون قبلی استفاده کن
      leadingWidget = Icon(
        _getIconForRole(user.role),
        size: 18,
        color: isSelected ? Colors.white : AppColors.primaryText,
      );
    }

    return GestureDetector(
      onTap: () => onUserSelected(user.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color:
              isSelected ? AppColors.darkBlue : Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.darkBlue.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            // <<< ویجت جدید را اینجا قرار می‌دهیم >>>
            leadingWidget,
            const SizedBox(width: 8),
            Text(
              user.name,
              style: font.copyWith(
                color: isSelected ? Colors.white : AppColors.primaryText,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
