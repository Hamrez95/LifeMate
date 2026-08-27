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

  bool get _isPersian => LifeMateRuntimeLocale.isPersian;

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
        _error = LifeMateRuntimeLocale.select(
          fa: 'اطلاعات تقویم دریافت نشد. دوباره تلاش کن.',
          en: 'Cycle information could not be loaded. Try again.',
        );
      });
    }
  }

  void _next() {
    if (_step == 3 && _lastPeriodStart == null) {
      setState(() {
        _error = LifeMateRuntimeLocale.select(
          fa: 'اولین روز آخرین پریود را انتخاب کن.',
          en: 'Select the first day of your last period.',
        );
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
      title: LifeMateRuntimeLocale.select(
        fa: 'اولین روز آخرین پریود',
        en: 'First day of your last period',
      ),
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
        _error = LifeMateRuntimeLocale.select(
          fa: 'فعال‌سازی ذخیره نشد. اتصال را بررسی کن.',
          en: 'Activation was not saved. Check your connection.',
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = LifeMateRuntimeLocale.select(
          fa: 'فعال‌سازی ذخیره نشد. دوباره تلاش کن.',
          en: 'Activation was not saved. Try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _frame(
        body: _question(
          Icons.favorite_outline_rounded,
          LifeMateRuntimeLocale.select(
            fa: 'Women Health را آماده می‌کنیم',
            en: 'Preparing Women Health',
          ),
          LifeMateRuntimeLocale.select(fa: 'چند لحظه صبر کن.', en: 'One moment.'),
        ),
        primaryLabel: LifeMateRuntimeLocale.select(
          fa: 'در حال آماده‌سازی',
          en: 'Preparing',
        ),
        busy: true,
      );
    }
    if (_profile == null) {
      return _frame(
        body: _question(
          Icons.cloud_off_outlined,
          LifeMateRuntimeLocale.select(
            fa: 'فعلاً اطلاعات در دسترس نیست',
            en: 'Information is unavailable',
          ),
          _error ?? '',
        ),
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'تلاش دوباره', en: 'Try again'),
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
          ? LifeMateRuntimeLocale.select(
              fa: 'ورود به تقویم بانوان',
              en: 'Open Period Calendar',
            )
          : LifeMateRuntimeLocale.select(fa: 'ادامه', en: 'Continue'),
      onPrimary: _saving ? null : _next,
      busy: _saving,
      progress: (_step + 1) / 5,
      progressLabel: _isPersian ? '${_step + 1} از ۵' : '${_step + 1} of 5',
      onBack: _step == 0 ? null : _back,
    );
  }

  Widget _activationStep() => Column(
        children: [
          const Spacer(),
          _question(
            Icons.calendar_month_outlined,
            LifeMateRuntimeLocale.select(
              fa: 'تقویم بانوان را فعال می‌کنی؟',
              en: 'Activate Period Calendar?',
            ),
            LifeMateRuntimeLocale.select(
              fa: 'فقط چند داده پایه چرخه را می‌پرسیم. Mood، علائم، یادداشت خصوصی و هدف باروری جزو این مرحله نیستند.',
              en: 'We only ask for basic cycle data. Mood, symptoms, private notes and fertility intent are not part of activation.',
            ),
          ),
          const SizedBox(height: 22),
          _softNote(
            Icons.lock_outline_rounded,
            LifeMateRuntimeLocale.select(
              fa: 'این اطلاعات در همان پروفایل واقعی Period Calendar ذخیره می‌شود و بعداً قابل ویرایش است.',
              en: 'This is saved in the real Period Calendar profile and remains editable later.',
            ),
          ),
          const Spacer(flex: 2),
        ],
      );

  Widget _cycleStep() => Column(
        children: [
          const Spacer(),
          _question(
            Icons.rotate_right_rounded,
            LifeMateRuntimeLocale.select(
              fa: 'چرخه‌ات معمولاً چند روزه است؟',
              en: 'How long is your cycle usually?',
            ),
            _cycleKnown
                ? LifeMateRuntimeLocale.select(
                    fa: 'اگر می‌دانی، عدد را تنظیم کن.',
                    en: 'Adjust the number if you know it.',
                  )
                : LifeMateRuntimeLocale.select(
                    fa: 'یک مقدار سازگاری برای موتور نگه می‌داریم، اما آن را به‌عنوان عدد معلوم تو نمایش نمی‌دهیم.',
                    en: 'A compatibility value is retained for the engine, but it is not presented as a known value.',
                  ),
          ),
          const SizedBox(height: 18),
          if (_cycleKnown) _numberSelector(
            value: _cycleLength,
            min: 21,
            max: 45,
            suffix: LifeMateRuntimeLocale.select(fa: 'روز', en: 'days'),
            onChanged: (value) => setState(() => _cycleLength = value),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _compactChoice(
                  label: LifeMateRuntimeLocale.select(fa: 'نمی‌دانم', en: 'I’m not sure'),
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
                  label: LifeMateRuntimeLocale.select(fa: 'نامنظم است', en: 'It’s irregular'),
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
              child: Text(LifeMateRuntimeLocale.select(
                fa: 'عدد چرخه را وارد می‌کنم',
                en: 'I know the cycle length',
              )),
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
            LifeMateRuntimeLocale.select(
              fa: 'پریود معمولاً چند روز طول می‌کشد؟',
              en: 'How long does your period usually last?',
            ),
            LifeMateRuntimeLocale.select(
              fa: 'اگر مطمئن نیستی، می‌توانی «مطمئن نیستم» را انتخاب کنی.',
              en: 'Choose “Not sure” if you do not know yet.',
            ),
          ),
          const SizedBox(height: 18),
          if (_periodKnown) _numberSelector(
            value: _periodLength,
            min: 1,
            max: 10,
            suffix: LifeMateRuntimeLocale.select(fa: 'روز', en: 'days'),
            onChanged: (value) => setState(() => _periodLength = value),
          ),
          const SizedBox(height: 14),
          _compactChoice(
            label: LifeMateRuntimeLocale.select(fa: 'مطمئن نیستم', en: 'Not sure'),
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
            LifeMateRuntimeLocale.select(
              fa: 'اولین روز آخرین پریود چه تاریخی بود؟',
              en: 'When did your last period start?',
            ),
            LifeMateRuntimeLocale.select(
              fa: 'در رابط فارسی، انتخاب تاریخ با تقویم شمسی انجام می‌شود و به تاریخ canonical تبدیل می‌شود.',
              en: 'The date is stored canonically after selection.',
            ),
          ),
          const SizedBox(height: 24),
          Semantics(
            button: true,
            label: LifeMateRuntimeLocale.select(
              fa: 'انتخاب اولین روز آخرین پریود',
              en: 'Select first day of last period',
            ),
            child: OutlinedButton.icon(
              onPressed: _pickLastPeriod,
              icon: const Icon(Icons.calendar_today_rounded),
              label: Text(
                _lastPeriodStart == null
                    ? LifeMateRuntimeLocale.select(fa: 'انتخاب تاریخ', en: 'Choose date')
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
            LifeMateRuntimeLocale.select(
              fa: 'چرخه‌ات چقدر منظم است؟',
              en: 'How regular is your cycle?',
            ),
            LifeMateRuntimeLocale.select(
              fa: 'این پاسخ فقط توصیف خودت از چرخه است؛ از آن هدف باروری یا مجوز پزشکی استنباط نمی‌کنیم.',
              en: 'This is only your description of cycle regularity; we do not infer fertility intent or medical permission.',
            ),
          ),
          const SizedBox(height: 18),
          _option('regular', LifeMateRuntimeLocale.select(fa: 'معمولاً منظم', en: 'Usually regular')),
          const SizedBox(height: 10),
          _option('irregular', LifeMateRuntimeLocale.select(fa: 'نامنظم', en: 'Irregular')),
          const SizedBox(height: 10),
          _option('unknown', LifeMateRuntimeLocale.select(fa: 'هنوز مطمئن نیستم', en: 'Not sure yet')),
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
              tooltip: LifeMateRuntimeLocale.select(fa: 'کمتر', en: 'Decrease'),
              onPressed: value <= min ? null : () => onChanged(value - 1),
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 110,
              child: Text(
                '$value $suffix',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _theme.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              tooltip: LifeMateRuntimeLocale.select(fa: 'بیشتر', en: 'Increase'),
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
              child: Text(text, style: TextStyle(color: _theme.ink, height: 1.5)),
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
        textDirection: _isPersian ? TextDirection.rtl : TextDirection.ltr,
        child: LifeMateOnboardingScaffold(
          theme: _theme,
          title: LifeMateRuntimeLocale.select(
            fa: 'Women Health',
            en: 'Women Health',
          ),
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
