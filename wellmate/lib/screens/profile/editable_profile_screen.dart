import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';

class EditableProfileScreen extends StatefulWidget {
  const EditableProfileScreen({super.key});

  @override
  State<EditableProfileScreen> createState() => _EditableProfileScreenState();
}

class _EditableProfileScreenState extends State<EditableProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _timeZone = TextEditingController();

  Future<Map<String, dynamic>>? _profileFuture;
  Map<String, dynamic>? _profile;
  String _locale = 'fa';
  String _avatarKey = LifeMateProfileAvatars.defaultKey;
  String? _profilePhotoUrl;
  bool _saving = false;
  bool _photoBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _error = null;
      _profileFuture = context.read<LifeMateApiClient>().getCurrentProfile();
    });
  }

  void _applyProfile(Map<String, dynamic> profile) {
    _profile = profile;
    _displayName.text = profile['displayName']?.toString() ?? '';
    _email.text = profile['email']?.toString() ?? '';
    _phone.text = profile['phoneNumber']?.toString() ?? '';
    _locale = profile['locale']?.toString() == 'en' ? 'en' : 'fa';
    _timeZone.text = profile['timeZone']?.toString() ?? 'Asia/Tehran';
    _avatarKey = LifeMateProfileAvatars.normalize(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('عکس پروفایل ذخیره شد.')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('عکس پروفایل حذف شد.')));
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

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_saving || !_formKey.currentState!.validate()) return;
    final profile = _profile;
    final version = profile?['version'];
    if (profile == null || version is! int) {
      setState(
        () => _error = 'اطلاعات پروفایل کامل نیست. دوباره بارگذاری کنید.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await context
          .read<LifeMateApiClient>()
          .updateCurrentProfile(
            version: version,
            displayName: _displayName.text,
            phoneNumber: _phone.text,
            locale: _locale,
            timeZone: _timeZone.text,
            avatarKey: _avatarKey,
          );
      if (!mounted) return;
      setState(() => _applyProfile(updated));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اطلاعات پروفایل با موفقیت ذخیره شد.')),
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'stale_profile') {
        setState(() {
          _error =
              'پروفایل در دستگاه دیگری تغییر کرده است؛ اطلاعات تازه بارگذاری می‌شود.';
        });
        _profileFuture = context.read<LifeMateApiClient>().getCurrentProfile();
      } else if (error.isUnauthorized) {
        setState(() => _error = 'نشست شما منقضی شده است. دوباره وارد شوید.');
      } else if (error.statusCode == 0) {
        setState(
          () =>
              _error = 'اتصال برقرار نشد. اینترنت را بررسی و دوباره تلاش کنید.',
        );
      } else {
        setState(
          () => _error = 'ذخیره اطلاعات انجام نشد. ورودی‌ها را بررسی کنید.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'ذخیره اطلاعات انجام نشد. دوباره تلاش کنید.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _phone.dispose();
    _timeZone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('اطلاعات شخصی'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _profileFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _LoadError(onRetry: _reload);
            }
            final data = snapshot.data ?? const <String, dynamic>{};
            if (!identical(_profile, data) &&
                (_profile == null || _profile?['version'] != data['version'])) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _applyProfile(data));
              });
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
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
                            key: const ValueKey('profile-photo-preview'),
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
                          key: const ValueKey('profile-photo-camera'),
                          onPressed: _saving || _photoBusy
                              ? null
                              : () => _pickProfilePhoto(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_rounded),
                          label: const Text('دوربین'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('profile-photo-gallery'),
                          onPressed: _saving || _photoBusy
                              ? null
                              : () => _pickProfilePhoto(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_rounded),
                          label: const Text('گالری'),
                        ),
                        if (_profilePhotoUrl != null)
                          TextButton.icon(
                            key: const ValueKey('profile-photo-remove'),
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
                      key: const ValueKey('profile-avatar-picker'),
                      selectedKey: _avatarKey,
                      onSelected: _saving || _photoBusy
                          ? null
                          : (value) => setState(() => _avatarKey = value),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'عکس شخصی در فضای خصوصی نگهداری می‌شود. تا وقتی عکس وجود دارد، همان نمایش داده می‌شود؛ برای نمایش آواتار، عکس را حذف کنید.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    _ProfileField(
                      key: const ValueKey('profile-display-name'),
                      controller: _displayName,
                      label: 'نام نمایشی',
                      icon: Icons.badge_outlined,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final normalized = value?.trim() ?? '';
                        if (normalized.length < 2) {
                          return 'نام نمایشی را وارد کنید.';
                        }
                        if (normalized.length > 120) {
                          return 'نام نمایشی بیش از حد طولانی است.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    _ProfileField(
                      key: const ValueKey('profile-email'),
                      controller: _email,
                      label: 'ایمیل حساب',
                      icon: Icons.alternate_email_rounded,
                      enabled: false,
                      textDirection: TextDirection.ltr,
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'تغییر ایمیل نیازمند تأیید جداگانه حساب است و از این صفحه انجام نمی‌شود.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _ProfileField(
                      key: const ValueKey('profile-phone'),
                      controller: _phone,
                      label: 'شماره تماس اختیاری',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final compact = (value ?? '').trim().replaceAll(
                          RegExp(r'[\s()-]'),
                          '',
                        );
                        if (compact.isEmpty) return null;
                        if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(compact)) {
                          return 'شماره تماس معتبر وارد کنید.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'زبان نمایش',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      key: const ValueKey('profile-locale'),
                      segments: const [
                        ButtonSegment(value: 'fa', label: Text('فارسی')),
                        ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {_locale},
                      onSelectionChanged: _saving
                          ? null
                          : (selection) =>
                                setState(() => _locale = selection.single),
                    ),
                    const SizedBox(height: 18),
                    _ProfileField(
                      key: const ValueKey('profile-time-zone'),
                      controller: _timeZone,
                      label: 'منطقه زمانی',
                      icon: Icons.schedule_rounded,
                      textDirection: TextDirection.ltr,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _save(),
                      validator: (value) => (value?.trim().isNotEmpty ?? false)
                          ? null
                          : 'منطقه زمانی را وارد کنید.',
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'نمونه: Asia/Tehran یا Europe/Berlin',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        key: const ValueKey('profile-save'),
                        onPressed: _saving || _profile == null ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _saving ? 'در حال ذخیره...' : 'ذخیره اطلاعات',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.keyboardType,
    this.textDirection,
    this.textInputAction,
    this.validator,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextDirection? textDirection;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      textDirection: textDirection,
      textInputAction: textInputAction,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: enabled ? Colors.white : const Color(0xFFF1F3F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: AppColors.primaryBlue,
            ),
            const SizedBox(height: 12),
            const Text(
              'اطلاعات پروفایل دریافت نشد.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('تلاش دوباره'),
            ),
          ],
        ),
      ),
    );
  }
}
