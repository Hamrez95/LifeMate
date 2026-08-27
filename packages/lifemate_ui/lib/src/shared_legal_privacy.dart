import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifemate_client/lifemate_client.dart';

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
  String? _error;

  LifeMateOnboardingTheme get _theme => LifeMateOnboardingTheme.shared;
  bool get _isPersian => LifeMateRuntimeLocale.isPersian;

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
        _error = null;
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
        _error = LifeMateRuntimeLocale.select(
          fa: 'شرایط و حریم خصوصی دریافت نشد. دوباره تلاش کن.',
          en: 'Terms and privacy information could not be loaded. Try again.',
        );
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
      setState(() => _error = LifeMateRuntimeLocale.select(
            fa: 'برای ادامه، شرایط و اطلاعیه حریم خصوصی الزامی را خودت تأیید کن.',
            en: 'Confirm each required Terms and Privacy document to continue.',
          ));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
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
        _error = error.code == 'legal_acceptance_required'
            ? LifeMateRuntimeLocale.select(
                fa: 'نسخه شرایط تغییر کرده است. نسخه جدید را بررسی و تأیید کن.',
                en: 'The legal version changed. Review and accept the current version.',
              )
            : LifeMateRuntimeLocale.select(
                fa: 'تأیید ذخیره نشد. اتصال را بررسی و دوباره تلاش کن.',
                en: 'Acceptance could not be saved. Check your connection and retry.',
              );
      });
      if (error.code == 'legal_acceptance_required') await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = LifeMateRuntimeLocale.select(
          fa: 'تأیید ذخیره نشد. دوباره تلاش کن.',
          en: 'Acceptance could not be saved. Try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (!_loading && _error == null && status?.completed == true) {
      return widget.child;
    }
    if (_loading) return _loadingScreen();
    if (status == null) return _errorScreen();
    return _legalScreen(status);
  }

  Widget _loadingScreen() => _shell(
        title: 'LifeMate',
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'در حال آماده‌سازی', en: 'Preparing'),
        primaryBusy: true,
        body: _question(
          Icons.policy_outlined,
          LifeMateRuntimeLocale.select(fa: 'نسخه فعلی شرایط را بررسی می‌کنیم', en: 'Checking the current legal version'),
          LifeMateRuntimeLocale.select(fa: 'چند لحظه صبر کن.', en: 'This only takes a moment.'),
        ),
      );

  Widget _errorScreen() => _shell(
        title: 'LifeMate',
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'تلاش دوباره', en: 'Try again'),
        onPrimary: _load,
        body: _question(
          Icons.cloud_off_outlined,
          LifeMateRuntimeLocale.select(fa: 'شرایط فعلی در دسترس نیست', en: 'Current terms are unavailable'),
          _error ?? '',
        ),
      );

  Widget _legalScreen(LifeMateRegistrationStatus status) {
    final docs = status.requiredDocuments;
    final allRequiredChecked = docs.every(
      (document) => document.accepted || _checked.contains(document.id),
    );
    return _shell(
      title: LifeMateRuntimeLocale.select(fa: 'شرایط و حریم خصوصی', en: 'Terms & Privacy'),
      progress: 1,
      progressLabel: LifeMateRuntimeLocale.select(fa: 'مرحله نهایی', en: 'Final step'),
      primaryLabel: LifeMateRuntimeLocale.select(fa: 'تأیید و ادامه', en: 'Accept and continue'),
      onPrimary: allRequiredChecked && !_saving ? _accept : null,
      primaryBusy: _saving,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          LifeMateOnboardingQuestion(
            theme: _theme,
            icon: Icons.verified_user_outlined,
            title: LifeMateRuntimeLocale.select(
              fa: 'قبل از ورود، نسخه فعلی را خودت تأیید کن',
              en: 'Review and accept the current version yourself',
            ),
            description: LifeMateRuntimeLocale.select(
              fa: 'هیچ گزینه‌ای از قبل فعال نیست. تنظیمات اختیاری تبلیغات و پژوهش جداگانه‌اند.',
              en: 'Nothing is pre-checked. Optional marketing and research preferences are separate.',
            ),
          ),
          const SizedBox(height: 16),
          for (final document in docs) ...[
            _documentCard(document),
            const SizedBox(height: 8),
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: TextStyle(color: _theme.error, fontWeight: FontWeight.w600)),
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
        border: Border.all(color: checked ? _theme.primary : _theme.border),
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
                    _error = null;
                  }),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(document.title, style: TextStyle(color: _theme.ink, fontWeight: FontWeight.w800)),
            subtitle: Text(
              LifeMateRuntimeLocale.select(
                fa: 'نسخه ${document.version}',
                en: 'Version ${document.version}',
              ),
              style: TextStyle(color: _theme.muted),
            ),
          ),
          if (document.contentUri != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      document.contentUri!,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(color: _theme.secondary, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    tooltip: LifeMateRuntimeLocale.select(fa: 'کپی لینک', en: 'Copy link'),
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
  }) => Directionality(
        textDirection: _isPersian ? TextDirection.rtl : TextDirection.ltr,
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
  String? _error;

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
      _error = null;
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
        _error = LifeMateRuntimeLocale.select(
          fa: 'تنظیمات حریم خصوصی دریافت نشد.',
          en: 'Privacy preferences could not be loaded.',
        );
      });
    }
  }

  Future<void> _toggle(LifeMatePrivacyPreference item, bool enabled) async {
    if (!item.userMutable || _saving.contains(item.purpose)) return;
    setState(() => _saving.add(item.purpose));
    try {
      await _api.setPrivacyPreference(purpose: item.purpose, enabled: enabled);
      if (!mounted) return;
      setState(() {
        _items = _items
            .map((candidate) => candidate.purpose == item.purpose
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
                : candidate)
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LifeMateRuntimeLocale.select(
          fa: 'تغییر ذخیره نشد؛ دوباره تلاش کن.',
          en: 'The change was not saved. Try again.',
        ))),
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
        title: Text(LifeMateRuntimeLocale.select(
          fa: 'حریم خصوصی و ارتباطات',
          en: 'Privacy & Communications',
        )),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: FilledButton(
                      onPressed: _load,
                      child: Text(LifeMateRuntimeLocale.select(fa: 'تلاش دوباره', en: 'Try again')),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                    children: [
                      Text(
                        LifeMateRuntimeLocale.select(
                          fa: 'این گزینه‌ها اختیاری‌اند و هر زمان می‌توانی خاموششان کنی. اعلان‌های امنیتی، تراکنشی و یادآوری‌های مراقبتی جدا از تبلیغات هستند.',
                          en: 'These choices are optional and can be turned off anytime. Security, transactional and care-reminder communications are separate from marketing.',
                        ),
                        style: const TextStyle(height: 1.6),
                      ),
                      const SizedBox(height: 18),
                      for (final item in _items)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: SwitchListTile.adaptive(
                            value: item.enabled,
                            onChanged: item.userMutable && !_saving.contains(item.purpose)
                                ? (value) => _toggle(item, value)
                                : null,
                            title: Text(_title(item), style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text(_subtitle(item)),
                            secondary: _saving.contains(item.purpose)
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(_icon(item), color: widget.accent),
                          ),
                        ),
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: widget.accent.withValues(alpha: 0.08),
                        ),
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: 'خاموش‌کردن پیشنهادها و تبلیغات روی پیام‌های ضروری حساب، امنیت یا یادآوری‌های مراقبتی اثر نمی‌گذارد.',
                            en: 'Turning off offers and marketing does not disable essential account, security or care-reminder messages.',
                          ),
                          style: const TextStyle(height: 1.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  String _title(LifeMatePrivacyPreference item) => switch (item.purpose) {
        'promotional_sms' => LifeMateRuntimeLocale.select(fa: 'پیشنهادها با پیامک', en: 'Offers by SMS'),
        'promotional_push' => LifeMateRuntimeLocale.select(fa: 'پیشنهادها با اعلان', en: 'Offers by push'),
        'promotional_email' => LifeMateRuntimeLocale.select(fa: 'پیشنهادها با ایمیل', en: 'Offers by email'),
        'research' => LifeMateRuntimeLocale.select(fa: 'مشارکت در پژوهش', en: 'Research participation'),
        'personalization' => LifeMateRuntimeLocale.select(fa: 'شخصی‌سازی اختیاری', en: 'Optional personalization'),
        _ => item.purpose,
      };

  String _subtitle(LifeMatePrivacyPreference item) => LifeMateRuntimeLocale.select(
        fa: '${item.description} · نسخه ${item.policyVersion}',
        en: '${item.description} · ${item.policyVersion}',
      );

  IconData _icon(LifeMatePrivacyPreference item) => switch (item.category) {
        'Promotional' => Icons.campaign_outlined,
        'Research' => Icons.science_outlined,
        'Personalization' => Icons.tune_rounded,
        _ => Icons.privacy_tip_outlined,
      };
}
