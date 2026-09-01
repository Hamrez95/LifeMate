import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'legal_privacy_locales.dart';
import 'localization.dart';
import 'onboarding_components.dart';
import 'onboarding_theme.dart';

class LifeMateLegalRegistrationGate extends StatefulWidget {
  const LifeMateLegalRegistrationGate({
    super.key,
    required this.child,
    this.api,
  });

  final Widget child;
  final LifeMateLegalPrivacyApi? api;

  @override
  State<LifeMateLegalRegistrationGate> createState() =>
      _LifeMateLegalRegistrationGateState();
}

class _LifeMateLegalRegistrationGateState
    extends State<LifeMateLegalRegistrationGate> {
  late LifeMateLegalPrivacyApi _api;
  late bool _ownsApi;
  LifeMateRegistrationStatus? _status;
  final Set<String> _checked = <String>{};
  bool _loading = true;
  bool _saving = false;
  String? _errorKey;

  LifeMateOnboardingTheme get _theme => LifeMateOnboardingTheme.shared;

  @override
  void initState() {
    super.initState();
    _ownsApi = widget.api == null;
    _api = widget.api ?? LifeMateLegalPrivacyApi.fromEnvironment();
    _load();
  }

  @override
  void dispose() {
    if (_ownsApi) _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorKey = null;
      });
    }
    try {
      final value = await _api.registrationStatus();
      if (!mounted) return;
      setState(() {
        _status = value;
        _loading = false;
        _checked
          ..clear()
          ..addAll(
            value.requiredDocuments
                .where((document) => document.accepted)
                .map((document) => document.id),
          );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = 'legal.registration.loadFailed';
      });
    }
  }

  Future<void> _accept() async {
    final status = _status;
    if (status == null || _saving) return;
    final pending = status.requiredDocuments
        .where((document) => !document.accepted)
        .toList(growable: false);
    if (pending.any((document) => !_checked.contains(document.id))) {
      setState(
        () => _errorKey = 'legal.registration.confirmRequired',
      );
      return;
    }
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    try {
      final updated = await _api.acceptCurrentLegalDocuments(
        status.requiredDocuments,
      );
      if (!mounted) return;
      setState(() {
        _status = updated;
        _saving = false;
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorKey = error.code == 'legal_acceptance_required'
            ? 'legal.registration.versionChanged'
            : 'legal.registration.saveConnectionFailed';
      });
      if (error.code == 'legal_acceptance_required') await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorKey = 'legal.registration.saveFailed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (!_loading && _errorKey == null && status?.completed == true) {
      return widget.child;
    }
    if (_loading) return _loadingScreen();
    if (status == null) return _errorScreen();
    return _legalScreen(status);
  }

  Widget _loadingScreen() => _shell(
        title: 'LifeMate',
        primaryLabel: context.tr('common.preparing'),
        primaryBusy: true,
        body: _question(
          Icons.policy_outlined,
          context.legalPrivacyTr('legal.registration.checkingTitle'),
          context.legalPrivacyTr('legal.registration.checkingDescription'),
        ),
      );

  Widget _errorScreen() => _shell(
        title: 'LifeMate',
        primaryLabel: context.tr('common.retry'),
        onPrimary: _load,
        body: _question(
          Icons.cloud_off_outlined,
          context.legalPrivacyTr('legal.registration.unavailableTitle'),
          _errorKey == null ? '' : context.legalPrivacyTr(_errorKey!),
        ),
      );

  Widget _legalScreen(LifeMateRegistrationStatus status) {
    final docs = status.requiredDocuments;
    final allRequiredChecked = docs.every(
      (document) => document.accepted || _checked.contains(document.id),
    );
    return _shell(
      title: context.legalPrivacyTr('legal.registration.title'),
      progress: 1,
      progressLabel: context.legalPrivacyTr('legal.registration.finalStep'),
      primaryLabel:
          context.legalPrivacyTr('legal.registration.acceptContinue'),
      onPrimary: allRequiredChecked && !_saving ? _accept : null,
      primaryBusy: _saving,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          LifeMateOnboardingQuestion(
            theme: _theme,
            icon: Icons.verified_user_outlined,
            title: context.legalPrivacyTr('legal.registration.reviewTitle'),
            description:
                context.legalPrivacyTr('legal.registration.reviewDescription'),
          ),
          const SizedBox(height: 16),
          for (final document in docs) ...[
            _documentCard(document),
            const SizedBox(height: 8),
          ],
          if (_errorKey != null) ...[
            const SizedBox(height: 6),
            Text(
              context.legalPrivacyTr(_errorKey!),
              style: TextStyle(
                color: _theme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _documentCard(LifeMateLegalDocument document) {
    final checked = document.accepted || _checked.contains(document.id);
    return Container(
      decoration: BoxDecoration(
        color: _theme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: checked ? _theme.primary : _theme.border,
        ),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            value: checked,
            enabled: !document.accepted && !_saving,
            onChanged: document.accepted || _saving
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      _checked.add(document.id);
                    } else {
                      _checked.remove(document.id);
                    }
                    _errorKey = null;
                  }),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              document.title,
              style: TextStyle(
                color: _theme.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              context.legalPrivacyTr(
                'legal.registration.documentVersion',
                params: <String, Object?>{'version': document.version},
              ),
              style: TextStyle(color: _theme.muted),
            ),
          ),
          if (document.contentUri != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      document.contentUri!,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: _theme.secondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip:
                        context.legalPrivacyTr('legal.registration.copyLink'),
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: document.contentUri!),
                    ),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _question(IconData icon, String title, String description) => Center(
        child: LifeMateOnboardingQuestion(
          theme: _theme,
          icon: icon,
          title: title,
          description: description,
          alignCenter: true,
        ),
      );

  Widget _shell({
    required String title,
    required String primaryLabel,
    required Widget body,
    VoidCallback? onPrimary,
    bool primaryBusy = false,
    double? progress,
    String? progressLabel,
  }) =>
      Directionality(
        textDirection: context.lifeMateLocale.textDirection,
        child: LifeMateOnboardingScaffold(
          theme: _theme,
          title: title,
          primaryLabel: primaryLabel,
          onPrimary: onPrimary,
          primaryBusy: primaryBusy,
          progress: progress,
          progressLabel: progressLabel,
          body: body,
        ),
      );
}

class LifeMatePrivacyPreferencesScreen extends StatefulWidget {
  const LifeMatePrivacyPreferencesScreen({
    super.key,
    this.api,
    this.background = const Color(0xFFFAF7F2),
    this.accent = const Color(0xFF51475A),
  });

  final LifeMateLegalPrivacyApi? api;
  final Color background;
  final Color accent;

  @override
  State<LifeMatePrivacyPreferencesScreen> createState() =>
      _LifeMatePrivacyPreferencesScreenState();
}

class _LifeMatePrivacyPreferencesScreenState
    extends State<LifeMatePrivacyPreferencesScreen> {
  late LifeMateLegalPrivacyApi _api;
  late bool _ownsApi;
  List<LifeMatePrivacyPreference> _items = const [];
  final Set<String> _saving = <String>{};
  bool _loading = true;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    _ownsApi = widget.api == null;
    _api = widget.api ?? LifeMateLegalPrivacyApi.fromEnvironment();
    _load();
  }

  @override
  void dispose() {
    if (_ownsApi) _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final items = await _api.privacyPreferences();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = 'privacy.preferences.loadFailed';
      });
    }
  }

  Future<void> _toggle(LifeMatePrivacyPreference item, bool enabled) async {
    if (!item.userMutable || _saving.contains(item.purpose)) return;
    setState(() => _saving.add(item.purpose));
    try {
      await _api.setPrivacyPreference(
        purpose: item.purpose,
        enabled: enabled,
      );
      if (!mounted) return;
      setState(() {
        _items = _items
            .map(
              (candidate) => candidate.purpose == item.purpose
                  ? LifeMatePrivacyPreference(
                      purpose: candidate.purpose,
                      category: candidate.category,
                      channel: candidate.channel,
                      policyVersion: candidate.policyVersion,
                      enabled: enabled,
                      explicit: true,
                      userMutable: candidate.userMutable,
                      description: candidate.description,
                    )
                  : candidate,
            )
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.legalPrivacyTr(
              'privacy.preferences.changeSaveFailed',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(item.purpose));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.background,
      appBar: AppBar(
        backgroundColor: widget.background,
        surfaceTintColor: Colors.transparent,
        title: Text(
          context.legalPrivacyTr('privacy.preferences.title'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorKey != null
                ? Center(
                    child: FilledButton(
                      onPressed: _load,
                      child: Text(context.tr('common.retry')),
                    ),
                  )
                : ListView(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(18, 12, 18, 28),
                    children: [
                      Text(
                        context.legalPrivacyTr(
                          'privacy.preferences.description',
                        ),
                        style: const TextStyle(height: 1.6),
                      ),
                      const SizedBox(height: 18),
                      for (final item in _items)
                        Card(
                          margin: const EdgeInsetsDirectional.only(bottom: 10),
                          child: SwitchListTile.adaptive(
                            value: item.enabled,
                            onChanged:
                                item.userMutable && !_saving.contains(item.purpose)
                                    ? (value) => _toggle(item, value)
                                    : null,
                            title: Text(
                              _title(item),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(_subtitle(item)),
                            secondary: _saving.contains(item.purpose)
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(_icon(item), color: widget.accent),
                          ),
                        ),
                      Container(
                        margin: const EdgeInsetsDirectional.only(top: 8),
                        padding: const EdgeInsetsDirectional.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: widget.accent.withValues(alpha: 0.08),
                        ),
                        child: Text(
                          context.legalPrivacyTr(
                            'privacy.preferences.essentialNotice',
                          ),
                          style: const TextStyle(
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  String _title(LifeMatePrivacyPreference item) => switch (item.purpose) {
        'promotional_sms' =>
          context.legalPrivacyTr('privacy.preferences.promotionalSms'),
        'promotional_push' =>
          context.legalPrivacyTr('privacy.preferences.promotionalPush'),
        'promotional_email' =>
          context.legalPrivacyTr('privacy.preferences.promotionalEmail'),
        'research' => context.legalPrivacyTr('privacy.preferences.research'),
        'personalization' =>
          context.legalPrivacyTr('privacy.preferences.personalization'),
        _ => item.purpose,
      };

  String _subtitle(LifeMatePrivacyPreference item) => context.legalPrivacyTr(
        'privacy.preferences.versionedDescription',
        params: <String, Object?>{
          'description': item.description,
          'version': item.policyVersion,
        },
      );

  IconData _icon(LifeMatePrivacyPreference item) => switch (item.category) {
        'Promotional' => Icons.campaign_outlined,
        'Research' => Icons.science_outlined,
        'Personalization' => Icons.tune_rounded,
        _ => Icons.privacy_tip_outlined,
      };
}
