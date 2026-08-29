import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/theme/app_style.dart';
import 'care_access_screen.dart';

class RelationshipInviteFlowScreen extends StatefulWidget {
  const RelationshipInviteFlowScreen({super.key});

  @override
  State<RelationshipInviteFlowScreen> createState() =>
      _RelationshipInviteFlowScreenState();
}

class _RelationshipInviteFlowScreenState
    extends State<RelationshipInviteFlowScreen> {
  final _phoneController = TextEditingController();
  final _nicknameController = TextEditingController();
  int _step = 0;
  String? _relationshipType;
  bool _consent = false;
  bool _saving = false;
  String? _error;

  static const _relationships = <(String, String, IconData)>[
    ('partner', 'پارتنر', Icons.favorite_rounded),
    ('family', 'خانواده', Icons.family_restroom_rounded),
    ('child', 'فرزند', Icons.child_care_rounded),
  ];

  @override
  void dispose() {
    _phoneController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  bool get _canContinue => switch (_step) {
        0 => normalizeIranianMobileE164(_phoneController.text) != null,
        1 => _relationshipType != null,
        2 => true,
        _ => _consent,
      };

  String get _relationshipLabel => _relationships
      .where((item) => item.$1 == _relationshipType)
      .map((item) => item.$2)
      .firstOrNull ?? 'رابطه مراقبتی';

  String get _toneDescription => switch (_relationshipType) {
        'partner' =>
          'LifeMate متن‌ها و اعلان‌های CareMate را صمیمی‌تر و متناسب با رابطه پارتنری نمایش می‌دهد.',
        'child' =>
          'LifeMate متن‌ها و اعلان‌های CareMate را متناسب با مراقبت از فرزند تنظیم می‌کند.',
        _ =>
          'LifeMate متن‌ها و اعلان‌های CareMate را متناسب با رابطه خانوادگی نمایش می‌دهد.',
      };

  void _next() {
    FocusScope.of(context).unfocus();
    if (!_canContinue) return;
    if (_step < 3) {
      setState(() {
        _step += 1;
        _error = null;
      });
    } else {
      _submit();
    }
  }

  void _back() {
    if (_saving) return;
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _step -= 1;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_saving || !_canContinue || _relationshipType == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = LifeMateCareRelationshipInvitationApi.fromEnvironment();
    try {
      final result = await api.createPhoneInvitation(
        phone: _phoneController.text,
        relationshipType: _relationshipType!,
        caregiverDisplayName: _nicknameController.text,
      );
      if (!mounted) return;
      await _showSuccess(result);
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          'invalid_contact' => 'شماره موبایل معتبر نیست.',
          'self_invitation_not_allowed' =>
            'نمی‌توانی شماره حساب خودت را به‌عنوان مراقب دعوت کنی.',
          'invitation_already_pending' =>
            'برای این شماره یک دعوت فعال وجود دارد.',
          _ => 'دعوت ساخته نشد. دوباره تلاش کن.',
        };
      });
    } finally {
      api.close();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showSuccess(Map<String, dynamic> result) async {
    final token = result['token']?.toString() ?? '';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('دعوت آماده شد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'دعوت $_relationshipLabel ساخته شد. نوع رابطه و نام دلخواهت همراه دعوت ذخیره شده و بعد از تأیید در CareMate استفاده می‌شود.',
              style: const TextStyle(height: 1.6),
            ),
            if (token.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'کد اتصال',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              SelectableText(
                token,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: token));
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('کد کپی شد.')),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('کپی کد'),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.of(context).pop();
            },
            child: const Text('تمام'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text('دعوت مراقب'),
          leading: IconButton(
            onPressed: _back,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Row(
                  children: List.generate(4, (index) {
                    return Expanded(
                      child: Container(
                        height: 4,
                        margin: EdgeInsetsDirectional.only(
                          end: index == 3 ? 0 : 6,
                        ),
                        decoration: BoxDecoration(
                          color: index <= _step
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: SingleChildScrollView(
                    key: ValueKey(_step),
                    padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
                    child: switch (_step) {
                      0 => _phoneStep(),
                      1 => _relationshipStep(),
                      2 => _nicknameStep(),
                      _ => _reviewStep(),
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: _saving || !_canContinue ? null : _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _step == 3 ? 'ساخت دعوت' : 'ادامه',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _phoneStep() => _section(
        icon: Icons.phone_iphone_rounded,
        title: 'شماره مراقب را وارد کن',
        subtitle:
            'این شماره فقط برای ساخت و اعتبارسنجی دعوت استفاده می‌شود.',
        child: TextField(
          key: const ValueKey('relationship-invite-phone'),
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          onChanged: (_) => setState(() {}),
          decoration: _inputDecoration(
            label: 'شماره موبایل',
            hint: '0912xxxxxxx',
            icon: Icons.phone_outlined,
          ),
        ),
      );

  Widget _relationshipStep() => _section(
        icon: Icons.people_alt_rounded,
        title: 'رابطه شما چیست؟',
        subtitle:
            'فقط سه گروه لحن داریم تا تجربه ساده، قابل‌فهم و قابل نگهداری بماند.',
        child: Column(
          children: [
            for (final item in _relationships) ...[
              _RelationshipCard(
                value: item.$1,
                title: item.$2,
                icon: item.$3,
                selected: _relationshipType == item.$1,
                onTap: () => setState(() => _relationshipType = item.$1),
              ),
              const SizedBox(height: 10),
            ],
            if (_relationshipType != null) ...[
              const SizedBox(height: 6),
              _InfoCard(
                icon: Icons.auto_awesome_rounded,
                text:
                    '$_toneDescription این انتخاب هیچ دسترسی جدیدی فعال نمی‌کند.',
              ),
            ],
          ],
        ),
      );

  Widget _nicknameStep() => _section(
        icon: Icons.badge_outlined,
        title: 'دوست داری چی صداش کنی؟',
        subtitle:
            'اختیاری است. اگر خالی بگذاری، نام رسمی پروفایلش نمایش داده می‌شود.',
        child: Column(
          children: [
            TextField(
              key: const ValueKey('relationship-invite-nickname'),
              controller: _nicknameController,
              maxLength: 80,
              decoration: _inputDecoration(
                label: 'نام دلخواه',
                hint: _relationshipType == 'family'
                    ? 'مثلاً مامان جون'
                    : _relationshipType == 'partner'
                        ? 'مثلاً عشقم'
                        : 'مثلاً پسرم',
                icon: Icons.favorite_border_rounded,
              ),
            ),
            const SizedBox(height: 8),
            const _InfoCard(
              icon: Icons.lock_outline_rounded,
              text:
                  'این نام فقط برای نمایش در حساب توست و نام رسمی پروفایل طرف مقابل را تغییر نمی‌دهد.',
            ),
          ],
        ),
      );

  Widget _reviewStep() => _section(
        icon: Icons.verified_user_outlined,
        title: 'مرور و تأیید دعوت',
        subtitle: 'قبل از ساخت دعوت، رابطه و محدوده دسترسی را بررسی کن.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReviewRow(label: 'شماره', value: _phoneController.text.trim()),
            _ReviewRow(label: 'نوع رابطه', value: _relationshipLabel),
            _ReviewRow(
              label: 'نام دلخواه',
              value: _nicknameController.text.trim().isEmpty
                  ? 'نام رسمی پروفایل'
                  : _nicknameController.text.trim(),
            ),
            const SizedBox(height: 12),
            const _InfoCard(
              icon: Icons.privacy_tip_outlined,
              text:
                  'نوع رابطه فقط لحن، نام نمایشی و اولویت ارائه را شخصی می‌کند. Women Health، Fertility، یادداشت‌های خصوصی و سایر داده‌های حساس فقط با مجوزهای مستقل قابل اشتراک هستند.',
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              key: const ValueKey('relationship-invite-consent'),
              contentPadding: EdgeInsets.zero,
              value: _consent,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) =>
                  setState(() => _consent = value ?? false),
              title: const Text(
                'اجازه می‌دهم این فرد پس از تأیید خودش، دسترسی پایه مراقبتی را دریافت کند. دسترسی‌های حساس جداگانه مدیریت می‌شوند.',
                style: TextStyle(fontSize: 12.5, height: 1.55),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CareAccessScreen(),
                ),
              ),
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('مدیریت مراقبان و دعوت‌های قبلی'),
            ),
          ],
        ),
      );

  Widget _section({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: AppColors.primary, size: 30),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w900,
              color: AppColors.darkBlue,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.65,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 26),
          child,
        ],
      );

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      );
}

class _RelationshipCard extends StatelessWidget {
  const _RelationshipCard({
    required this.value,
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String value;
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.10)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: ValueKey('relationship-type-$value'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.12),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F8F6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 12.5, height: 1.6),
              ),
            ),
          ],
        ),
      );
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
