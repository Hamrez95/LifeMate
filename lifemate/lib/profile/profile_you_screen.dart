import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

class ProfileYouScreen extends StatefulWidget {
  const ProfileYouScreen({
    super.key,
    required this.apiClient,
    required this.isPersian,
    required this.onLocaleChanged,
  });

  final LifeMateApiClient apiClient;
  final bool isPersian;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<ProfileYouScreen> createState() => _ProfileYouScreenState();
}

class _ProfileYouScreenState extends State<ProfileYouScreen> {
  Map<String, dynamic>? _profile;
  Object? _error;
  bool _loading = true;
  bool _accountActionBusy = false;

  String t(String en, String fa) => widget.isPersian ? fa : en;

  @override
  void initState() {
    super.initState();
    final cached = LifeMateProfileRefresh.peek(widget.apiClient);
    if (cached != null) {
      _profile = cached;
      _loading = false;
    }
    _load(force: cached == null);
  }

  Future<void> _load({bool force = true}) async {
    if (_profile == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final profile = await LifeMateProfileRefresh.loadProfile(
        widget.apiClient,
        force: force,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_profile == null) {
      return _ErrorState(
        title: t('Profile is unavailable', 'پروفایل در دسترس نیست'),
        message: t(
          'Your profile could not be loaded. No local profile copy was created.',
          'پروفایل بارگذاری نشد و هیچ نسخه محلیِ جایگزین به‌عنوان مرجع ساخته نشده است.',
        ),
        retryLabel: t('Try again', 'تلاش دوباره'),
        onRetry: _load,
      );
    }

    final profile = _profile!;
    final displayName = _string(profile['displayName']);
    final locale = _string(profile['locale'], fallback: 'fa');
    final timeZone = _string(profile['timeZone'], fallback: 'Asia/Tehran');
    final avatarKey = LifeMateProfileAvatars.normalize(
      profile['avatarKey']?.toString(),
    );
    final photoUrl = profile['profilePhotoUrl']?.toString();

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView(
        key: const PageStorageKey<String>('lifemate-you'),
        padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _InlineNotice(
                icon: Icons.cloud_off_outlined,
                message: t(
                  'Showing the last safe profile copy. Pull to retry.',
                  'آخرین نسخه امن پروفایل نمایش داده می‌شود. برای تلاش دوباره صفحه را تازه کنید.',
                ),
              ),
            ),
          _IdentityCard(
            displayName: displayName.isEmpty
                ? t('Complete your profile', 'پروفایل خود را کامل کنید')
                : displayName,
            subtitle: t('Your global LifeMate profile', 'پروفایل سراسری LifeMate'),
            avatarKey: avatarKey,
            photoUrl: photoUrl,
            editLabel: t('Edit profile', 'ویرایش پروفایل'),
            onEdit: _openProfileEditor,
          ),
          const SizedBox(height: 18),
          _Section(
            title: t('Profile & preferences', 'پروفایل و ترجیحات'),
            children: [
              _ActionTile(
                icon: Icons.badge_outlined,
                title: t('Personal information', 'اطلاعات شخصی'),
                subtitle: displayName.isEmpty
                    ? t('Profile incomplete', 'پروفایل ناقص است')
                    : displayName,
                onTap: _openProfileEditor,
              ),
              _ActionTile(
                icon: Icons.language_rounded,
                title: t('Language', 'زبان'),
                subtitle: locale == 'fa' ? 'فارسی' : 'English',
                onTap: _openProfileEditor,
              ),
              _ActionTile(
                icon: Icons.schedule_rounded,
                title: t('Time zone', 'منطقه زمانی'),
                subtitle: timeZone,
                onTap: _openProfileEditor,
              ),
              _ActionTile(
                icon: Icons.accessibility_new_rounded,
                title: t('Accessibility', 'دسترسی‌پذیری'),
                subtitle: MediaQuery.disableAnimationsOf(context)
                    ? t('Reduced motion from system', 'کاهش حرکت از تنظیمات سیستم')
                    : t('System motion settings active', 'تنظیمات حرکت سیستم فعال است'),
                onTap: _showAccessibility,
              ),
              _ActionTile(
                icon: Icons.volume_off_outlined,
                title: t('Ambient audio', 'صدای محیط'),
                subtitle: t(
                  'Off — durable preference is not available yet',
                  'خاموش — ذخیره‌سازی پایدار این ترجیح هنوز آماده نیست',
                ),
                enabled: false,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: t('Membership & privacy', 'عضویت و حریم خصوصی'),
            children: [
              _ActionTile(
                icon: Icons.workspace_premium_outlined,
                title: t('Membership', 'عضویت'),
                subtitle: t(
                  'View canonical subscription status',
                  'مشاهده وضعیت رسمی اشتراک',
                ),
                onTap: _showSubscription,
              ),
              _ActionTile(
                icon: Icons.privacy_tip_outlined,
                title: t('Privacy', 'حریم خصوصی'),
                subtitle: t(
                  'Privacy and consent entry points',
                  'ورودی‌های حریم خصوصی و رضایت',
                ),
                onTap: _showPrivacy,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: t('Help & account', 'راهنما و حساب'),
            children: [
              _ActionTile(
                icon: Icons.support_agent_outlined,
                title: t('Support', 'پشتیبانی'),
                subtitle: t('Help and app information', 'راهنما و اطلاعات اپ'),
                onTap: _showSupport,
              ),
              _ActionTile(
                icon: Icons.download_outlined,
                title: t('Export account data', 'خروجی گرفتن از داده‌های حساب'),
                subtitle: t(
                  'Request your canonical account export',
                  'درخواست خروجی رسمی داده‌های حساب',
                ),
                onTap: _accountActionBusy ? null : _exportAccountData,
              ),
              _ActionTile(
                icon: Icons.delete_outline_rounded,
                title: t('Delete account', 'حذف حساب'),
                subtitle: t(
                  'Start the reviewed deletion request flow',
                  'شروع فرایند رسمی درخواست حذف حساب',
                ),
                destructive: true,
                onTap: _accountActionBusy ? null : _requestAccountDeletion,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openProfileEditor() async {
    final current = _profile;
    if (current == null) return;
    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => _ProfileEditorPage(
          apiClient: widget.apiClient,
          initialProfile: current,
          isPersian: widget.isPersian,
        ),
      ),
    );
    if (!mounted || updated == null) return;
    LifeMateProfileRefresh.cacheProfile(widget.apiClient, updated);
    final locale = _string(updated['locale'], fallback: 'fa');
    widget.onLocaleChanged(Locale(locale == 'fa' ? 'fa' : 'en'));
    setState(() {
      _profile = updated;
      _error = null;
    });
  }

  void _showAccessibility() {
    _showInfoSheet(
      icon: Icons.accessibility_new_rounded,
      title: t('Accessibility', 'دسترسی‌پذیری'),
      body: MediaQuery.disableAnimationsOf(context)
          ? t(
              'Your system requests reduced motion. LifeMate must reduce nonessential animation while keeping every action available.',
              'سیستم شما کاهش حرکت را درخواست کرده است. LifeMate باید انیمیشن‌های غیرضروری را کم کند و همه عملکردها را قابل دسترس نگه دارد.',
            )
          : t(
              'LifeMate follows the system motion setting. A durable in-app override will only be enabled after its reviewed preference adapter is available.',
              'LifeMate از تنظیمات حرکت سیستم پیروی می‌کند. گزینه پایدار داخل اپ فقط پس از آماده شدن adapter تأییدشده فعال می‌شود.',
            ),
    );
  }

  Future<void> _showSubscription() async {
    await _showAsyncSheet(
      title: t('Membership', 'عضویت'),
      loader: widget.apiClient.getSubscriptionSnapshot,
      summary: (value) {
        final status = _firstNonEmpty(value, const [
          'status',
          'subscriptionStatus',
          'state',
          'planStatus',
        ]);
        final plan = _firstNonEmpty(value, const [
          'planName',
          'plan',
          'offerName',
          'productName',
        ]);
        if (status == null && plan == null) {
          return t(
            'Your canonical subscription snapshot is available. Detailed Commerce presentation remains owned by the existing Subscription Center.',
            'وضعیت رسمی اشتراک دریافت شد. نمایش جزئیات Commerce همچنان متعلق به Subscription Center موجود است.',
          );
        }
        return [if (plan != null) plan, if (status != null) status].join(' • ');
      },
    );
  }

  void _showPrivacy() {
    _showInfoSheet(
      icon: Icons.privacy_tip_outlined,
      title: t('Privacy', 'حریم خصوصی'),
      body: t(
        'Relationship, consent and authorization are separate. LifeMate never treats a relationship or subscription as permission to access another person’s protected data.',
        'رابطه، رضایت و مجوز دسترسی از هم جدا هستند. LifeMate هیچ‌وقت رابطه یا اشتراک را به‌معنای اجازه دسترسی به داده محافظت‌شده فرد دیگر در نظر نمی‌گیرد.',
      ),
    );
  }

  void _showSupport() {
    _showInfoSheet(
      icon: Icons.support_agent_outlined,
      title: t('Support', 'پشتیبانی'),
      body: t(
        'LifeMate parent app version 0.1.0+1. Support entry is available without exposing health data, tokens or internal identifiers.',
        'نسخه اپ مادر LifeMate: 0.1.0+1. مسیر پشتیبانی بدون نمایش داده سلامت، توکن یا شناسه‌های داخلی در دسترس است.',
      ),
    );
  }

  Future<void> _exportAccountData() async {
    setState(() => _accountActionBusy = true);
    try {
      await widget.apiClient.exportAccountData();
      if (!mounted) return;
      _showInfoSheet(
        icon: Icons.check_circle_outline_rounded,
        title: t('Export ready', 'خروجی آماده است'),
        body: t(
          'The account export request completed successfully. Sensitive export contents are not rendered on this Profile page.',
          'درخواست خروجی حساب با موفقیت انجام شد. محتوای حساس خروجی در صفحه پروفایل نمایش داده نمی‌شود.',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showActionError();
    } finally {
      if (mounted) setState(() => _accountActionBusy = false);
    }
  }

  Future<void> _requestAccountDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Delete account?', 'حذف حساب؟')),
        content: Text(
          t(
            'This starts the reviewed server-side deletion request. It does not instantly erase data from this device only.',
            'این کار درخواست رسمی حذف حساب در سرور را شروع می‌کند و صرفاً داده‌های این دستگاه را پاک نمی‌کند.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('Cancel', 'انصراف')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('Request deletion', 'درخواست حذف')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _accountActionBusy = true);
    try {
      final status = await widget.apiClient.requestAccountDeletion();
      if (!mounted) return;
      _showInfoSheet(
        icon: Icons.mark_email_read_outlined,
        title: t('Deletion requested', 'درخواست حذف ثبت شد'),
        body: t(
          'Your server-side deletion request was recorded. Follow the canonical account flow for its current status.',
          'درخواست حذف حساب در سرور ثبت شد. وضعیت آن را از فرایند رسمی حساب دنبال کنید.',
        ),
      );
      status.toString();
    } catch (_) {
      if (!mounted) return;
      _showActionError();
    } finally {
      if (mounted) setState(() => _accountActionBusy = false);
    }
  }

  void _showActionError() {
    _showInfoSheet(
      icon: Icons.error_outline_rounded,
      title: t('Action failed', 'عملیات انجام نشد'),
      body: t(
        'Nothing was changed locally. Check your connection and try again.',
        'هیچ تغییری به‌صورت محلی اعمال نشد. اتصال را بررسی کنید و دوباره تلاش کنید.',
      ),
    );
  }

  Future<void> _showAsyncSheet({
    required String title,
    required Future<Map<String, dynamic>> Function() loader,
    required String Function(Map<String, dynamic>) summary,
  }) async {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _AsyncSheetBody(
        title: title,
        loader: loader,
        summary: summary,
        closeLabel: t('Close', 'بستن'),
        errorText: t(
          'Could not load the latest canonical state.',
          'آخرین وضعیت رسمی دریافت نشد.',
        ),
      ),
    );
  }

  void _showInfoSheet({
    required IconData icon,
    required String title,
    required String body,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(body),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t('Close', 'بستن')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _string(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String? _firstNonEmpty(
    Map<String, dynamic> value,
    List<String> keys,
  ) {
    for (final key in keys) {
      final candidate = value[key]?.toString().trim();
      if (candidate != null && candidate.isNotEmpty) return candidate;
    }
    return null;
  }
}

class _ProfileEditorPage extends StatefulWidget {
  const _ProfileEditorPage({
    required this.apiClient,
    required this.initialProfile,
    required this.isPersian,
  });

  final LifeMateApiClient apiClient;
  final Map<String, dynamic> initialProfile;
  final bool isPersian;

  @override
  State<_ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<_ProfileEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayName;
  late final TextEditingController _timeZone;
  late String _locale;
  late String _avatarKey;
  bool _saving = false;
  String? _error;

  String t(String en, String fa) => widget.isPersian ? fa : en;

  @override
  void initState() {
    super.initState();
    _displayName = TextEditingController(
      text: widget.initialProfile['displayName']?.toString() ?? '',
    );
    _timeZone = TextEditingController(
      text: widget.initialProfile['timeZone']?.toString() ?? 'Asia/Tehran',
    );
    final locale = widget.initialProfile['locale']?.toString();
    _locale = locale == 'en' ? 'en' : 'fa';
    _avatarKey = LifeMateProfileAvatars.normalize(
      widget.initialProfile['avatarKey']?.toString(),
    );
  }

  @override
  void dispose() {
    _displayName.dispose();
    _timeZone.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_isDirty || _saving) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t('Discard changes?', 'تغییرات حذف شوند؟')),
            content: Text(
              t(
                'Your unsaved profile edits will be lost.',
                'تغییرات ذخیره‌نشده پروفایل از بین می‌رود.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t('Keep editing', 'ادامه ویرایش')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t('Discard', 'حذف تغییرات')),
              ),
            ],
          ),
        ) ??
        false;
  }

  bool get _isDirty =>
      _displayName.text.trim() !=
          (widget.initialProfile['displayName']?.toString().trim() ?? '') ||
      _timeZone.text.trim() !=
          (widget.initialProfile['timeZone']?.toString().trim() ?? '') ||
      _locale != (widget.initialProfile['locale']?.toString() == 'en' ? 'en' : 'fa') ||
      _avatarKey !=
          LifeMateProfileAvatars.normalize(
            widget.initialProfile['avatarKey']?.toString(),
          );

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final version = widget.initialProfile['version'];
    if (version is! num) {
      setState(() => _error = t(
            'This profile cannot be safely updated because its version is missing.',
            'به‌دلیل نبود نسخه پروفایل، به‌روزرسانی امن ممکن نیست.',
          ));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.apiClient.updateCurrentProfile(
        version: version.toInt(),
        displayName: _displayName.text,
        phoneNumber: widget.initialProfile['phoneNumber']?.toString(),
        locale: _locale,
        timeZone: _timeZone.text,
        avatarKey: _avatarKey,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.statusCode == 409
            ? t(
                'Your profile changed elsewhere. Go back, refresh and try again.',
                'پروفایل در جای دیگری تغییر کرده است. برگردید، تازه‌سازی کنید و دوباره تلاش کنید.',
              )
            : t(
                'Profile could not be saved. No local copy became authoritative.',
                'پروفایل ذخیره نشد و هیچ نسخه محلی به‌عنوان مرجع در نظر گرفته نشد.',
              );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = t(
          'Profile could not be saved. Check your connection and retry.',
          'پروفایل ذخیره نشد. اتصال را بررسی کنید و دوباره تلاش کنید.',
        );
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_isDirty || _saving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _saving) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(t('Edit profile', 'ویرایش پروفایل'))),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
              children: [
                Center(
                  child: LifeMateProfileAvatar(
                    avatarKey: _avatarKey,
                    photoUrl: widget.initialProfile['profilePhotoUrl']?.toString(),
                    radius: 48,
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _displayName,
                  enabled: !_saving,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: t('Display name', 'نام نمایشی'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? t('Enter a display name', 'نام نمایشی را وارد کنید')
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _locale,
                  decoration: InputDecoration(
                    labelText: t('Language', 'زبان'),
                    border: const OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'fa', child: Text('فارسی')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _locale = value ?? _locale),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _timeZone,
                  enabled: !_saving,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: t('Time zone', 'منطقه زمانی'),
                    hintText: 'Asia/Tehran',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? t('Enter a time zone', 'منطقه زمانی را وارد کنید')
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),
                Text(
                  t('Avatar', 'آواتار'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                LifeMateAvatarPicker(
                  selectedKey: _avatarKey,
                  onSelected: _saving
                      ? null
                      : (value) => setState(() => _avatarKey = value),
                ),
                const SizedBox(height: 12),
                Text(
                  t(
                    'Avatar choices are cosmetic. Life stage and future skin-tone/family contracts remain separate from demographics.',
                    'انتخاب آواتار صرفاً ظاهری است. مرحله سنی و قراردادهای آینده خانواده/رنگ پوست از اطلاعات جمعیت‌شناختی جدا می‌مانند.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  _InlineNotice(icon: Icons.error_outline, message: _error!),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving || !_isDirty ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(t('Save changes', 'ذخیره تغییرات')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.displayName,
    required this.subtitle,
    required this.avatarKey,
    required this.photoUrl,
    required this.editLabel,
    required this.onEdit,
  });

  final String displayName;
  final String subtitle;
  final String avatarKey;
  final String? photoUrl;
  final String editLabel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            LifeMateProfileAvatar(
              avatarKey: avatarKey,
              photoUrl: photoUrl,
              radius: 36,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
            IconButton(
              tooltip: editLabel,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Card(child: Column(children: children)),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.enabled = true,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onTap != null;
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return ListTile(
      enabled: active,
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: Text(subtitle),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
      onTap: active ? onTap : null,
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_off_outlined, size: 52),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AsyncSheetBody extends StatelessWidget {
  const _AsyncSheetBody({
    required this.title,
    required this.loader,
    required this.summary,
    required this.closeLabel,
    required this.errorText,
  });

  final String title;
  final Future<Map<String, dynamic>> Function() loader;
  final String Function(Map<String, dynamic>) summary;
  final String closeLabel;
  final String errorText;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 24),
        child: FutureBuilder<Map<String, dynamic>>(
          future: loader(),
          builder: (context, snapshot) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                if (snapshot.connectionState != ConnectionState.done)
                  const Center(child: CircularProgressIndicator())
                else if (snapshot.hasError)
                  Text(errorText)
                else
                  Text(summary(snapshot.data ?? const <String, dynamic>{})),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(closeLabel),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
