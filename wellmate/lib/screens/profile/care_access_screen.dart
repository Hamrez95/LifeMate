import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/string_extensions.dart';
import 'care_access_settings_screen.dart';
import 'incoming_care_request_card.dart';
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
  List<Map<String, dynamic>> _incomingRequests = const [];
  final Set<String> _cancellingInvitationIds = <String>{};
  final Set<String> _respondingCareRequestIds = <String>{};

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
        api.getIncomingCareRequests(),
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
        _incomingRequests = results[3] as List<Map<String, dynamic>>;
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

  Future<void> _respondToCareRequest(
    Map<String, dynamic> request, {
    required bool accept,
  }) async {
    final id = request['id']?.toString();
    if (id == null || id.isEmpty || _respondingCareRequestIds.contains(id)) {
      return;
    }
    if (accept) {
      final name = request['requesterDisplayName']?.toString() ?? 'این فرد';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('تأیید درخواست مراقبت'),
          content: Text(
            'با تأیید، $name به‌عنوان مراقب شما فعال می‌شود. دسترسی‌های حساس مثل تقویم بانوان و مدیریت پرونده سلامت همچنان جداگانه و فقط با اجازه خودتان فعال می‌شوند.',
            style: const TextStyle(height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('فعلاً نه'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('تأیید مراقب'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _respondingCareRequestIds.add(id));
    try {
      await context.read<LifeMateApiClient>().respondCareRequest(
        requestId: id,
        accept: accept,
      );
      if (!mounted) return;
      _notice(
        type: LifeMateNoticeType.success,
        title: accept ? 'مراقب اضافه شد' : 'درخواست رد شد',
        message: accept
            ? 'ارتباط مراقبتی فعال شد؛ حالا می‌توانید دسترسی‌هایش را تنظیم کنید.'
            : 'این درخواست دیگر فعال نیست.',
      );
      await _refresh();
    } on LifeMateApiException catch (error) {
      _notice(
        type: LifeMateNoticeType.error,
        title: 'انجام نشد',
        message: switch (error.code) {
          'care_request_expired' => 'این درخواست منقضی شده است.',
          'care_request_not_pending' => 'این درخواست قبلاً بررسی شده است.',
          _ => 'دوباره تلاش کنید یا اتصال اینترنت را بررسی کنید.',
        },
      );
    } finally {
      if (mounted) setState(() => _respondingCareRequestIds.remove(id));
    }
  }

  Future<void> _openInviteSheet() async {
    final action = await showModalBottomSheet<_InviteAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _InviteOptionsSheet(),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _InviteAction.email:
        await _createInvitation();
        break;
      case _InviteAction.qr:
        await _createQrInvitation();
        break;
    }
  }

  Future<void> _createInvitation() async {
    final emailController = TextEditingController();
    var confirmed = false;
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
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
                decoration: InputDecoration(
                  labelText: 'ایمیل مراقب',
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  filled: true,
                  fillColor: const Color(0xFFF6FAF8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
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
                  style: TextStyle(height: 1.55, fontSize: 12.5),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('اتصال با QR'),
        content: const Text(
          'با ادامه، یک QR یک‌بارمصرف می‌سازید که فقط ۱۰ دقیقه معتبر است. آن را فقط به مراقب مورد اعتماد نشان دهید.',
          style: TextStyle(height: 1.6),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('کد دعوت آماده است'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'این کد محرمانه را فقط برای همان مراقب ارسال کنید. کد پس از ۷۲ ساعت منقضی می‌شود.',
              style: TextStyle(height: 1.55),
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
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: CareAccessSettingsScreen(relationship: relationship),
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _revokeRelationship(Map<String, dynamic> relationship) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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

  Future<void> _cancelInvitation(Map<String, dynamic> invitation) async {
    final id = invitation['id']?.toString();
    if (id == null || id.isEmpty || _cancellingInvitationIds.contains(id)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('لغو دعوت؟'),
        content: Text(
          'دعوت ${invitation['contactHint'] ?? ''} دیگر قابل استفاده نخواهد بود.',
          style: const TextStyle(height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('لغو دعوت'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancellingInvitationIds.add(id));
    try {
      await context.read<LifeMateApiClient>().revokeCareInvitation(
        invitationId: id,
      );
      if (!mounted) return;
      _notice(
        type: LifeMateNoticeType.success,
        title: 'دعوت لغو شد',
        message: 'این دعوت دیگر معتبر نیست.',
      );
      await _refresh();
    } catch (error) {
      debugPrint('WellMate revoke invitation failed: $error');
      _notice(
        type: LifeMateNoticeType.error,
        title: 'لغو دعوت انجام نشد',
        message: 'دوباره تلاش کنید.',
      );
    } finally {
      if (mounted) setState(() => _cancellingInvitationIds.remove(id));
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
    final incoming = _incomingRequests
        .where((request) => request['status'] == 'pending')
        .toList(growable: false);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'مراقبان من',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
          children: [
            const _CareAccessHero(),
            const SizedBox(height: 14),
            _AddCaregiverCard(
              loading: _creating,
              onTap: _creating ? null : _openInviteSheet,
            ),
            const SizedBox(height: 24),
            _SectionHeader(
              title: 'درخواست‌های جدید',
              count: incoming.length,
              isPersian: isPersian,
            ),
            const SizedBox(height: 10),
            if (incoming.isEmpty)
              const _NoIncomingRequestsCard()
            else
              ...incoming.map(
                (request) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: IncomingCareRequestCard(
                    request: request,
                    loading: _respondingCareRequestIds.contains(
                      request['id']?.toString(),
                    ),
                    onAccept: () =>
                        _respondToCareRequest(request, accept: true),
                    onReject: () =>
                        _respondToCareRequest(request, accept: false),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            _SectionHeader(
              title: 'مراقبان فعال',
              count: active.length,
              isPersian: isPersian,
            ),
            const SizedBox(height: 10),
            if (_loading && _currentUserId == null)
              const _LoadingCard()
            else if (_error != null)
              _ErrorState(message: _error!, onRetry: _refresh)
            else if (active.isEmpty)
              const _CaregiverEmptyCard()
            else
              ...active.map(
                (relationship) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CaregiverCard(
                    relationship: relationship,
                    onSettings: () => _openAccessSettings(relationship),
                    onRevoke: () => _revokeRelationship(relationship),
                  ),
                ),
              ),
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 14),
              _SectionHeader(
                title: 'دعوت‌های ارسال‌شده',
                count: pending.length,
                isPersian: isPersian,
              ),
              const SizedBox(height: 10),
              ...pending.map(
                (invitation) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PendingInvitationCard(
                    invitation: invitation,
                    isPersian: isPersian,
                    loading: _cancellingInvitationIds.contains(
                      invitation['id']?.toString(),
                    ),
                    onCancel: () => _cancelInvitation(invitation),
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

enum _InviteAction { email, qr }

class _CareAccessHero extends StatelessWidget {
  const _CareAccessHero();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFFE9F8F2), Color(0xFFF6FBF8)],
      ),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Colors.white),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D27493D),
          blurRadius: 22,
          offset: Offset(0, 9),
        ),
      ],
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroIcon(),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تیم مراقبتت، زیر کنترل خودت',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.darkBlue,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'مراقب اضافه کن، دسترسی هر نفر را جدا تنظیم کن و هر زمان خواستی ارتباط را قطع کن.',
                style: TextStyle(
                  height: 1.6,
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 52,
    decoration: const BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
    ),
    child: const Icon(
      Icons.diversity_1_rounded,
      color: AppColors.primary,
      size: 28,
    ),
  );
}

class _AddCaregiverCard extends StatelessWidget {
  const _AddCaregiverCard({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D27493D),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: AppColors.primary,
                    ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'افزودن مراقب جدید',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.darkBlue,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'دعوت با ایمیل یا اتصال امن با QR',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: Colors.black26),
          ],
        ),
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.isPersian,
  });

  final String title;
  final int count;
  final bool isPersian;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: AppColors.darkBlue,
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          count.toString().toPersianDigit(isPersian),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    ],
  );
}

class _NoIncomingRequestsCard extends StatelessWidget {
  const _NoIncomingRequestsCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE4EEE8)),
    ),
    child: const Row(
      children: [
        CircleAvatar(
          radius: 21,
          backgroundColor: Color(0xFFF0F6F3),
          child: Icon(
            Icons.inbox_outlined,
            color: AppColors.textSecondary,
            size: 21,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'درخواست جدیدی برای بررسی ندارید. اگر کسی از CareMate درخواست مراقبت بفرستد، نام و تصویرش همین‌جا نمایش داده می‌شود.',
            style: TextStyle(
              height: 1.55,
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _CaregiverCard extends StatelessWidget {
  const _CaregiverCard({
    required this.relationship,
    required this.onSettings,
    required this.onRevoke,
  });

  final Map<String, dynamic> relationship;
  final VoidCallback onSettings;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final rawName = relationship['caregiverDisplayName']?.toString().trim();
    final name = rawName == null || rawName.isEmpty ? 'مراقب' : rawName;
    final canSeeWomenCalendar = relationship['canViewWomenCalendar'] == true;
    final rawPhotoUrl = relationship['caregiverProfilePhotoUrl']
        ?.toString()
        .trim();
    final photoUrl = rawPhotoUrl == null || rawPhotoUrl.isEmpty
        ? null
        : rawPhotoUrl;
    final rawAvatarKey = relationship['caregiverAvatarKey']?.toString().trim();
    final avatarKey = rawAvatarKey == null || rawAvatarKey.isEmpty
        ? 'caregiver_teal'
        : rawAvatarKey;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D27493D),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              LifeMateProfileAvatar(
                key: ValueKey('caregiver-profile-avatar-${relationship['id']}'),
                avatarKey: avatarKey,
                photoUrl: photoUrl,
                radius: 29,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'مراقب فعال شما',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'تنظیمات دسترسی',
                  onPressed: onSettings,
                  icon: const Icon(
                    Icons.settings_rounded,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              const _AccessChip(icon: Icons.medication_rounded, label: 'دارو'),
              if (canSeeWomenCalendar) ...[
                const SizedBox(width: 7),
                const _AccessChip(
                  icon: Icons.calendar_month_rounded,
                  label: 'تقویم بانوان',
                ),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: onRevoke,
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: const Text('قطع ارتباط'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB34A4A),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccessChip extends StatelessWidget {
  const _AccessChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFF2F8F5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _PendingInvitationCard extends StatelessWidget {
  const _PendingInvitationCard({
    required this.invitation,
    required this.isPersian,
    required this.loading,
    required this.onCancel,
  });

  final Map<String, dynamic> invitation;
  final bool isPersian;
  final bool loading;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final contact = invitation['contactHint']?.toString() ?? 'مراقب';
    final expiresAt = invitation['expiresAtUtc']?.toString();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.schedule_send_rounded,
              color: Color(0xFFD6932C),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  expiresAt == null
                      ? 'در انتظار پذیرش'
                      : 'در انتظار پذیرش • انقضا ${expiresAt.toPersianDigit(isPersian)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'لغو دعوت',
            onPressed: loading ? null : onCancel,
            icon: loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.close_rounded, color: Color(0xFFB34A4A)),
          ),
        ],
      ),
    );
  }
}

class _CaregiverEmptyCard extends StatelessWidget {
  const _CaregiverEmptyCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
    ),
    child: const Column(
      children: [
        Icon(Icons.group_add_rounded, color: AppColors.primary, size: 42),
        SizedBox(height: 10),
        Text(
          'هنوز مراقب فعالی ندارید',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: AppColors.darkBlue,
          ),
        ),
        SizedBox(height: 5),
        Text(
          'از کارت بالا یک نفر را با ایمیل یا QR دعوت کنید.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 120,
    child: Center(child: CircularProgressIndicator()),
  );
}

class _InviteOptionsSheet extends StatelessWidget {
  const _InviteOptionsSheet();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFD7E0DB),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const Text(
            'افزودن مراقب جدید',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: AppColors.darkBlue,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'روش امنی که برای شما راحت‌تر است انتخاب کنید.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          _InviteOptionTile(
            icon: Icons.qr_code_2_rounded,
            title: 'اتصال با QR',
            subtitle: 'برای وقتی که مراقب کنار شماست',
            onTap: () => Navigator.pop(context, _InviteAction.qr),
          ),
          const SizedBox(height: 10),
          _InviteOptionTile(
            icon: Icons.alternate_email_rounded,
            title: 'دعوت با ایمیل',
            subtitle: 'ارسال کد دعوت برای مراقب مورد اعتماد',
            onTap: () => Navigator.pop(context, _InviteAction.email),
          ),
        ],
      ),
    ),
  );
}

class _InviteOptionTile extends StatelessWidget {
  const _InviteOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF6FAF8),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: Colors.black26),
          ],
        ),
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      children: [
        Icon(
          Icons.cloud_off_rounded,
          color: Theme.of(context).colorScheme.error,
          size: 42,
        ),
        const SizedBox(height: 10),
        Text(message),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('تلاش دوباره')),
      ],
    ),
  );
}
