import 'package:flutter/material.dart';

import 'lifemate_api_client.dart';

@immutable
class LifeMateProfileAvatarOption {
  const LifeMateProfileAvatarOption({
    required this.key,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String key;
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
}

abstract final class LifeMateProfileAvatars {
  static const String defaultKey = 'person_blue';

  static const List<LifeMateProfileAvatarOption> options = [
    LifeMateProfileAvatarOption(
      key: 'person_blue',
      label: 'آبی',
      icon: Icons.person_rounded,
      backgroundColor: Color(0xFFE4F2FF),
      foregroundColor: Color(0xFF2878B8),
    ),
    LifeMateProfileAvatarOption(
      key: 'person_green',
      label: 'سبز',
      icon: Icons.person_rounded,
      backgroundColor: Color(0xFFE3F7EE),
      foregroundColor: Color(0xFF2D8A67),
    ),
    LifeMateProfileAvatarOption(
      key: 'person_purple',
      label: 'یاسی',
      icon: Icons.person_rounded,
      backgroundColor: Color(0xFFF0E8FF),
      foregroundColor: Color(0xFF7652B5),
    ),
    LifeMateProfileAvatarOption(
      key: 'person_orange',
      label: 'گلبهی',
      icon: Icons.person_rounded,
      backgroundColor: Color(0xFFFFECE4),
      foregroundColor: Color(0xFFB85E3B),
    ),
    LifeMateProfileAvatarOption(
      key: 'heart_coral',
      label: 'قلب',
      icon: Icons.favorite_rounded,
      backgroundColor: Color(0xFFFFE7EA),
      foregroundColor: Color(0xFFC84F65),
    ),
    LifeMateProfileAvatarOption(
      key: 'caregiver_teal',
      label: 'مراقب',
      icon: Icons.volunteer_activism_rounded,
      backgroundColor: Color(0xFFE2F7F6),
      foregroundColor: Color(0xFF277F7C),
    ),
  ];

  static bool isAllowed(String? value) =>
      value != null && options.any((option) => option.key == value);

  static String normalize(String? value) =>
      isAllowed(value) ? value! : defaultKey;

  static LifeMateProfileAvatarOption resolve(String? value) {
    final normalized = normalize(value);
    return options.firstWhere((option) => option.key == normalized);
  }
}

class LifeMateProfileAvatar extends StatelessWidget {
  const LifeMateProfileAvatar({
    super.key,
    this.avatarKey,
    this.radius = 36,
    this.showBorder = true,
  });

  final String? avatarKey;
  final double radius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final option = LifeMateProfileAvatars.resolve(avatarKey);
    return Semantics(
      image: true,
      label: 'آواتار پروفایل ${option.label}',
      child: Container(
        width: radius * 2,
        height: radius * 2,
        padding: EdgeInsets.all(showBorder ? 3 : 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: showBorder
              ? Border.all(
                  color: option.foregroundColor.withValues(alpha: 0.18),
                  width: 1.5,
                )
              : null,
        ),
        child: CircleAvatar(
          backgroundColor: option.backgroundColor,
          child: Icon(
            option.icon,
            size: radius,
            color: option.foregroundColor,
          ),
        ),
      ),
    );
  }
}

class LifeMateAvatarPicker extends StatelessWidget {
  const LifeMateAvatarPicker({
    super.key,
    required this.selectedKey,
    required this.onSelected,
  });

  final String selectedKey;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final normalized = LifeMateProfileAvatars.normalize(selectedKey);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: LifeMateProfileAvatars.options.map((option) {
        final selected = option.key == normalized;
        return Semantics(
          button: true,
          selected: selected,
          label: 'انتخاب آواتار ${option.label}',
          child: InkWell(
            key: ValueKey('profile-avatar-${option.key}'),
            onTap: onSelected == null ? null : () => onSelected!(option.key),
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? option.foregroundColor
                      : Colors.transparent,
                  width: 3,
                ),
              ),
              child: LifeMateProfileAvatar(
                avatarKey: option.key,
                radius: 30,
                showBorder: false,
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class LifeMateCurrentUserAvatar extends StatefulWidget {
  const LifeMateCurrentUserAvatar({
    super.key,
    required this.apiClient,
    this.radius = 22,
  });

  final LifeMateApiClient apiClient;
  final double radius;

  @override
  State<LifeMateCurrentUserAvatar> createState() =>
      _LifeMateCurrentUserAvatarState();
}

class _LifeMateCurrentUserAvatarState extends State<LifeMateCurrentUserAvatar> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.apiClient.getCurrentUser();
  }

  @override
  void didUpdateWidget(covariant LifeMateCurrentUserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.apiClient, widget.apiClient)) {
      _future = widget.apiClient.getCurrentUser();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, dynamic>{};
        final profile = data['profile'] as Map<String, dynamic>? ?? const {};
        return LifeMateProfileAvatar(
          avatarKey: profile['avatarKey']?.toString(),
          radius: widget.radius,
        );
      },
    );
  }
}
