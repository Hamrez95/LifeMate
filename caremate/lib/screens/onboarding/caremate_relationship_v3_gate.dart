import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

import '../pairing/care_invitation_scanner_screen.dart';

enum _CareMateGatePhase {
  loading,
  relationshipHint,
  pairingMethod,
  manualCode,
  connecting,
  pending,
  accepted,
  revoked,
  error,
}

class CareMateRelationshipV3Gate extends StatefulWidget {
  const CareMateRelationshipV3Gate({
    super.key,
    required this.apiClient,
    required this.child,
  });

  final LifeMateApiClient apiClient;
  final Widget child;

  @override
  State<CareMateRelationshipV3Gate> createState() =>
      _CareMateRelationshipV3GateState();
}

class _CareMateRelationshipV3GateState
    extends State<CareMateRelationshipV3Gate> {
  final _theme = LifeMateOnboardingTheme.careMate;
  final _manualController = TextEditingController();

  _CareMateGatePhase _phase = _CareMateGatePhase.loading;
  String? _relationshipHint;
  String? _message;
  Map<String, dynamic>? _activeRelationship;
  Map<String, bool> _privacyScopes = const <String, bool>{};
  bool _showAcceptedOnce = false;

  bool get _isPersian => LifeMateRuntimeLocale.isPersian;

  @override
  void initState() {
    super.initState();
    _loadRelationshipState();
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _loadRelationshipState({bool afterAccept = false}) async {
    if (mounted) {
      setState(() {
        _phase = _CareMateGatePhase.loading;
        _message = null;
      });
    }
    try {
      final values = await Future.wait<dynamic>([
        widget.apiClient.getCurrentUser(),
        widget.apiClient.getCareRelationships(),
      ]);
      final current = values[0] as Map<String, dynamic>;
      final relationships = values[1] as List<Map<String, dynamic>>;
      final currentUser =
          current['user'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final currentUserId = currentUser['id']?.toString();

      Map<String, dynamic>? active;
      Map<String, dynamic>? pending;
      Map<String, dynamic>? revoked;
      for (final relationship in relationships) {
        final caregiverId = relationship['caregiverUserId']?.toString();
        if (currentUserId != null &&
            caregiverId != null &&
            caregiverId.isNotEmpty &&
            caregiverId != currentUserId) {
          continue;
        }
        final status = relationship['status']?.toString().toLowerCase();
        if (status == 'active') {
          active ??= relationship;
        } else if (status == 'pending' || status == 'requested') {
          pending ??= relationship;
        } else if (status == 'revoked') {
          revoked ??= relationship;
        }
      }

      if (!mounted) return;
      if (active != null) {
        final scopes = await _loadExactPrivacyScopes(active);
        if (!mounted) return;
        setState(() {
          _activeRelationship = active;
          _privacyScopes = scopes;
          _showAcceptedOnce = afterAccept;
          _phase = afterAccept
              ? _CareMateGatePhase.accepted
              : _CareMateGatePhase.loading;
        });
        return;
      }
      setState(() {
        _activeRelationship = null;
        _privacyScopes = const <String, bool>{};
        _phase = pending != null
            ? _CareMateGatePhase.pending
            : revoked != null
            ? _CareMateGatePhase.revoked
            : _CareMateGatePhase.relationshipHint;
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _CareMateGatePhase.error;
        _message = _friendly(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _CareMateGatePhase.error;
        _message = LifeMateRuntimeLocale.select(
          fa: 'وضعیت اتصال CareMate دریافت نشد. دوباره تلاش کن.',
          en: 'CareMate connection status could not be loaded. Try again.',
        );
      });
    }
  }

  Future<Map<String, bool>> _loadExactPrivacyScopes(
    Map<String, dynamic> relationship,
  ) async {
    if (relationship['canViewWomenCalendar'] != true) {
      return const <String, bool>{
        'viewFertilityEstimate': false,
        'receiveFertilityNotifications': false,
      };
    }
    final patientUserId = relationship['patientUserId']?.toString();
    if (patientUserId == null || patientUserId.isEmpty) {
      return const <String, bool>{
        'viewFertilityEstimate': false,
        'receiveFertilityNotifications': false,
      };
    }
    try {
      final summary = await widget.apiClient.getCareRecipientWomenCalendar(
        patientUserId: patientUserId,
      );
      final raw = summary['privacyScopes'];
      if (raw is! Map) return const <String, bool>{};
      return Map<String, bool>.fromEntries(
        raw.entries.map(
          (entry) => MapEntry(entry.key.toString(), entry.value == true),
        ),
      );
    } on LifeMateApiException catch (error) {
      if (error.statusCode == 403 ||
          error.code == 'women_calendar_access_denied') {
        return const <String, bool>{
          'viewFertilityEstimate': false,
          'receiveFertilityNotifications': false,
        };
      }
      return const <String, bool>{};
    }
  }

  Future<void> _scanQr() async {
    final token = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const CareInvitationScannerScreen(),
      ),
    );
    if (token == null || token.trim().isEmpty || !mounted) return;
    await _accept(token);
  }

  Future<void> _accept(String token) async {
    if (token.trim().isEmpty) {
      setState(() {
        _message = LifeMateRuntimeLocale.select(
          fa: 'کد دعوت را وارد کن.',
          en: 'Enter the invitation code.',
        );
      });
      return;
    }
    setState(() {
      _phase = _CareMateGatePhase.connecting;
      _message = null;
    });
    try {
      await widget.apiClient.acceptCareInvitation(token: token.trim());
      if (!mounted) return;
      await _loadRelationshipState(afterAccept: true);
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _CareMateGatePhase.manualCode;
        _message = _friendly(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _CareMateGatePhase.manualCode;
        _message = LifeMateRuntimeLocale.select(
          fa: 'اتصال انجام نشد. اینترنت را بررسی و دوباره تلاش کن.',
          en: 'Connection failed. Check your internet and try again.',
        );
      });
    }
  }

  String _friendly(LifeMateApiException error) {
    return switch (error.code) {
      'invitation_expired' => LifeMateRuntimeLocale.select(
          fa: 'این دعوت منقضی شده است. از صاحب حساب یک دعوت تازه بگیر.',
          en: 'This invitation has expired. Ask the account owner for a new one.',
        ),
      'invitation_not_found' => LifeMateRuntimeLocale.select(
          fa: 'این کد دعوت معتبر نیست.',
          en: 'This invitation code is invalid.',
        ),
      'invitation_contact_mismatch' => LifeMateRuntimeLocale.select(
          fa: 'این دعوت برای حساب دیگری صادر شده است.',
          en: 'This invitation belongs to another account.',
        ),
      'self_invitation_not_allowed' => LifeMateRuntimeLocale.select(
          fa: 'نمی‌توانی دعوت مراقبت حساب خودت را بپذیری.',
          en: 'You cannot accept your own care invitation.',
        ),
      'invitation_not_pending' => LifeMateRuntimeLocale.select(
          fa: 'این دعوت قبلاً استفاده یا لغو شده است. دعوت تازه لازم است.',
          en: 'This invitation was already used or revoked. A new invitation is required.',
        ),
      _ => LifeMateRuntimeLocale.select(
          fa: 'دعوت پذیرفته نشد. دوباره تلاش کن.',
          en: 'The invitation could not be accepted. Try again.',
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_activeRelationship != null && !_showAcceptedOnce) {
      return widget.child;
    }

    return Directionality(
      textDirection: _isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: switch (_phase) {
        _CareMateGatePhase.loading => _loading(),
        _CareMateGatePhase.relationshipHint => _relationshipHintScreen(),
        _CareMateGatePhase.pairingMethod => _pairingMethodScreen(),
        _CareMateGatePhase.manualCode => _manualCodeScreen(),
        _CareMateGatePhase.connecting => _connectingScreen(),
        _CareMateGatePhase.pending => _pendingScreen(),
        _CareMateGatePhase.accepted => _acceptedScreen(),
        _CareMateGatePhase.revoked => _revokedScreen(),
        _CareMateGatePhase.error => _errorScreen(),
      },
    );
  }

  Widget _loading() => _scaffold(
        title: 'CareMate',
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'در حال بررسی', en: 'Checking'),
        primaryBusy: true,
        body: _centerQuestion(
          Icons.shield_outlined,
          LifeMateRuntimeLocale.select(
            fa: 'وضعیت دسترسی را از سرور بررسی می‌کنیم',
            en: 'Checking server-authoritative access',
          ),
          LifeMateRuntimeLocale.select(
            fa: 'هیچ اطلاعات سلامت تا تأیید رابطه نمایش داده نمی‌شود.',
            en: 'No health data is shown before the relationship is authorized.',
          ),
        ),
      );

  Widget _relationshipHintScreen() => _scaffold(
        title: LifeMateRuntimeLocale.select(fa: 'شروع CareMate', en: 'Start CareMate'),
        progress: 0.25,
        progressLabel: '1/4',
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'ادامه', en: 'Continue'),
        onPrimary: _relationshipHint == null
            ? null
            : () => setState(() => _phase = _CareMateGatePhase.pairingMethod),
        body: Column(
          children: [
            const Spacer(),
            _question(
              Icons.people_alt_outlined,
              LifeMateRuntimeLocale.select(
                fa: 'برای چه کسی CareMate را استفاده می‌کنی؟',
                en: 'Who are you using CareMate for?',
              ),
              LifeMateRuntimeLocale.select(
                fa: 'این انتخاب فقط متن و ظاهر را شخصی می‌کند و هیچ دسترسی‌ای نمی‌دهد.',
                en: 'This only personalizes copy and never grants access.',
              ),
            ),
            const SizedBox(height: 18),
            _hintCard('parent', Icons.elderly_outlined,
                LifeMateRuntimeLocale.select(fa: 'پدر یا مادر', en: 'Parent')),
            const SizedBox(height: 8),
            _hintCard('partner', Icons.favorite_border_rounded,
                LifeMateRuntimeLocale.select(fa: 'همسر یا شریک زندگی', en: 'Partner')),
            const SizedBox(height: 8),
            _hintCard('family', Icons.family_restroom_rounded,
                LifeMateRuntimeLocale.select(fa: 'عضو خانواده یا فرد دیگر', en: 'Family or someone else')),
            const Spacer(flex: 2),
          ],
        ),
      );

  Widget _hintCard(String value, IconData icon, String title) =>
      LifeMateOnboardingOptionCard(
        theme: _theme,
        title: title,
        icon: icon,
        selected: _relationshipHint == value,
        onTap: () => setState(() => _relationshipHint = value),
      );

  Widget _pairingMethodScreen() => _scaffold(
        title: LifeMateRuntimeLocale.select(fa: 'اتصال امن', en: 'Secure pairing'),
        progress: 0.5,
        progressLabel: '2/4',
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'اسکن QR', en: 'Scan QR'),
        onPrimary: _scanQr,
        secondary: TextButton(
          onPressed: () => setState(() {
            _phase = _CareMateGatePhase.manualCode;
            _message = null;
          }),
          child: Text(LifeMateRuntimeLocale.select(
            fa: 'ورود دستی کد دعوت',
            en: 'Enter invitation code manually',
          )),
        ),
        body: Column(
          children: [
            const Spacer(),
            _centerQuestion(
              Icons.qr_code_scanner_rounded,
              LifeMateRuntimeLocale.select(
                fa: 'دعوت یک‌بارمصرف را اسکن کن',
                en: 'Scan the one-time invitation',
              ),
              LifeMateRuntimeLocale.select(
                fa: 'نوع رابطه‌ای که انتخاب کردی مجوز نیست؛ فقط دعوت معتبر + رضایت دوطرفه می‌تواند رابطه را فعال کند.',
                en: 'Your relationship hint is not permission; only a valid invitation plus both consents can activate access.',
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      );

  Widget _manualCodeScreen() => _scaffold(
        title: LifeMateRuntimeLocale.select(fa: 'کد دعوت', en: 'Invitation code'),
        progress: 0.5,
        progressLabel: '2/4',
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'بررسی و اتصال', en: 'Validate and connect'),
        onPrimary: () => _accept(_manualController.text),
        onBack: () => setState(() {
          _phase = _CareMateGatePhase.pairingMethod;
          _message = null;
        }),
        keyboardAware: true,
        body: Column(
          children: [
            const Spacer(),
            _question(
              Icons.key_rounded,
              LifeMateRuntimeLocale.select(fa: 'کد را وارد کن', en: 'Enter the code'),
              LifeMateRuntimeLocale.select(
                fa: 'سرور اعتبار، انقضا، صاحب دعوت و استفاده مجدد را بررسی می‌کند.',
                en: 'The server validates ownership, expiry and replay before creating access.',
              ),
            ),
            const SizedBox(height: 20),
            LifeMateOnboardingTextField(
              theme: _theme,
              controller: _manualController,
              label: LifeMateRuntimeLocale.select(fa: 'کد دعوت', en: 'Invitation code'),
              textDirection: TextDirection.ltr,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _accept(_manualController.text),
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(_message!, style: TextStyle(color: _theme.error)),
            ],
            const Spacer(flex: 2),
          ],
        ),
      );

  Widget _connectingScreen() => _scaffold(
        title: LifeMateRuntimeLocale.select(fa: 'بررسی دعوت', en: 'Validating invitation'),
        progress: 0.75,
        progressLabel: '3/4',
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'در حال اتصال', en: 'Connecting'),
        primaryBusy: true,
        body: _centerQuestion(
          Icons.verified_user_outlined,
          LifeMateRuntimeLocale.select(fa: 'منتظر پاسخ امن سرور', en: 'Waiting for server authorization'),
          LifeMateRuntimeLocale.select(
            fa: 'در این وضعیت هیچ دارو، ویزیت یا اطلاعات خصوصی نمایش داده نمی‌شود.',
            en: 'No medication, appointment or private data is displayed in this state.',
          ),
        ),
      );

  Widget _pendingScreen() => _scaffold(
        title: LifeMateRuntimeLocale.select(fa: 'در انتظار تأیید', en: 'Pending approval'),
        progress: 0.75,
        progressLabel: '3/4',
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'بررسی دوباره', en: 'Check again'),
        onPrimary: _loadRelationshipState,
        body: _centerQuestion(
          Icons.hourglass_top_rounded,
          LifeMateRuntimeLocale.select(fa: 'هنوز دسترسی فعال نشده', en: 'Access is not active yet'),
          LifeMateRuntimeLocale.select(
            fa: 'تا وقتی رابطه روی سرور Active و رضایت‌ها معتبر نباشند، CareMate هیچ داده سلامتی نشان نمی‌دهد.',
            en: 'CareMate shows no health data until the server relationship is Active with valid consent.',
          ),
        ),
      );

  Widget _acceptedScreen() {
    final relationship = _activeRelationship ?? const <String, dynamic>{};
    final patient = relationship['patientDisplayName']?.toString().trim();
    final fertility = _privacyScopes['viewFertilityEstimate'] == true;
    final fertilityNotifications =
        _privacyScopes['receiveFertilityNotifications'] == true;
    final womenSummary = relationship['canViewWomenCalendar'] == true;
    return _scaffold(
      title: LifeMateRuntimeLocale.select(fa: 'اتصال تأیید شد', en: 'Connection accepted'),
      progress: 1,
      progressLabel: '4/4',
      primaryLabel: LifeMateRuntimeLocale.select(fa: 'ورود به CareMate', en: 'Enter CareMate'),
      onPrimary: () => setState(() => _showAcceptedOnce = false),
      body: Column(
        children: [
          const Spacer(),
          _centerQuestion(
            Icons.verified_rounded,
            patient == null || patient.isEmpty
                ? LifeMateRuntimeLocale.select(fa: 'رابطه امن فعال شد', en: 'Secure relationship is active')
                : LifeMateRuntimeLocale.select(
                    fa: 'اتصال با $patient فعال شد',
                    en: 'Connected with $patient',
                  ),
            LifeMateRuntimeLocale.select(
              fa: 'نمایش بعدی فقط از دسترسی‌های واقعی همین رابطه استفاده می‌کند.',
              en: 'The next screen uses only the server-authoritative scopes of this relationship.',
            ),
          ),
          const SizedBox(height: 18),
          _scopeRow(
            LifeMateRuntimeLocale.select(fa: 'تقویم سلامت بانوان', en: 'Women Health summary'),
            womenSummary,
          ),
          _scopeRow(
            LifeMateRuntimeLocale.select(fa: 'برآورد باروری', en: 'Fertility estimate'),
            fertility,
            sensitive: true,
          ),
          _scopeRow(
            LifeMateRuntimeLocale.select(fa: 'اعلان‌های باروری', en: 'Fertility notifications'),
            fertilityNotifications,
            sensitive: true,
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _scopeRow(String label, bool enabled, {bool sensitive = false}) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: sensitive ? _theme.surfaceAlt : _theme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _theme.border),
        ),
        child: Row(
          children: [
            Icon(
              enabled ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
              color: enabled ? _theme.success : _theme.muted,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: TextStyle(color: _theme.ink, fontWeight: FontWeight.w700)),
            ),
            Text(
              enabled
                  ? LifeMateRuntimeLocale.select(fa: 'فعال', en: 'On')
                  : LifeMateRuntimeLocale.select(fa: 'خاموش', en: 'Off'),
              style: TextStyle(
                color: enabled ? _theme.success : _theme.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );

  Widget _revokedScreen() => _scaffold(
        title: LifeMateRuntimeLocale.select(fa: 'اتصال پایان یافته', en: 'Connection revoked'),
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'اتصال دوباره', en: 'Reconnect'),
        onPrimary: () => setState(() {
          _phase = _CareMateGatePhase.relationshipHint;
          _relationshipHint = null;
          _message = null;
        }),
        body: _centerQuestion(
          Icons.link_off_rounded,
          LifeMateRuntimeLocale.select(fa: 'دسترسی قبلی لغو شده است', en: 'Previous access was revoked'),
          LifeMateRuntimeLocale.select(
            fa: 'اطلاعات شخصی از رابط CareMate کنار گذاشته شده و برای اتصال دوباره یک دعوت معتبر جدید لازم است.',
            en: 'Personalized CareMate surfaces are cleared and a new valid invitation is required to reconnect.',
          ),
        ),
      );

  Widget _errorScreen() => _scaffold(
        title: 'CareMate',
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'تلاش دوباره', en: 'Try again'),
        onPrimary: _loadRelationshipState,
        body: _centerQuestion(
          Icons.cloud_off_outlined,
          LifeMateRuntimeLocale.select(fa: 'وضعیت اتصال در دسترس نیست', en: 'Connection status is unavailable'),
          _message ?? '',
        ),
      );

  Widget _question(IconData icon, String title, String description) =>
      LifeMateOnboardingQuestion(
        theme: _theme,
        icon: icon,
        title: title,
        description: description,
      );

  Widget _centerQuestion(IconData icon, String title, String description) =>
      Center(
        child: LifeMateOnboardingQuestion(
          theme: _theme,
          icon: icon,
          title: title,
          description: description,
          alignCenter: true,
        ),
      );

  Widget _scaffold({
    required String title,
    required String primaryLabel,
    required Widget body,
    VoidCallback? onPrimary,
    VoidCallback? onBack,
    Widget? secondary,
    bool primaryBusy = false,
    bool keyboardAware = false,
    double? progress,
    String? progressLabel,
  }) => LifeMateOnboardingScaffold(
        theme: _theme,
        title: title,
        body: body,
        primaryLabel: primaryLabel,
        onPrimary: onPrimary,
        onBack: onBack,
        secondary: secondary,
        primaryBusy: primaryBusy,
        keyboardAware: keyboardAware,
        progress: progress,
        progressLabel: progressLabel,
      );
}
