import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'localization.dart';
import 'onboarding_components.dart';
import 'onboarding_theme.dart';

/// Server-backed minimal account onboarding shared by LifeMate products.
///
/// The gate deliberately owns only Display Name and presentation intent.
/// Birth date, healthcare data, relationships, consent and permissions remain
/// feature-specific progressive profiling and are never inferred here.
class LifeMateAccountOnboardingGate extends StatefulWidget {
  const LifeMateAccountOnboardingGate({
    super.key,
    required this.child,
    this.api,
  });

  final Widget child;
  final LifeMateAccountOnboardingApi? api;

  @override
  State<LifeMateAccountOnboardingGate> createState() =>
      _LifeMateAccountOnboardingGateState();
}

class _LifeMateAccountOnboardingGateState
    extends State<LifeMateAccountOnboardingGate> {
  late LifeMateAccountOnboardingApi _api;
  late bool _ownsApi;
  final _displayName = TextEditingController();
  LifeMateAccountOnboardingSnapshot? _snapshot;
  LifeMatePresentationIntent? _intent;
  Object? _loadError;
  String? _actionError;
  bool _loading = true;
  bool _saving = false;
  int _step = 0;

  LifeMateOnboardingTheme get _theme => LifeMateOnboardingTheme.shared;

  @override
  void initState() {
    super.initState();
    _ownsApi = widget.api == null;
    _api = widget.api ?? LifeMateAccountOnboardingApi.fromEnvironment();
    _load();
  }

  @override
  void didUpdateWidget(covariant LifeMateAccountOnboardingGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.api, widget.api)) return;
    if (_ownsApi) _api.close();
    _ownsApi = widget.api == null;
    _api = widget.api ?? LifeMateAccountOnboardingApi.fromEnvironment();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
        _actionError = null;
      });
    }
    try {
      final snapshot = await _api.getSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _intent = snapshot.presentationIntent;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _continueName() {
    final value = _displayName.text.trim();
    if (value.isEmpty) {
      setState(() => _actionError = context.tr('onboarding.account.nameRequired'));
      return;
    }
    if (value.length > 120) {
      setState(() => _actionError = context.tr('onboarding.account.nameTooLong'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _actionError = null;
      _step = 1;
    });
  }

  Future<void> _complete() async {
    final snapshot = _snapshot;
    final intent = _intent;
    if (snapshot == null || intent == null || _saving) return;
    setState(() {
      _saving = true;
      _actionError = null;
    });
    try {
      final updated = await _api.complete(
        current: snapshot,
        displayName: _displayName.text,
        intent: intent,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = updated;
        _saving = false;
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 409) {
        setState(() => _saving = false);
        await _reloadAfterConflict();
        return;
      }
      setState(() {
        _saving = false;
        _actionError = _safeActionError();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _actionError = _safeActionError();
      });
    }
  }

  Future<void> _reloadAfterConflict() async {
    final preservedName = _displayName.text;
    final preservedIntent = _intent;
    try {
      final latest = await _api.getSnapshot();
      if (!mounted) return;
      if (latest.completed) {
        setState(() => _snapshot = latest);
        return;
      }
      setState(() {
        _snapshot = latest;
        _intent = preservedIntent;
        _displayName.text = preservedName;
        _actionError = context.tr('onboarding.account.conflictRefreshed');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionError = _safeActionError());
    }
  }

  String _safeActionError() => context.tr('onboarding.account.saveFailed');

  @override
  void dispose() {
    _displayName.dispose();
    if (_ownsApi) _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (!_loading && _loadError == null && snapshot?.completed == true) {
      return widget.child;
    }
    if (_loading) return _loadingScreen();
    if (_loadError != null || snapshot == null) return _errorScreen();
    return _step == 0 ? _nameScreen() : _intentScreen();
  }

  Widget _loadingScreen() {
    return Directionality(
      textDirection: context.lifeMateLocale.textDirection,
      child: LifeMateOnboardingScaffold(
        theme: _theme,
        title: 'LifeMate',
        primaryLabel: context.tr('common.preparing'),
        primaryBusy: true,
        body: Center(
          child: LifeMateOnboardingQuestion(
            theme: _theme,
            title: context.tr('onboarding.account.preparingTitle'),
            description: context.tr('onboarding.account.preparingDescription'),
            icon: Icons.favorite_outline_rounded,
            alignCenter: true,
          ),
        ),
      ),
    );
  }

  Widget _errorScreen() {
    return Directionality(
      textDirection: context.lifeMateLocale.textDirection,
      child: LifeMateOnboardingScaffold(
        theme: _theme,
        title: 'LifeMate',
        primaryLabel: context.tr('common.retry'),
        onPrimary: _load,
        body: Center(
          child: LifeMateOnboardingQuestion(
            theme: _theme,
            title: context.tr('onboarding.account.unavailableTitle'),
            description: context.tr('onboarding.account.unavailableDescription'),
            icon: Icons.cloud_off_outlined,
            alignCenter: true,
          ),
        ),
      ),
    );
  }

  Widget _nameScreen() {
    return Directionality(
      textDirection: context.lifeMateLocale.textDirection,
      child: LifeMateOnboardingScaffold(
        theme: _theme,
        title: context.tr('onboarding.account.start'),
        progress: 0.5,
        progressLabel: context.tr('onboarding.account.step1of2'),
        primaryLabel: context.tr('common.continue'),
        onPrimary: _continueName,
        keyboardAware: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            LifeMateOnboardingQuestion(
              theme: _theme,
              title: context.tr('onboarding.account.nameTitle'),
              description: context.tr('onboarding.account.nameDescription'),
              icon: Icons.person_outline_rounded,
              alignCenter: true,
            ),
            const SizedBox(height: 26),
            LifeMateOnboardingTextField(
              theme: _theme,
              controller: _displayName,
              label: context.tr('onboarding.account.displayName'),
              hintText: context.tr('onboarding.account.nameHint'),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _continueName(),
              enabled: !_saving,
            ),
            if (_actionError != null) ...[
              const SizedBox(height: 10),
              _feedback(_actionError!),
            ],
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  Widget _intentScreen() {
    return Directionality(
      textDirection: context.lifeMateLocale.textDirection,
      child: LifeMateOnboardingScaffold(
        theme: _theme,
        title: context.tr('onboarding.account.start'),
        progress: 1,
        progressLabel: context.tr('onboarding.account.step2of2'),
        primaryLabel: context.tr('onboarding.account.enter'),
        onPrimary: _intent == null || _saving ? null : _complete,
        primaryBusy: _saving,
        onBack: _saving ? null : () => setState(() {
          _step = 0;
          _actionError = null;
        }),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            LifeMateOnboardingQuestion(
              theme: _theme,
              title: context.tr('onboarding.account.intentTitle'),
              description: context.tr('onboarding.account.intentDescription'),
            ),
            const SizedBox(height: 22),
            _intentCard(
              LifeMatePresentationIntent.self,
              Icons.person_outline_rounded,
              context.tr('onboarding.account.intentSelf'),
              context.tr('onboarding.account.intentSelfDescription'),
            ),
            const SizedBox(height: 12),
            _intentCard(
              LifeMatePresentationIntent.caregiving,
              Icons.favorite_border_rounded,
              context.tr('onboarding.account.intentCaregiving'),
              context.tr('onboarding.account.intentCaregivingDescription'),
            ),
            const SizedBox(height: 12),
            _intentCard(
              LifeMatePresentationIntent.both,
              Icons.diversity_1_outlined,
              context.tr('onboarding.account.intentBoth'),
              context.tr('onboarding.account.intentBothDescription'),
            ),
            if (_actionError != null) ...[
              const SizedBox(height: 10),
              _feedback(_actionError!),
            ],
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  Widget _intentCard(
    LifeMatePresentationIntent intent,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return LifeMateOnboardingOptionCard(
      theme: _theme,
      title: title,
      subtitle: subtitle,
      icon: icon,
      selected: _intent == intent,
      enabled: !_saving,
      onTap: () => setState(() {
        _intent = intent;
        _actionError = null;
      }),
    );
  }

  Widget _feedback(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: _theme.error, size: 18),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: _theme.error,
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
