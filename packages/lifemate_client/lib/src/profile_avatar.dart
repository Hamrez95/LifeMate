import 'package:flutter/foundation.dart';
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

class _LifeMateProfileCacheEntry {
  Map<String, dynamic>? profile;
  DateTime? loadedAt;
  Future<Map<String, dynamic>>? inFlight;
}

/// Shared stale-while-revalidate cache for the signed profile-photo URL and
/// avatar metadata. A single authenticated session can render the avatar in
/// several routes; without this cache every widget requested a new signed URL,
/// which changed the image key and forced another network download.
abstract final class LifeMateProfileRefresh {
  static const Duration cacheDuration = Duration(minutes: 10);
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final Map<LifeMateApiClient, _LifeMateProfileCacheEntry> _cache =
      Map<LifeMateApiClient, _LifeMateProfileCacheEntry>.identity();

  static Map<String, dynamic>? peek(LifeMateApiClient apiClient) =>
      _cache[apiClient]?.profile;

  static Future<Map<String, dynamic>> loadProfile(
    LifeMateApiClient apiClient, {
    bool force = false,
  }) {
    final entry = _cache.putIfAbsent(apiClient, _LifeMateProfileCacheEntry.new);
    final cached = entry.profile;
    final loadedAt = entry.loadedAt;
    final isFresh =
        cached != null &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < cacheDuration;
    if (!force && isFresh) return Future.value(cached!);

    final inFlight = entry.inFlight;
    if (inFlight != null) return inFlight;

    final request = apiClient
        .getCurrentProfile()
        .then((profile) {
          final stableProfile = Map<String, dynamic>.unmodifiable(
            Map<String, dynamic>.from(profile),
          );
          entry
            ..profile = stableProfile
            ..loadedAt = DateTime.now();
          return stableProfile;
        })
        .whenComplete(() {
          entry.inFlight = null;
        });
    entry.inFlight = request;
    return request;
  }

  /// Publishes the profile returned by a successful write immediately. This
  /// avoids another API request and lets all visible avatars reuse one URL.
  static void cacheProfile(
    LifeMateApiClient apiClient,
    Map<String, dynamic> profile,
  ) {
    final stableProfile = Map<String, dynamic>.unmodifiable(
      Map<String, dynamic>.from(profile),
    );
    final entry = _cache.putIfAbsent(apiClient, _LifeMateProfileCacheEntry.new);
    entry
      ..profile = stableProfile
      ..loadedAt = DateTime.now();
    revision.value = revision.value + 1;
  }

  /// Backwards-compatible invalidation for call sites that do not have the
  /// updated profile payload. Existing image data remains visible while one
  /// shared revalidation request runs.
  static void notifyChanged() {
    for (final entry in _cache.values) {
      entry.loadedAt = null;
    }
    revision.value = revision.value + 1;
  }

  @visibleForTesting
  static void clearCacheForTesting() {
    _cache.clear();
    revision.value = 0;
  }
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
    this.photoUrl,
    this.radius = 36,
    this.showBorder = true,
  });

  final String? avatarKey;
  final String? photoUrl;
  final double radius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final option = LifeMateProfileAvatars.resolve(avatarKey);
    final normalizedPhotoUrl = photoUrl?.trim();
    final hasPhoto =
        normalizedPhotoUrl != null && normalizedPhotoUrl.isNotEmpty;
    final cacheWidth = (radius * 2 * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(48, 1024)
        .toInt();
    return Semantics(
      image: true,
      label: hasPhoto ? 'عکس پروفایل' : 'آواتار پروفایل ${option.label}',
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
        child: ClipOval(
          child: hasPhoto
              ? Image.network(
                  normalizedPhotoUrl,
                  key: ValueKey<String>('profile-photo-$normalizedPhotoUrl'),
                  fit: BoxFit.cover,
                  width: radius * 2,
                  height: radius * 2,
                  cacheWidth: cacheWidth,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) =>
                      _AvatarFallback(option: option, iconSize: radius),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        _AvatarFallback(option: option, iconSize: radius),
                        Center(
                          child: SizedBox.square(
                            dimension: radius * 0.55,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                )
              : _AvatarFallback(option: option, iconSize: radius),
        ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.option, required this.iconSize});

  final LifeMateProfileAvatarOption option;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: option.backgroundColor,
      child: Center(
        child: Icon(option.icon, size: iconSize, color: option.foregroundColor),
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
      children: LifeMateProfileAvatars.options
          .map((option) {
            final selected = option.key == normalized;
            return Semantics(
              button: true,
              selected: selected,
              label: 'انتخاب آواتار ${option.label}',
              child: InkWell(
                key: ValueKey('profile-avatar-${option.key}'),
                onTap: onSelected == null
                    ? null
                    : () => onSelected!(option.key),
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
          })
          .toList(growable: false),
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
  Map<String, dynamic> _profile = const <String, dynamic>{};
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _profile =
        LifeMateProfileRefresh.peek(widget.apiClient) ??
        const <String, dynamic>{};
    LifeMateProfileRefresh.revision.addListener(_reload);
    _load();
  }

  void _reload() {
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final generation = ++_requestGeneration;
    try {
      final profile = await LifeMateProfileRefresh.loadProfile(
        widget.apiClient,
        force: force,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _profile = profile);
    } catch (error) {
      debugPrint('LifeMate profile avatar refresh failed: $error');
      // Keep the last good avatar visible during transient failures.
    }
  }

  @override
  void didUpdateWidget(covariant LifeMateCurrentUserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.apiClient, widget.apiClient)) {
      _profile =
          LifeMateProfileRefresh.peek(widget.apiClient) ??
          const <String, dynamic>{};
      _load();
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    LifeMateProfileRefresh.revision.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LifeMateProfileAvatar(
      avatarKey: _profile['avatarKey']?.toString(),
      photoUrl: _profile['profilePhotoUrl']?.toString(),
      radius: widget.radius,
    );
  }
}
