import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/string_extensions.dart';
import 'care_access_settings_screen.dart';
import 'care_pairing_qr_dialog.dart';

class CareAccessScreen extends StatefulWidget {
  const CareAccessScreen({super.key});

  @override
  State<CareAccessScreen> createState() => _CareAccessScreenState();
}

class _CareAccessScreenState extends State<CareAccessScreen> {
  bool _loading = true;
  bool _creating = false;
  String? _error;
  String? _currentUserId;
  List<Map<String, dynamic>> _invitations = const [];
  List<Map<String, dynamic>> _relationships = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final api = context.read<LifeMateApiClient>();
      final results = await Future.wait([
        api.getCurrentUser(),
        api.getOutgoingCareInvitations(),
        api.getCareRelationships(),
      ]);
      final current = results[0] as Map<String, dynamic>;
      final currentUserId = (current['user'] as Map<String, dynamic>?)?['id']
          ?.toString();
      final relationships = (results[2] as List<Map<String, dynamic>>)
          .where(
            (relationship) =>
                relationship['patientUserId']?.toString() == currentUserId,
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _currentUserId = currentUserId;
        _invitations = results[1] as List<Map<String, dynamic>>;
        _relationships = relationships;
      });
    } catch (error) {
      debugPrint('WellMate care access refresh failed: $error');
      if (mounted) {
        setState(() => _error = 'اطلاعات مراقبان دریافت نشد.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _notice({
    required LifeMateNoticeType type,
    required String title,
    required String message,
  }) {
    if (!mounted) return;
    LifeMateNotice.show(context, type: type, title: title, message: message);
  }

  Future<void> _createInvitation() async {
    final emailController = TextEditingController();
    var confirmed = false;
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('دعوت مراقب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(
                  labelText: 'ایمیل مراقب',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: confirmed,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (value) =>
                    setDialogState(() => confirmed = value ?? false),
                title: const Text(
                  'اجازه می‌دهم این فرد وضعیت برنامه و مصرف داروهای من را ببیند. هر زمان بخواهم می‌توانم دسترسی را قطع کنم.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: confirmed && _looksLikeEmail(emailController.text)
                  ? () => Navigator.pop(
                      dialogContext,
                      emailController.text.trim(),
                    )
                  : null,
              child: const Text('ساخت دعوت'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
    if (email == null || !mounted) return;

    setState(() => _creating = true);
    try {
      final invitation = await context
          .read<LifeMateApiClient>()
          .createCareInvitation(email: email);
      if (!mounted) return;
      await _showInvitationToken(
        invitation['token']?.toString() ?? '',
        invitation['expiresAtUtc']?.toString(),
      );
      await _refresh();
    } on LifeMateApiException catch (error) {
      final message = switch (error.code) {
        'invitation_already_pending' =>
          'برای این ایمیل یک دعوت فعال وجود دارد.',
        'self_invitation_not_allowed' =>
          'نمی‌توانید حساب خودتان را به‌عنوان مراقب دعوت کنید.',
        _ => 'دعوت ساخته نشد. دوباره تلاش کنید.',
      };
      _notice(
        type: LifeMateNoticeType.error,
        title: 'دعوت ساخته نشد',
        message: message,
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _createQrInvitation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اتصال با QR'),
        content: const Text(
          'با ادامه، یک QR یک‌بارمصرف می‌سازید که فقط ۱۰ دقیقه معتبر است. آن را فقط به مراقب مورد اعتماد نشان دهید.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ساخت QR امن'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _creating = true);
    try {
      final invitation = await context
          .read<LifeMateApiClient>()
          .createQrCareInvitation();
      if (!mounted) return;
      await showCarePairingQrDialog(
        context: context,
        token: invitation['token']?.toString() ?? '',
        expiresAtUtc: invitation['expiresAtUtc']?.toString(),
      );
      await _refresh();
    } on LifeMateApiException catch (error) {
      _notice(
        type: LifeMateNoticeType.error,
        title: 'QR ساخته نشد',
        message: error.code == 'patient_consent_required'
            ? 'برای اتصال، تأیید رضایت بیمار لازم است.'
            : 'ساخت QR انجام نشد. دوباره تلاش کنید.',
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _showInvitationToken(String token, String? expiresAt) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('کد دعوت آماده است'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'این کد محرمانه را فقط برای همان مراقب ارسال کنید. کد پس از ۷۲ ساعت منقضی می‌شود.',
            ),
            const SizedBox(height: 16),
            SelectableText(
              token,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (expiresAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'انقضا: ${expiresAt.toPersianDigit(Localizations.localeOf(context).languageCode == 'fa')}',
              ),
            ],
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: token));
              if (dialogContext.mounted) {
                LifeMateNotice.show(
                  dialogContext,
                  type: LifeMateNoticeType.success,
                  title: 'کد کپی شد',
                  message: 'کد دعوت در کلیپ‌بورد قرار گرفت.',
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('کپی کد'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('تمام'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAccessSettings(Map<String, dynamic> relationship) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CareAccessSettingsScreen(relationship: relationship),
      ),
    );
    await _refresh();
  }

  Future<void> _revokeRelationship(Map<String, dynamic> relationship) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('قطع دسترسی مراقب؟'),
        content: Text(
          'دسترسی ${relationship['caregiverDisplayName'] ?? 'این مراقب'} فوراً قطع می‌شود.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('قطع دسترسی'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<LifeMateApiClient>().revokeCareRelationship(
        relationshipId: relationship['id'].toString(),
      );
      if (!mounted) return;
      _notice(
        type: LifeMateNoticeType.success,
        title: 'دسترسی قطع شد',
        message: 'همه دسترسی‌های این مراقب فوراً متوقف شد.',
      );
      await _refresh();
    } catch (error) {
      debugPrint('WellMate revoke caregiver failed: $error');
      _notice(
        type: LifeMateNoticeType.error,
        title: 'قطع دسترسی انجام نشد',
        message: 'دوباره تلاش کنید یا اتصال را بررسی کنید.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final active = _relationships
        .where((relationship) => relationship['status'] == 'active')
        .toList(growable: false);
    final pending = _invitations
        .where((invitation) => invitation['status'] == 'pending')
        .toList(growable: false);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'مراقبان من',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'care-qr-invite',
            onPressed: _creating ? null : _createQrInvitation,
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('اتصال با QR'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'care-email-invite',
            onPressed: _creating ? null : _createInvitation,
            icon: _creating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.alternate_email_rounded),
            label: const Text('دعوت با ایمیل'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            const _PrivacyNotice(),
            const SizedBox(height: 20),
            if (_loading && _currentUserId == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _ErrorState(message: _error!, onRetry: _refresh)
            else ...[
              Text(
                'مراقبان فعال (${active.length.toString().toPersianDigit(isPersian)})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (active.isEmpty)
                const _EmptySection(message: 'هنوز مراقب فعالی ندارید.')
              else
                ...active.map(
                  (relationship) => Card(
                    elevation: 0,
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.health_and_safety_rounded),
                      ),
                      title: Text(
                        (relationship['caregiverDisplayName']?.toString() ??
                                'مراقب')
                            .toPersianDigit(isPersian),
                      ),
                      subtitle: Text(
                        relationship['canViewWomenCalendar'] == true
                            ? 'دارو و تقویم بانوان'
                            : 'دسترسی فعال به وضعیت مصرف دارو',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'تنظیمات دسترسی',
                            onPressed: () => _openAccessSettings(relationship),
                            icon: const Icon(Icons.tune_rounded),
                          ),
                          IconButton(
                            tooltip: 'قطع دسترسی',
                            onPressed: () => _revokeRelationship(relationship),
                            icon: const Icon(Icons.link_off_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'دعوت‌های در انتظار (${pending.length.toString().toPersianDigit(isPersian)})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (pending.isEmpty)
                const _EmptySection(message: 'دعوت در انتظاری وجود ندارد.')
              else
                ...pending.map(
                  (invitation) => Card(
                    elevation: 0,
                    child: ListTile(
                      leading: const Icon(Icons.schedule_send_rounded),
                      title: Text(
                        invitation['contactHint']?.toString() ?? 'مراقب',
                      ),
                      subtitle: const Text(
                        'برای امنیت، کد دعوت دوباره نمایش داده نمی‌شود.',
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static bool _looksLikeEmail(String value) {
    final email = value.trim();
    final at = email.indexOf('@');
    return at > 0 && at < email.length - 3 && email.contains('.', at);
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_outlined, color: AppColors.primary),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'کنترل دسترسی همیشه با شماست. فقط مراقبان فعال می‌توانند وضعیت برنامه و مصرف دارو را ببینند.',
          ),
        ),
      ],
    ),
  );
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Center(child: Text(message)),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      children: [
        Icon(
          Icons.cloud_off_rounded,
          color: Theme.of(context).colorScheme.error,
          size: 48,
        ),
        const SizedBox(height: 10),
        Text(message),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('تلاش دوباره')),
      ],
    ),
  );
}
