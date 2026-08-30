import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/theme/app_style.dart';

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
  String? _relationshipType;
  bool _consent = false;
  bool _saving = false;
  String? _error;

  static const _relationships = <(String, String, IconData)>[
    ('partner', 'پارتنر', Icons.favorite_rounded),
    ('family', 'خانواده', Icons.family_restroom_rounded),
    ('child', 'فرزند', Icons.child_care_rounded),
    ('friend', 'دوست', Icons.people_alt_rounded),
    ('trusted_person', 'فرد مورد اعتماد', Icons.verified_user_rounded),
    ('doctor', 'پزشک', Icons.medical_services_rounded),
    ('nurse', 'پرستار', Icons.health_and_safety_rounded),
    ('professional_caregiver', 'مراقب حرفه‌ای', Icons.volunteer_activism_rounded),
    ('therapist_specialist', 'درمانگر / متخصص', Icons.psychology_alt_rounded),
    ('other', 'سایر', Icons.more_horiz_rounded),
  ];

  @override
  void dispose() {
    _phoneController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_saving &&
      normalizeIranianMobileE164(_phoneController.text) != null &&
      _relationshipType != null &&
      _consent;

  String get _relationshipLabel => _relationships
          .where((item) => item.$1 == _relationshipType)
          .map((item) => item.$2)
          .firstOrNull ??
      'رابطه مراقبتی';

  Future<void> _submit() async {
    if (!_canSubmit || _relationshipType == null) return;
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
            'نمی‌توانی شماره حساب خودت را دعوت کنی.',
          'invitation_already_pending' =>
            'برای این شماره یک دعوت فعال وجود دارد.',
          'invalid_relationship_presentation_type' =>
            'نوع رابطه پشتیبانی نمی‌شود. اپ را به‌روزرسانی کن.',
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
              'دعوت $_relationshipLabel ساخته شد. نوع رابطه فقط برای نمایش و لحن استفاده می‌شود و به‌تنهایی هیچ دسترسی سلامتی ایجاد نمی‌کند.',
              style: const TextStyle(height: 1.6),
            ),
            if (token.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('کد اتصال',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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
          title: const Text('دعوت فرد مورد اعتماد'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  children: [
                    const Text(
                      'چه کسی را می‌خواهی دعوت کنی؟',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'نوع رابطه فقط تجربه و لحن LifeMate را شخصی می‌کند؛ دسترسی به اطلاعات سلامتی همیشه جداگانه و با رضایت صریح کنترل می‌شود.',
                      style: TextStyle(
                        height: 1.6,
                        color: Colors.black.withValues(alpha: .62),
                      ),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'شماره موبایل',
                        hintText: '09xxxxxxxxx',
                        prefixIcon: const Icon(Icons.phone_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'نوع رابطه',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _relationships.map((item) {
                        final selected = _relationshipType == item.$1;
                        return ChoiceChip(
                          selected: selected,
                          avatar: Icon(item.$3, size: 18),
                          label: Text(item.$2),
                          onSelected: (_) =>
                              setState(() => _relationshipType = item.$1),
                        );
                      }).toList(growable: false),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _nicknameController,
                      maxLength: 80,
                      decoration: InputDecoration(
                        labelText: 'نام دلخواه (اختیاری)',
                        hintText: 'مثلاً مامان، دکتر احمدی، ریحانه…',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _consent,
                      onChanged: (value) =>
                          setState(() => _consent = value == true),
                      title: const Text('ارسال این دعوت را تأیید می‌کنم.'),
                      subtitle: const Text(
                        'این انتخاب به فرد دعوت‌شده دسترسی خودکار به پرونده، Women Health یا Fertility نمی‌دهد.',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'ساخت دعوت',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
