import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

import '../../core/utils/persian_date_utils.dart';
import 'women_health_activation_api.dart';

class WomenHealthActivationV3Screen extends StatefulWidget {
  const WomenHealthActivationV3Screen({
    super.key,
    required this.onActivated,
    this.api,
  });

  final Future<void> Function() onActivated;
  final WomenHealthActivationApi? api;

  @override
  State<WomenHealthActivationV3Screen> createState() =>
      _WomenHealthActivationV3ScreenState();
}

class _WomenHealthActivationV3ScreenState
    extends State<WomenHealthActivationV3Screen> {
  late final WomenHealthActivationApi _api =
      widget.api ?? WomenHealthActivationApi.fromEnvironment();
  final _theme = LifeMateOnboardingTheme.womenHealth;

  WomenHealthActivationProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _step = 0;
  int _cycleLength = 28;
  bool _cycleKnown = true;
  int _periodLength = 5;
  bool _periodKnown = true;
  DateTime? _lastPeriodStart;
  String _regularity = 'unknown';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
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
      final profile = await _api.getProfile();
      if (!mounted) return;
      if (profile.enabled) {
        await widget.onActivated();
        return;
      }
      setState(() {
        _profile = profile;
        _cycleLength = profile.cycleLength;
        _cycleKnown = profile.cycleLengthKnown ?? true;
        _periodLength = profile.periodLength;
        _periodKnown = profile.periodLengthKnown ?? true;
        _lastPeriodStart = profile.lastPeriodStart;
        _regularity = profile.regularity ?? 'unknown';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr('women.activation.loadFailed');
      });
    }
  }

  void _next() {
    if (_step == 3 && _lastPeriodStart == null) {
      setState(() {
        _error = context.tr('women.activation.selectLastPeriod');
      });
      return;
    }
    if (_step >= 4) {
      _save();
      return;
    }
    setState(() {
      _error = null;
      _step += 1;
    });
  }

  void _back() {
    if (_saving || _step == 0) return;
    setState(() {
      _error = null;
      _step -= 1;
    });
  }

  Future<void> _pickLastPeriod() async {
    final selected = await showAppDatePicker(
      context: context,
      initialDate: _lastPeriodStart ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
      title: context.tr('women.activation.datePickerTitle'),
    );
    if (selected != null && mounted) {
      setState(() {
        _lastPeriodStart = selected;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    final profile = _profile;
    final start = _lastPeriodStart;
    if (profile == null || start == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.activate(
        current: profile,
        lastPeriodStart: start,
        cycleLength: _cycleLength,
        cycleLengthKnown: _cycleKnown,
        periodLength: _periodLength,
        periodLengthKnown: _periodKnown,
        regularity: _regularity,
      );
      if (!mounted) return;
      await widget.onActivated();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 409) {
        await _load();
        return;
      }
      setState(() {
        _saving = false;
        _error = context.tr('women.activation.saveConnectionFailed');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.tr('women.activation.saveFailed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _frame(
        body: _question(
          Icons.favorite_outline_rounded,
          context.tr('women.activation.preparingTitle'),
          context.tr('women.activation.oneMoment'),
        ),
        primaryLabel: context.tr('common.preparing'),
        busy: true,
      );
    }
    if (_profile == null) {
      return _frame(
        body: _question(
          Icons.cloud_off_outlined,
          context.tr('women.activation.unavailableTitle'),
          _error ?? '',
        ),
        primaryLabel: context.tr('common.retry'),
        onPrimary: _load,
      );
    }

    return _frame(
      body: switch (_step) {
        0 => _activationStep(),
        1 => _cycleStep(),
        2 => _periodStep(),
        3 => _dateStep(),
        _ => _regularityStep(),
      },
      primaryLabel: _step == 4
          ? context.tr('women.activation.openCalendar')
          : context.tr('common.continue'),
      onPrimary: _saving ? null : _next,
      busy: _saving,
      progress: (_step + 1) / 5,
      progressLabel: context.tr(
        'women.activation.progress',
        params: {'current': localizeDigits(context, _step + 1)},
      ),
      onBack: _step == 0 ? null : _back,
    );
  }

  Widget _activationStep() => Column(
        children: [
          const Spacer(),
          _question(
            Icons.calendar_month_outlined,
            context.tr('women.activation.activateTitle'),
            context.tr('women.activation.activateDescription'),
          ),
          const SizedBox(height: 22),
          _softNote(
            Icons.lock_outline_rounded,
            context.tr('women.activation.privacyNote'),
          ),
          const Spacer(flex: 2),
        ],
      );

  Widget _cycleStep() => Column(
        children: [
          const Spacer(),
          _question(
            Icons.rotate_right_rounded,
            context.tr('women.activation.cycleTitle'),
            _cycleKnown
                ? context.tr('women.activation.cycleKnownDescription')
                : context.tr('women.activation.cycleUnknownDescription'),
          ),
          const SizedBox(height: 18),
          if (_cycleKnown)
            _numberSelector(
              value: _cycleLength,
              min: 21,
              max: 45,
              suffix: context.tr('women.activation.days'),
              onChanged: (value) => setState(() => _cycleLength = value),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _compactChoice(
                  label: context.tr('women.activation.notSure'),
                  selected: !_cycleKnown && _regularity != 'irregular',
                  onTap: () => setState(() {
                    _cycleKnown = false;
                    if (_regularity == 'irregular') _regularity = 'unknown';
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _compactChoice(
                  label: context.tr('women.activation.irregularChoice'),
                  selected: !_cycleKnown && _regularity == 'irregular',
                  onTap: () => setState(() {
                    _cycleKnown = false;
                    _regularity = 'irregular';
                  }),
                ),
              ),
            ],
          ),
          if (!_cycleKnown) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(() => _cycleKnown = true),
              child: Text(context.tr('women.activation.enterCycleLength')),
            ),
          ],
          const Spacer(flex: 2),
        ],
      );

  Widget _periodStep() => Column(
        children: [
          const Spacer(),
          _question(
            Icons.water_drop_outlined,
            context.tr('women.activation.periodTitle'),
            context.tr('women.activation.periodDescription'),
          ),
          const SizedBox(height: 18),
          if (_periodKnown)
            _numberSelector(
              value: _periodLength,
              min: 1,
              max: 10,
              suffix: context.tr('women.activation.days'),
              onChanged: (value) => setState(() => _periodLength = value),
            ),
          const SizedBox(height: 14),
          _compactChoice(
            label: context.tr('women.activation.periodNotSure'),
            selected: !_periodKnown,
            onTap: () => setState(() => _periodKnown = !_periodKnown),
          ),
          const Spacer(flex: 2),
        ],
      );

  Widget _dateStep() => Column(
        children: [
          const Spacer(),
          _question(
            Icons.event_outlined,
            context.tr('women.activation.dateTitle'),
            context.tr('women.activation.dateDescription'),
          ),
          const SizedBox(height: 24),
          Semantics(
            button: true,
            label: context.tr('women.activation.dateSemantic'),
            child: OutlinedButton.icon(
              onPressed: _pickLastPeriod,
              icon: const Icon(Icons.calendar_today_rounded),
              label: Text(
                _lastPeriodStart == null
                    ? context.tr('women.activation.chooseDate')
                    : formatAppDate(context, _lastPeriodStart!),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: _theme.error)),
          ],
          const Spacer(flex: 2),
        ],
      );

  Widget _regularityStep() => Column(
        children: [
          const Spacer(),
          _question(
            Icons.insights_outlined,
            context.tr('women.activation.regularityTitle'),
            context.tr('women.activation.regularityDescription'),
          ),
          const SizedBox(height: 18),
          _option('regular', context.tr('women.activation.regular')),
          const SizedBox(height: 10),
          _option('irregular', context.tr('women.activation.irregular')),
          const SizedBox(height: 10),
          _option('unknown', context.tr('women.activation.notSureYet')),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: _theme.error)),
          ],
          const Spacer(flex: 2),
        ],
      );

  Widget _option(String value, String label) => LifeMateOnboardingOptionCard(
        theme: _theme,
        title: label,
        selected: _regularity == value,
        onTap: () => setState(() => _regularity = value),
      );

  Widget _numberSelector({
    required int value,
    required int min,
    required int max,
    required String suffix,
    required ValueChanged<int> onChanged,
  }) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: _theme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _theme.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: context.tr('common.decrease'),
              onPressed: value <= min ? null : () => onChanged(value - 1),
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 110,
              child: Text(
                '${localizeDigits(context, value)} $suffix',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _theme.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              tooltip: context.tr('common.increase'),
              onPressed: value >= max ? null : () => onChanged(value + 1),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      );

  Widget _compactChoice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: selected ? _theme.soft : _theme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? _theme.primary : _theme.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? _theme.primary : _theme.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );

  Widget _softNote(IconData icon, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _theme.surfaceAlt,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: _theme.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: _theme.ink, height: 1.5),
              ),
            ),
          ],
        ),
      );

  Widget _question(IconData icon, String title, String description) =>
      LifeMateOnboardingQuestion(
        theme: _theme,
        icon: icon,
        title: title,
        description: description,
        alignCenter: true,
      );

  Widget _frame({
    required Widget body,
    required String primaryLabel,
    VoidCallback? onPrimary,
    bool busy = false,
    double? progress,
    String? progressLabel,
    VoidCallback? onBack,
  }) => Directionality(
        textDirection: context.lifeMateLocale.textDirection,
        child: LifeMateOnboardingScaffold(
          theme: _theme,
          title: 'Women Health',
          primaryLabel: primaryLabel,
          onPrimary: onPrimary,
          primaryBusy: busy,
          progress: progress,
          progressLabel: progressLabel,
          onBack: onBack,
          body: body,
        ),
      );
}