import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'profile_theme.dart';

class LifeMateSharedEditableProfileScreen extends StatefulWidget {
  const LifeMateSharedEditableProfileScreen({
    super.key,
    required this.apiClient,
    required this.theme,
    required this.fontFamily,
    required this.keyPrefix,
  });

  final LifeMateApiClient apiClient;
  final LifeMateProfileThemeData theme;
  final String fontFamily;
  final String keyPrefix;

  @override
  State<LifeMateSharedEditableProfileScreen> createState() =>
      _LifeMateSharedEditableProfileScreenState();
}

class _LifeMateSharedEditableProfileScreenState
    extends State<LifeMateSharedEditableProfileScreen> {
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

  String keyName(String suffix) => '${widget.keyPrefix}-$suffix';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _error = null;
      _profileFuture = widget.apiClient.getCurrentProfile();
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

  void _notice(
    LifeMateNoticeType type, {
    required String title,
    required String message,
  }) {
    if (!mounted) return;
    LifeMateNotice.show(context, type: type, title: title, message: message);
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
      final updated = await widget.apiClient.uploadCurrentProfilePhoto(
        bytes: bytes,
        contentType: contentType,
      );
      if (!mounted) return;
      setState(() {
        _applyProfile(updated);
        _profileFuture = Future.value(updated);
      });
      LifeMateProfileRefresh.notifyChanged();
      _notice(
        LifeMateNoticeType.success,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'عکس ذخیره شد',
            en: "The photo is saved",
          ),
          en: "The photo is saved",
        ),
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'عکس پروفایل ذخیره شد.',
            en: "Profile picture saved.",
          ),
          en: "Profile picture saved.",
        ),
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          'profile_photo_too_large' => LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'حجم عکس باید کمتر از ۳ مگابایت باشد.',
              en: "The size of the photo must be less than 3 MB.",
            ),
            en: "The size of the photo must be less than 3 MB.",
          ),
          'invalid_profile_photo' => LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'فرمت عکس پشتیبانی نمی‌شود.',
              en: "The image format is not supported.",
            ),
            en: "The image format is not supported.",
          ),
          _ => LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ذخیره عکس انجام نشد. دوباره تلاش کنید.',
              en: "Failed to save photo. Try again.",
            ),
            en: "Failed to save photo. Try again.",
          ),
        };
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message == 'profile_photo_too_large'
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'حجم عکس باید کمتر از ۳ مگابایت باشد.',
                  en: "The size of the photo must be less than 3 MB.",
                ),
                en: "The size of the photo must be less than 3 MB.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'فقط عکس JPEG، PNG یا WebP انتخاب کنید.',
                  en: "Choose JPEG, PNG or WebP image only.",
                ),
                en: "Choose JPEG, PNG or WebP image only.",
              );
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'خواندن یا ارسال عکس انجام نشد.',
              en: "Failed to read or send photo.",
            ),
            en: "Failed to read or send photo.",
          ),
        );
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
      final updated = await widget.apiClient.deleteCurrentProfilePhoto();
      if (!mounted) return;
      setState(() {
        _applyProfile(updated);
        _profileFuture = Future.value(updated);
      });
      LifeMateProfileRefresh.notifyChanged();
      _notice(
        LifeMateNoticeType.success,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'عکس حذف شد',
            en: "Photo removed",
          ),
          en: "Photo removed",
        ),
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'از این پس آواتار انتخابی شما نمایش داده می‌شود.',
            en: "From now on, your selected avatar will be displayed.",
          ),
          en: "From now on, your selected avatar will be displayed.",
        ),
      );
    } on LifeMateApiException {
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'حذف عکس انجام نشد. دوباره تلاش کنید.',
              en: "The photo could not be deleted. Try again.",
            ),
            en: "The photo could not be deleted. Try again.",
          ),
        );
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
        () => _error = LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'اطلاعات پروفایل کامل نیست. دوباره بارگذاری کنید.',
            en: "Profile information is not complete. Reload.",
          ),
          en: "Profile information is not complete. Reload.",
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.apiClient.updateCurrentProfile(
        version: version,
        displayName: _displayName.text,
        phoneNumber: _phone.text,
        locale: _locale,
        timeZone: _timeZone.text,
        avatarKey: _avatarKey,
      );
      if (!mounted) return;
      setState(() => _applyProfile(updated));
      LifeMateProfileRefresh.notifyChanged();
      _notice(
        LifeMateNoticeType.success,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'پروفایل ذخیره شد',
            en: "Profile saved",
          ),
          en: "Profile saved",
        ),
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'اطلاعات پروفایل با موفقیت ذخیره شد.',
            en: "Profile information saved successfully.",
          ),
          en: "Profile information saved successfully.",
        ),
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'stale_profile') {
        setState(() {
          _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'پروفایل در دستگاه دیگری تغییر کرده است؛ اطلاعات تازه بارگذاری می‌شود.',
              en: "The profile has been changed on another device; New information is being loaded.",
            ),
            en: "The profile has been changed on another device; New information is being loaded.",
          );
          _profileFuture = widget.apiClient.getCurrentProfile();
        });
      } else if (error.isUnauthorized) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'نشست شما منقضی شده است. دوباره وارد شوید.',
              en: "Your session has expired. Sign in again.",
            ),
            en: "Your session has expired. Sign in again.",
          ),
        );
      } else if (error.statusCode == 0) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'اتصال برقرار نشد. اینترنت را بررسی و دوباره تلاش کنید.',
              en: "Connection failed. Check the internet and try again.",
            ),
            en: "Connection failed. Check the internet and try again.",
          ),
        );
      } else {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ذخیره اطلاعات انجام نشد. ورودی‌ها را بررسی کنید.',
              en: "Data could not be saved. Check the entries.",
            ),
            en: "Data could not be saved. Check the entries.",
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ذخیره اطلاعات انجام نشد. دوباره تلاش کنید.',
              en: "Data could not be saved. Try again.",
            ),
            en: "Data could not be saved. Try again.",
          ),
        );
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
    final textStyle = TextStyle(fontFamily: widget.fontFamily);
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(
          context,
        ).colorScheme.copyWith(primary: widget.theme.accent),
        textTheme: Theme.of(context).textTheme.apply(
          fontFamily: widget.fontFamily,
          bodyColor: widget.theme.titleColor,
          displayColor: widget.theme.titleColor,
        ),
      ),
      child: Scaffold(
        key: ValueKey('lifemate-shared-editable-profile-layout'),
        backgroundColor: widget.theme.background,
        appBar: AppBar(
          title: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'اطلاعات شخصی',
                en: "Personal information",
              ),
              en: "Personal information",
            ),
            style: textStyle,
          ),
          backgroundColor: widget.theme.background,
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _profileFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Center(
                  child: CircularProgressIndicator(color: widget.theme.accent),
                );
              }
              if (snapshot.hasError) {
                return _LoadError(
                  onRetry: _reload,
                  accent: widget.theme.accent,
                  fontFamily: widget.fontFamily,
                );
              }
              final data = snapshot.data ?? const <String, dynamic>{};
              if (!identical(_profile, data) &&
                  (_profile == null ||
                      _profile?['version'] != data['version'])) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _applyProfile(data));
                });
              }

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'عکس یا آواتار پروفایل',
                            en: "Profile picture or avatar",
                          ),
                          en: "Profile picture or avatar",
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: widget.fontFamily,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 12),
                      Center(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            LifeMateProfileAvatar(
                              key: ValueKey(keyName('photo-preview')),
                              avatarKey: _avatarKey,
                              photoUrl: _profilePhotoUrl,
                              radius: 52,
                            ),
                            if (_photoBusy)
                              Positioned.fill(
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
                      SizedBox(height: 14),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            key: ValueKey(keyName('photo-camera')),
                            onPressed: _saving || _photoBusy
                                ? null
                                : () => _pickProfilePhoto(ImageSource.camera),
                            icon: Icon(Icons.photo_camera_rounded),
                            label: Text(
                              LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'دوربین',
                                  en: "camera",
                                ),
                                en: "camera",
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            key: ValueKey(keyName('photo-gallery')),
                            onPressed: _saving || _photoBusy
                                ? null
                                : () => _pickProfilePhoto(ImageSource.gallery),
                            icon: Icon(Icons.photo_library_rounded),
                            label: Text(
                              LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'گالری',
                                  en: "Gallery",
                                ),
                                en: "Gallery",
                              ),
                            ),
                          ),
                          if (_profilePhotoUrl != null)
                            TextButton.icon(
                              key: ValueKey(keyName('photo-remove')),
                              onPressed: _saving || _photoBusy
                                  ? null
                                  : _removeProfilePhoto,
                              icon: Icon(Icons.delete_outline_rounded),
                              label: Text(
                                LifeMateRuntimeLocale.select(
                                  fa: LifeMateRuntimeLocale.select(
                                    fa: 'حذف عکس',
                                    en: "Delete photo",
                                  ),
                                  en: "Delete photo",
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 18),
                      Divider(),
                      SizedBox(height: 10),
                      Text(
                        LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'یا یک آواتار آماده انتخاب کنید',
                            en: "Or choose a ready-made avatar",
                          ),
                          en: "Or choose a ready-made avatar",
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: widget.fontFamily,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 12),
                      LifeMateAvatarPicker(
                        key: ValueKey(keyName('avatar-picker')),
                        selectedKey: _avatarKey,
                        onSelected: _saving || _photoBusy
                            ? null
                            : (value) => setState(() => _avatarKey = value),
                      ),
                      SizedBox(height: 10),
                      Text(
                        LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'عکس شخصی در فضای خصوصی نگهداری می‌شود. تا وقتی عکس وجود دارد، همان نمایش داده می‌شود؛ برای نمایش آواتار، عکس را حذف کنید.',
                            en: "Personal photo is kept in private space. As long as the photo exists, it will be displayed; Remove photo to show avatar.",
                          ),
                          en: "Personal photo is kept in private space. As long as the photo exists, it will be displayed; Remove photo to show avatar.",
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: widget.fontFamily,
                          color: widget.theme.secondaryText,
                        ),
                      ),
                      SizedBox(height: 24),
                      _ProfileField(
                        key: ValueKey(keyName('display-name')),
                        controller: _displayName,
                        label: LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'نام نمایشی',
                            en: "display name",
                          ),
                          en: "display name",
                        ),
                        icon: Icons.badge_outlined,
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          final normalized = value?.trim() ?? '';
                          if (normalized.length < 2) {
                            return LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'نام نمایشی را وارد کنید.',
                                en: "Enter a display name.",
                              ),
                              en: "Enter a display name.",
                            );
                          }
                          if (normalized.length > 120) {
                            return LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'نام نمایشی بیش از حد طولانی است.',
                                en: "Display name is too long.",
                              ),
                              en: "Display name is too long.",
                            );
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 14),
                      _ProfileField(
                        key: ValueKey(keyName('email')),
                        controller: _email,
                        label: LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'ایمیل حساب',
                            en: "Account email",
                          ),
                          en: "Account email",
                        ),
                        icon: Icons.alternate_email_rounded,
                        enabled: false,
                        textDirection: TextDirection.ltr,
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'تغییر ایمیل نیازمند تأیید جداگانه حساب است و از این صفحه انجام نمی‌شود.',
                              en: "Changing email requires separate account verification and cannot be done from this page.",
                            ),
                            en: "Changing email requires separate account verification and cannot be done from this page.",
                          ),
                          style: TextStyle(
                            fontFamily: widget.fontFamily,
                            fontSize: 12,
                            color: widget.theme.secondaryText,
                          ),
                        ),
                      ),
                      SizedBox(height: 14),
                      _ProfileField(
                        key: ValueKey(keyName('phone')),
                        controller: _phone,
                        label: LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'شماره تماس اختیاری',
                            en: "Optional contact number",
                          ),
                          en: "Optional contact number",
                        ),
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
                            return LifeMateRuntimeLocale.select(
                              fa: 'شماره تماس معتبر وارد کنید.',
                              en: 'Enter a valid phone number.',
                            );
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 18),
                      Text(
                        LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'زبان نمایش',
                            en: "Display language",
                          ),
                          en: "Display language",
                        ),
                        style: TextStyle(
                          fontFamily: widget.fontFamily,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 8),
                      SegmentedButton<String>(
                        key: ValueKey(keyName('locale')),
                        segments: [
                          ButtonSegment(
                            value: 'fa',
                            label: Text(
                              LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'فارسی',
                                  en: "Farsi",
                                ),
                                en: "Farsi",
                              ),
                            ),
                          ),
                          ButtonSegment(value: 'en', label: Text('English')),
                        ],
                        selected: {_locale},
                        onSelectionChanged: _saving
                            ? null
                            : (selection) =>
                                  setState(() => _locale = selection.single),
                      ),
                      SizedBox(height: 18),
                      _ProfileField(
                        key: ValueKey(keyName('time-zone')),
                        controller: _timeZone,
                        label: LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'منطقه زمانی',
                            en: "time zone",
                          ),
                          en: "time zone",
                        ),
                        icon: Icons.schedule_rounded,
                        textDirection: TextDirection.ltr,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _save(),
                        validator: (value) =>
                            (value?.trim().isNotEmpty ?? false)
                            ? null
                            : LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'منطقه زمانی را وارد کنید.',
                                  en: "Enter the time zone.",
                                ),
                                en: "Enter the time zone.",
                              ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'نمونه: Asia/Tehran یا Europe/Berlin',
                              en: "Example: Asia/Tehran or Europe/Berlin",
                            ),
                            en: "Example: Asia/Tehran or Europe/Berlin",
                          ),
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontFamily: widget.fontFamily,
                            fontSize: 12,
                            color: widget.theme.secondaryText,
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                fontFamily: widget.fontFamily,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: 22),
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          key: ValueKey(keyName('save')),
                          style: FilledButton.styleFrom(
                            backgroundColor: widget.theme.accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _saving || _profile == null ? null : _save,
                          icon: _saving
                              ? SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(Icons.save_outlined),
                          label: Text(
                            _saving
                                ? LifeMateRuntimeLocale.select(
                                    fa: LifeMateRuntimeLocale.select(
                                      fa: 'در حال ذخیره...',
                                      en: "Saving...",
                                    ),
                                    en: "Saving...",
                                  )
                                : LifeMateRuntimeLocale.select(
                                    fa: LifeMateRuntimeLocale.select(
                                      fa: 'ذخیره اطلاعات',
                                      en: "Save information",
                                    ),
                                    en: "Save information",
                                  ),
                            style: TextStyle(fontFamily: widget.fontFamily),
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
      inputFormatters: const [LifeMateLocaleDigitInputFormatter()],
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
  const _LoadError({
    required this.onRetry,
    required this.accent,
    required this.fontFamily,
  });

  final VoidCallback onRetry;
  final Color accent;
  final String fontFamily;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: accent),
            SizedBox(height: 12),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'اطلاعات پروفایل دریافت نشد.',
                  en: "Profile information not received.",
                ),
                en: "Profile information not received.",
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: fontFamily),
            ),
            SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: accent),
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'تلاش دوباره',
                    en: "Try again",
                  ),
                  en: "Try again",
                ),
                style: TextStyle(fontFamily: fontFamily),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
