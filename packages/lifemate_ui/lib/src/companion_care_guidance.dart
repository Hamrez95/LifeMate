import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

class LifeMateCompanionCareScreen extends StatefulWidget {
  const LifeMateCompanionCareScreen({
    super.key,
    required this.apiClient,
    this.companionApi,
    this.accent = const Color(0xFF4D8EF7),
    this.background = const Color(0xFFF6F9FF),
  });

  final LifeMateApiClient apiClient;
  final LifeMateCompanionCareApi? companionApi;
  final Color accent;
  final Color background;

  @override
  State<LifeMateCompanionCareScreen> createState() =>
      _LifeMateCompanionCareScreenState();
}

class _LifeMateCompanionCareScreenState
    extends State<LifeMateCompanionCareScreen> {
  late final LifeMateCompanionCareApi _companionApi;
  late final bool _ownsApi;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _patientUserId;
  String? _patientName;
  String? _presentationType;
  LifeMateCompanionGuidance? _guidance;
  LifeMateCompanionFertilityInsight? _fertilityInsight;

  @override
  void initState() {
    super.initState();
    _ownsApi = widget.companionApi == null;
    _companionApi =
        widget.companionApi ?? LifeMateCompanionCareApi.fromEnvironment();
    _load();
  }

  @override
  void dispose() {
    if (_ownsApi) _companionApi.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _guidance = null;
        _fertilityInsight = null;
        _presentationType = null;
      });
    }
    try {
      final relationships = await widget.apiClient.getCareRelationships();
      final candidates = relationships
          .where(
            (relationship) =>
                relationship['status']?.toString().toLowerCase() == 'active',
          )
          .toList(growable: false)
        ..sort((left, right) {
          final leftPolicy = LifeMateRelationshipPresentationPolicy.fromRaw(
            left['presentationType']?.toString(),
          );
          final rightPolicy = LifeMateRelationshipPresentationPolicy.fromRaw(
            right['presentationType']?.toString(),
          );
          final byPresentation = leftPolicy
              .surfaceRank('companion')
              .compareTo(rightPolicy.surfaceRank('companion'));
          if (byPresentation != 0) return byPresentation;
          return (left['id']?.toString() ?? '')
              .compareTo(right['id']?.toString() ?? '');
        });
      Map<String, dynamic>? summary;
      String? patientId;
      String? patientName;
      String? presentationType;

      // Presentation only orders candidates. The server still independently
      // authorizes each Women/Companion summary using actual consent scopes.
      for (final relationship in candidates) {
        final candidate = relationship['patientUserId']?.toString();
        if (candidate == null || candidate.isEmpty) continue;
        try {
          summary = await widget.apiClient.getCareRecipientWomenCalendar(
            patientUserId: candidate,
          );
          patientId = candidate;
          patientName = relationship['patientDisplayName']?.toString();
          presentationType = relationship['presentationType']?.toString();
          break;
        } on LifeMateApiException catch (error) {
          if (_isAccessRevoked(error.code) ||
              error.code == 'women_calendar_not_active') {
            continue;
          }
          rethrow;
        }
      }

      if (summary == null || patientId == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'locked';
        });
        return;
      }

      final scopes = _map(summary['privacyScopes']);
      final estimate = _map(summary['estimate']);
      final fertility = _map(summary['fertilityEstimate']);
      final shared = _map(summary['latestSharedDailyLog']);
      final historyRaw = summary['guidanceHistory'];
      final actionsRaw = summary['supportActions'];

      final history = (historyRaw is List ? historyRaw : const <dynamic>[])
          .whereType<Map>()
          .map((item) {
        final value = Map<String, dynamic>.from(item);
        return LifeMateCompanionGuidanceHistoryItem(
          guidanceId: value['guidanceId']?.toString() ?? '',
          shownAtUtc: DateTime.tryParse(
                value['shownAtUtc']?.toString() ?? '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
      }).toList(growable: false);

      final actions = (actionsRaw is List ? actionsRaw : const <dynamic>[])
          .whereType<Map>()
          .map((item) {
        final value = Map<String, dynamic>.from(item);
        return LifeMateCompanionSupportActionHistoryItem(
          actionType: value['actionType']?.toString() ?? '',
          performedAtUtc: DateTime.tryParse(
                value['performedAtUtc']?.toString() ?? '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
      }).toList(growable: false);

      final selected = const LifeMateCompanionCareEngine().select(
        phaseAllowed: scopes['viewPhaseSummary'] == true,
        wellbeingAllowed: scopes['viewSharedWellbeing'] == true,
        cycleDay: _int(estimate['cycleDay']),
        mood: shared['mood']?.toString(),
        energyLevel: _int(shared['energyLevel']),
        guidanceHistory: history,
        supportActions: actions,
        locale: LifeMateRuntimeLocale.languageCode,
        nowUtc: DateTime.now().toUtc(),
      );
      final fertilityInsight = const LifeMateCompanionFertilityEngine().insight(
        viewFertilityEstimate: scopes['viewFertilityEstimate'] == true,
        state: fertility['state']?.toString(),
        fertilityEstimateReliable: fertility['fertilityEstimateReliable'] == true,
        confidence: fertility['confidence']?.toString(),
        cyclePattern: fertility['cyclePattern']?.toString(),
        locale: LifeMateRuntimeLocale.languageCode,
      );

      if (!mounted) return;
      setState(() {
        _patientUserId = patientId;
        _patientName = patientName;
        _presentationType = presentationType;
        _guidance = selected;
        _fertilityInsight = fertilityInsight;
        _loading = false;
      });

      if (selected != null) {
        try {
          await _companionApi.recordImpression(
            patientUserId: patientId,
            guidanceId: selected.id,
            contentVersion: selected.contentVersion,
            category: selected.category,
          );
        } on LifeMateApiException catch (error) {
          if (_isAccessRevoked(error.code) && mounted) {
            setState(() {
              _guidance = null;
              _fertilityInsight = null;
              _error = 'locked';
            });
          }
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _recordAction() async {
    final patient = _patientUserId;
    final guidance = _guidance;
    final action = guidance?.supportActionType;
    if (patient == null || guidance == null || action == null || _saving) return;

    setState(() => _saving = true);
    try {
      await widget.apiClient.recordCareRecipientWomenSupportAction(
        patientUserId: patient,
        actionType: action,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: 'همراهی ثبت شد.',
              en: 'Support action recorded.',
            ),
          ),
        ),
      );
      await _load();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      if (_isAccessRevoked(error.code)) {
        setState(() {
          _guidance = null;
          _fertilityInsight = null;
          _error = 'locked';
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              LifeMateRuntimeLocale.select(
                fa: 'ثبت همراهی انجام نشد.',
                en: 'Support action could not be recorded.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fa = LifeMateRuntimeLocale.isPersian;
    return Scaffold(
      backgroundColor: widget.background,
      appBar: AppBar(
        backgroundColor: widget.background,
        surfaceTintColor: Colors.transparent,
        title: Text(fa ? 'همراهی پیشنهادی' : 'Support guidance'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error == 'locked'
                ? _state(
                    Icons.lock_outline_rounded,
                    fa ? 'اشتراک‌گذاری لازم خاموش است' : 'Required sharing is off',
                    fa
                        ? 'فقط داده‌ای که صاحب حساب صریحاً به اشتراک گذاشته باشد می‌تواند پیشنهاد شخصی‌سازی‌شده بسازد.'
                        : 'Personalized guidance is available only from explicitly shared data.',
                  )
                : _error != null
                    ? _state(
                        Icons.cloud_off_rounded,
                        fa ? 'دریافت پیشنهاد انجام نشد' : 'Guidance unavailable',
                        fa ? 'دوباره تلاش کنید.' : 'Try again.',
                        retry: true,
                      )
                    : _guidance == null && _fertilityInsight == null
                        ? _state(
                            Icons.spa_outlined,
                            fa ? 'فعلاً پیشنهاد تازه‌ای نداریم' : 'No new suggestion right now',
                            fa
                                ? 'برای جلوگیری از تکرار و مزاحمت، پیشنهادها فاصله زمانی دارند.'
                                : 'Guidance uses cooldowns to avoid repetition.',
                          )
                        : _card(fa),
      ),
    );
  }

  Widget _card(bool fa) {
    final name = _patientName?.trim().isNotEmpty == true
        ? _patientName!.trim()
        : (fa ? 'فرد تحت مراقبت' : 'Person under care');
    final policy = LifeMateRelationshipPresentationPolicy.fromRaw(
      _presentationType,
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          policy.companionHeading(personName: name, isPersian: fa),
          key: const ValueKey('relationship-aware-companion-heading'),
          style: TextStyle(
            color: widget.accent,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (_fertilityInsight != null) ...[
          const SizedBox(height: 12),
          _fertilityCard(fa),
        ],
        if (_guidance != null) ...[
          const SizedBox(height: 12),
          _guidanceCard(fa),
        ],
      ],
    );
  }

  Widget _fertilityCard(bool fa) {
    final insight = _fertilityInsight!;
    final unavailable =
        insight.state == LifeMateCompanionFertilityState.unavailable;
    return Container(
      key: const ValueKey('companion-fertility-estimate-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: widget.accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            unavailable ? Icons.help_outline_rounded : Icons.local_florist_rounded,
            color: widget.accent,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            insight.title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(insight.body, style: const TextStyle(height: 1.65, fontSize: 14)),
          const SizedBox(height: 12),
          Text(
            insight.disclaimer,
            key: const ValueKey('companion-fertility-disclaimer'),
            style: const TextStyle(fontSize: 11, height: 1.5, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Text(
            fa
                ? 'این بخش فقط وقتی نمایش داده می‌شود که صاحب داده، اشتراک برآورد باروری را جداگانه روشن کرده باشد.'
                : 'This appears only when the data owner independently enables fertility-estimate sharing.',
            style: TextStyle(fontSize: 10.5, color: widget.accent),
          ),
        ],
      ),
    );
  }

  Widget _guidanceCard(bool fa) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.volunteer_activism_rounded,
              color: widget.accent,
              size: 34,
            ),
            const SizedBox(height: 14),
            Text(
              _guidance!.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _guidance!.message,
              style: const TextStyle(height: 1.65, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              fa
                  ? 'این پیشنهاد تشخیص یا توصیه پزشکی نیست.'
                  : 'This is supportive guidance, not medical advice.',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
            if (_guidance!.supportActionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accent,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _saving ? null : _recordAction,
                icon: const Icon(Icons.favorite_outline_rounded),
                label: Text(_guidance!.supportActionLabel!),
              ),
            ],
          ],
        ),
      );

  Widget _state(
    IconData icon,
    String title,
    String message, {
    bool retry = false,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 54, color: widget.accent),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              if (retry) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    LifeMateRuntimeLocale.select(fa: 'تلاش دوباره', en: 'Retry'),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  static bool _isAccessRevoked(String code) =>
      code == 'women_calendar_access_denied' || code == 'person_access_denied';

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  static int? _int(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
}
