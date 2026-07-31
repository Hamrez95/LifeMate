import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/user_model.dart';

class UserSelector extends StatelessWidget {
  const UserSelector({
    required this.users,
    required this.selectedUserId,
    required this.font,
    required this.onUserSelected,
    super.key,
  });

  final List<UserModel> users;
  final String selectedUserId;
  final TextStyle font;
  final ValueChanged<String> onUserSelected;

  IconData _getIconForRole(String role) {
    switch (role) {
      case 'مادر':
        return Icons.pregnant_woman_rounded;
      case 'فرزند':
        return Icons.child_care_rounded;
      case 'پدر':
      case 'همسر':
        return Icons.favorite_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.72),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.family_restroom_rounded,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'هنوز فردی به حساب مراقبت شما متصل نیست.',
                  style: font.copyWith(
                    color: AppColors.secondaryText,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: users
            .map(
              (user) => Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: _buildUserChip(user: user),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _buildUserChip({required UserModel user}) {
    final isSelected = selectedUserId == user.id;
    final Widget leadingWidget;

    if (user.avatarPath != null && user.avatarPath!.isNotEmpty) {
      leadingWidget = CircleAvatar(
        radius: 12,
        backgroundColor: Colors.white,
        backgroundImage: AssetImage(user.avatarPath!),
      );
    } else {
      leadingWidget = Icon(
        _getIconForRole(user.role),
        size: 18,
        color: isSelected ? Colors.white : AppColors.primaryText,
      );
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label: 'انتخاب ${user.name}',
      child: InkWell(
        onTap: () => onUserSelected(user.id),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.darkBlue
                : Colors.white.withOpacity(0.72),
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.darkBlue.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            children: [
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
      ),
    );
  }
}
