import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/constants/app_colors.dart';
import '../../models/user_model.dart';

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

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Icon(Icons.family_restroom_rounded, color: AppColors.primaryBlue),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'هنوز فردی به حساب مراقبت شما متصل نیست.',
                      en: "No one is connected to your care account yet.",
                    ),
                    en: "No one is connected to your care account yet.",
                  ),
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

    // The scroll view follows the app Directionality. In Persian the first
    // recipient starts at the right edge and additional recipients naturally
    // continue to the left, while still allowing horizontal scrolling.
    return SingleChildScrollView(
      key: const ValueKey<String>('care-calendar-recipient-scroll'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: users
            .map(
              (user) => Padding(
                padding: const EdgeInsetsDirectional.only(end: 10),
                child: _UserChip(
                  user: user,
                  selected: selectedUserId == user.id,
                  font: font,
                  onTap: () => onUserSelected(user.id),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _UserChip extends StatelessWidget {
  const _UserChip({
    required this.user,
    required this.selected,
    required this.font,
    required this.onTap,
  });

  final UserModel user;
  final bool selected;
  final TextStyle font;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'نمایش تقویم ${user.name}',
          en: "Display calendar ${user.name}",
        ),
        en: "Display calendar ${user.name}",
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>('care-calendar-recipient-${user.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 180),
            constraints: BoxConstraints(minHeight: 48),
            padding: EdgeInsetsDirectional.fromSTEB(9, 7, 14, 7),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.darkBlue
                  : Colors.white.withValues(alpha: 0.76),
              borderRadius: BorderRadius.circular(22),
              border: selected
                  ? Border.all(color: Colors.white.withValues(alpha: 0.34))
                  : Border.all(
                      color: AppColors.primaryBlue.withValues(alpha: 0.08),
                    ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.darkBlue.withValues(alpha: 0.24),
                        blurRadius: 10,
                        offset: Offset(0, 5),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RecipientAvatar(user: user),
                SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 116),
                  child: Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: font.copyWith(
                      color: selected ? Colors.white : AppColors.primaryText,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecipientAvatar extends StatelessWidget {
  const _RecipientAvatar({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final photoUrl = user.profilePhotoUrl?.trim();
    final avatarKey = user.avatarKey?.trim();

    if ((photoUrl != null && photoUrl.isNotEmpty) ||
        (avatarKey != null && avatarKey.isNotEmpty)) {
      return LifeMateProfileAvatar(
        key: ValueKey<String>('care-calendar-avatar-${user.id}'),
        photoUrl: photoUrl,
        avatarKey: avatarKey,
        radius: 14,
        showBorder: true,
      );
    }

    final legacyAsset = user.avatarPath?.trim();
    if (legacyAsset != null && legacyAsset.isNotEmpty) {
      return CircleAvatar(
        key: ValueKey<String>('care-calendar-avatar-${user.id}'),
        radius: 14,
        backgroundColor: Colors.white,
        backgroundImage: AssetImage(legacyAsset),
      );
    }

    return LifeMateProfileAvatar(
      key: ValueKey<String>('care-calendar-avatar-${user.id}'),
      avatarKey: LifeMateProfileAvatars.defaultKey,
      radius: 14,
      showBorder: true,
    );
  }
}
