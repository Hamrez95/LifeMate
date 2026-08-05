from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, value: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(value, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    value = read(path)
    if new in value:
        return
    if old not in value:
        raise RuntimeError(f"Expected marker not found in {path}: {old[:140]!r}")
    write(path, value.replace(old, new, 1))


# Shared avatar widget renders a short-lived signed photo and falls back to the
# reviewed allow-listed avatar catalog on loading or delivery failure.
write(
    "packages/lifemate_client/lib/src/profile_avatar.dart",
    """import 'package:flutter/material.dart';

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
    final hasPhoto = normalizedPhotoUrl != null && normalizedPhotoUrl.isNotEmpty;
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
                  key: const ValueKey('profile-photo-image'),
                  fit: BoxFit.cover,
                  width: radius * 2,
                  height: radius * 2,
                  errorBuilder: (_, _, _) => _AvatarFallback(
                    option: option,
                    iconSize: radius,
                  ),
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
        child: Icon(
          option.icon,
          size: iconSize,
          color: option.foregroundColor,
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
    _future = widget.apiClient.getCurrentProfile();
  }

  @override
  void didUpdateWidget(covariant LifeMateCurrentUserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.apiClient, widget.apiClient)) {
      _future = widget.apiClient.getCurrentProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        final profile = snapshot.data ?? const <String, dynamic>{};
        return LifeMateProfileAvatar(
          avatarKey: profile['avatarKey']?.toString(),
          photoUrl: profile['profilePhotoUrl']?.toString(),
          radius: widget.radius,
        );
      },
    );
  }
}
""",
)

# Binary profile-photo client endpoints.
replace_once(
    "packages/lifemate_client/lib/src/lifemate_api_client.dart",
    "import 'dart:math';\n",
    "import 'dart:math';\nimport 'dart:typed_data';\n",
)
replace_once(
    "packages/lifemate_client/lib/src/lifemate_api_client.dart",
    """  Future<Map<String, dynamic>> getCurrentProfile() async =>
      _asObject(await _send('GET', '/api/v1/me/profile', retryable: true));

""",
    """  Future<Map<String, dynamic>> getCurrentProfile() async =>
      _asObject(await _send('GET', '/api/v1/me/profile', retryable: true));

  Future<Map<String, dynamic>> uploadCurrentProfilePhoto({
    required Uint8List bytes,
    required String contentType,
  }) async => _asObject(
    await _sendBinary(
      'PUT',
      '/api/v1/me/profile/photo',
      bytes: bytes,
      contentType: contentType,
    ),
  );

  Future<Map<String, dynamic>> deleteCurrentProfilePhoto() async =>
      _asObject(await _send('DELETE', '/api/v1/me/profile/photo'));

""",
)
replace_once(
    "packages/lifemate_client/lib/src/lifemate_api_client.dart",
    """  Future<dynamic> _send(
    String method,""",
    """  Future<dynamic> _sendBinary(
    String method,
    String path, {
    required Uint8List bytes,
    required String contentType,
  }) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }
    if (method != 'PUT') {
      throw ArgumentError.value(method, 'method', 'Unsupported binary method');
    }
    try {
      final response = await _http
          .put(
            _resolve(path),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
              'Content-Type': contentType,
            },
            body: bytes,
          )
          .timeout(_requestTimeout);
      return _decodeResponse(response);
    } on TimeoutException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'LifeMate request timed out.',
      );
    } on http.ClientException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'LifeMate service is unavailable.',
      );
    }
  }

  Future<dynamic> _send(
    String method,""",
)

write(
    "packages/lifemate_client/test/profile_photo_api_client_test.dart",
    """import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('profile photo upload sends authenticated raw bytes and media type', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': 'profile-1',
            'avatarKey': 'person_blue',
            'profilePhotoUrl': 'https://storage.example.test/signed',
            'version': 2,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final bytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0x00]);

    final result = await api.uploadCurrentProfilePhoto(
      bytes: bytes,
      contentType: 'image/jpeg',
    );

    expect(observed.method, 'PUT');
    expect(observed.url.path, '/api/v1/me/profile/photo');
    expect(observed.headers['authorization'], 'Bearer access-token');
    expect(observed.headers['content-type'], 'image/jpeg');
    expect(observed.bodyBytes, bytes);
    expect(result['profilePhotoUrl'], isNotNull);
  });
}
""",
)

# Add image_picker to both applications.
for pubspec in ["wellmate/pubspec.yaml", "caremate/pubspec.yaml"]:
    value = read(pubspec)
    if "  image_picker:" not in value:
        value = value.replace(
            "  lifemate_client:\n    path: ../packages/lifemate_client\n",
            "  lifemate_client:\n    path: ../packages/lifemate_client\n  image_picker: ^1.1.2\n",
            1,
        )
        write(pubspec, value)

# Shared editing behavior, specialized only for each app's visual colors.
def patch_editor(path: str, caremate: bool) -> None:
    value = read(path)
    if "_pickProfilePhoto" in value:
        return
    secondary = "AppColors.secondaryText" if caremate else "AppColors.textSecondary"
    picker_key = "care-profile" if caremate else "profile"
    value = value.replace(
        "import 'package:flutter/material.dart';\n",
        "import 'dart:typed_data';\n\nimport 'package:flutter/material.dart';\nimport 'package:image_picker/image_picker.dart';\n",
        1,
    )
    value = value.replace(
        "  String _avatarKey = LifeMateProfileAvatars.defaultKey;\n  bool _saving = false;\n",
        "  String _avatarKey = LifeMateProfileAvatars.defaultKey;\n  String? _profilePhotoUrl;\n  bool _saving = false;\n  bool _photoBusy = false;\n",
        1,
    )
    value = value.replace(
        """    _avatarKey = LifeMateProfileAvatars.normalize(
      profile['avatarKey']?.toString(),
    );
  }

  Future<void> _save() async {""",
        """    _avatarKey = LifeMateProfileAvatars.normalize(
      profile['avatarKey']?.toString(),
    );
    final photo = profile['profilePhotoUrl']?.toString().trim();
    _profilePhotoUrl = photo == null || photo.isEmpty ? null : photo;
  }

  Future<void> _pickProfilePhoto(ImageSource source) async {
    if (_saving || _photoBusy) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _photoBusy = true;
      _error = null;
    });
    try {
      final bytes = await picked.readAsBytes();
      final contentType = _detectProfilePhotoType(bytes);
      if (contentType == null) {
        throw const FormatException('unsupported_profile_photo');
      }
      if (bytes.length > 3 * 1024 * 1024) {
        throw const FormatException('profile_photo_too_large');
      }
      final updated = await context
          .read<LifeMateApiClient>()
          .uploadCurrentProfilePhoto(bytes: bytes, contentType: contentType);
      if (!mounted) return;
      setState(() {
        _applyProfile(updated);
        _profileFuture = Future.value(updated);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('عکس پروفایل ذخیره شد.')),
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          'profile_photo_too_large' => 'حجم عکس باید کمتر از ۳ مگابایت باشد.',
          'invalid_profile_photo' => 'فرمت عکس پشتیبانی نمی‌شود.',
          _ => 'ذخیره عکس انجام نشد. دوباره تلاش کنید.',
        };
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message == 'profile_photo_too_large'
            ? 'حجم عکس باید کمتر از ۳ مگابایت باشد.'
            : 'فقط عکس JPEG، PNG یا WebP انتخاب کنید.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'خواندن یا ارسال عکس انجام نشد.');
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removeProfilePhoto() async {
    if (_saving || _photoBusy || _profilePhotoUrl == null) return;
    setState(() {
      _photoBusy = true;
      _error = null;
    });
    try {
      final updated = await context
          .read<LifeMateApiClient>()
          .deleteCurrentProfilePhoto();
      if (!mounted) return;
      setState(() {
        _applyProfile(updated);
        _profileFuture = Future.value(updated);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('عکس پروفایل حذف شد.')),
      );
    } on LifeMateApiException {
      if (mounted) {
        setState(() => _error = 'حذف عکس انجام نشد. دوباره تلاش کنید.');
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  static String? _detectProfilePhotoType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }

  Future<void> _save() async {""",
        1,
    )
    old_ui = """                    const Text(
                      'آواتار پروفایل',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    LifeMateAvatarPicker(
                      key: const ValueKey('%s-avatar-picker'),
                      selectedKey: _avatarKey,
                      onSelected: _saving
                          ? null
                          : (value) => setState(() => _avatarKey = value),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'آواتار انتخابی در حساب ذخیره می‌شود و در هر دو اپ نمایش داده خواهد شد.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: %s),
                    ),
                    const SizedBox(height: 24),
""" % (picker_key, secondary)
    new_ui = """                    const Text(
                      'عکس یا آواتار پروفایل',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          LifeMateProfileAvatar(
                            key: const ValueKey('%s-photo-preview'),
                            avatarKey: _avatarKey,
                            photoUrl: _profilePhotoUrl,
                            radius: 52,
                          ),
                          if (_photoBusy)
                            const Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0x66FFFFFF),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('%s-photo-camera'),
                          onPressed: _saving || _photoBusy
                              ? null
                              : () => _pickProfilePhoto(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_rounded),
                          label: const Text('دوربین'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('%s-photo-gallery'),
                          onPressed: _saving || _photoBusy
                              ? null
                              : () => _pickProfilePhoto(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_rounded),
                          label: const Text('گالری'),
                        ),
                        if (_profilePhotoUrl != null)
                          TextButton.icon(
                            key: const ValueKey('%s-photo-remove'),
                            onPressed: _saving || _photoBusy
                                ? null
                                : _removeProfilePhoto,
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('حذف عکس'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Divider(),
                    const SizedBox(height: 10),
                    const Text(
                      'یا یک آواتار آماده انتخاب کنید',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    LifeMateAvatarPicker(
                      key: const ValueKey('%s-avatar-picker'),
                      selectedKey: _avatarKey,
                      onSelected: _saving || _photoBusy
                          ? null
                          : (value) => setState(() => _avatarKey = value),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'عکس شخصی در فضای خصوصی نگهداری می‌شود. تا وقتی عکس وجود دارد، همان نمایش داده می‌شود؛ برای نمایش آواتار، عکس را حذف کنید.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: %s),
                    ),
                    const SizedBox(height: 24),
""" % (
        picker_key,
        picker_key,
        picker_key,
        picker_key,
        picker_key,
        secondary,
    )
    if old_ui not in value:
        raise RuntimeError(f"Profile avatar UI marker missing in {path}")
    value = value.replace(old_ui, new_ui, 1)
    write(path, value)


patch_editor("wellmate/lib/screens/profile/editable_profile_screen.dart", False)
patch_editor("caremate/lib/screens/editable_profile_screen.dart", True)

# Full profile pages display the signed photo immediately after returning from edit.
for path in [
    "wellmate/lib/screens/profile/profile_screen.dart",
    "caremate/lib/screens/profile_screen.dart",
]:
    value = read(path)
    marker = "avatarKey: profile['avatarKey']?.toString(),\n"
    addition = (
        marker
        + "                      photoUrl: profile['profilePhotoUrl']?.toString(),\n"
    )
    if "photoUrl: profile['profilePhotoUrl']" not in value:
        if marker not in value:
            raise RuntimeError(f"Profile avatar marker missing in {path}")
        value = value.replace(marker, addition, 1)
        write(path, value)

# Camera permission and iOS privacy descriptions. Android photo library uses the
# system picker and does not request broad storage access.
for manifest in [
    "wellmate/android/app/src/main/AndroidManifest.xml",
    "caremate/android/app/src/main/AndroidManifest.xml",
]:
    value = read(manifest)
    permission = '<uses-permission android:name="android.permission.CAMERA" />'
    if permission not in value:
        marker = "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">"
        if marker not in value:
            raise RuntimeError(f"Android manifest marker missing in {manifest}")
        value = value.replace(marker, marker + "\n    " + permission, 1)
        write(manifest, value)

for plist in ["wellmate/ios/Runner/Info.plist", "caremate/ios/Runner/Info.plist"]:
    target = ROOT / plist
    if not target.exists():
        continue
    value = read(plist)
    if "NSCameraUsageDescription" not in value:
        marker = "</dict>"
        addition = """\t<key>NSCameraUsageDescription</key>
\t<string>برای گرفتن عکس پروفایل به دوربین دسترسی نیاز است.</string>
\t<key>NSPhotoLibraryUsageDescription</key>
\t<string>برای انتخاب عکس پروفایل به گالری دسترسی نیاز است.</string>
"""
        if marker not in value:
            raise RuntimeError(f"Info.plist marker missing in {plist}")
        value = value.replace(marker, addition + marker, 1)
        write(plist, value)

print("Profile-photo Flutter upload, selection and rendering materialized.")
