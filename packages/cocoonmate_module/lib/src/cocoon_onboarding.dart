part of '../cocoonmate_module.dart';

enum CocoonDatingSource { lastPeriod, estimatedDueDate, ultrasound }

enum CocoonPregnancyMultiplicity { notSpecified, singleton, multiple }

enum CocoonPregnancyActivationState { idle, submitting, error }

class CocoonPregnancyDateSelection {
  const CocoonPregnancyDateSelection({
    required this.value,
    required this.displayLabel,
    required this.semanticLabel,
  });

  final DateTime value;
  final String displayLabel;
  final String semanticLabel;
}

class CocoonPregnancySetupDraft {
  const CocoonPregnancySetupDraft({
    required this.datingSource,
    required this.date,
    required this.multiplicity,
    required this.timezone,
  });

  final CocoonDatingSource datingSource;
  final CocoonPregnancyDateSelection date;
  final CocoonPregnancyMultiplicity multiplicity;
  final String timezone;
}

class CocoonPregnancyOnboardingScreen extends StatefulWidget {
  const CocoonPregnancyOnboardingScreen({
    required this.fa,
    required this.timezone,
    required this.onPickDate,
    required this.onActivate,
    this.activationState = CocoonPregnancyActivationState.idle,
    super.key,
  });

  final bool fa;
  final String timezone;
  final CocoonPregnancyActivationState activationState;
  final Future<CocoonPregnancyDateSelection?> Function(
    CocoonDatingSource source,
  ) onPickDate;
  final Future<bool> Function(CocoonPregnancySetupDraft draft) onActivate;

  @override
  State<CocoonPregnancyOnboardingScreen> createState() =>
      _CocoonPregnancyOnboardingScreenState();
}

class _CocoonPregnancyOnboardingScreenState
    extends State<CocoonPregnancyOnboardingScreen> {
  int _step = 0;
  CocoonDatingSource? _source;
  CocoonPregnancyDateSelection? _date;
  CocoonPregnancyMultiplicity _multiplicity =
      CocoonPregnancyMultiplicity.notSpecified;
  CocoonPregnancyActivationState? _localActivationState;

  bool get _busy =>
      (_localActivationState ?? widget.activationState) ==
      CocoonPregnancyActivationState.submitting;
  CocoonPregnancyActivationState get _activationState =>
      _localActivationState ?? widget.activationState;
  String t(String en, String fa) => widget.fa ? fa : en;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _step == 0 && !_busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _step > 0 && !_busy) setState(() => _step--);
        },
        child: Scaffold(
          appBar: AppBar(
            leading: _step == 0
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: t('Back', 'بازگشت'),
                    onPressed: _busy ? null : () => setState(() => _step--),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
            title: Text(t('Pregnancy setup', 'شروع همراهی بارداری')),
            actions: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 20),
                child: Center(
                  child: Text(
                    t('${_step + 1} of 4',
                        '${cocoonDigits('${_step + 1}', true)} از ۴'),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(5),
              child: Semantics(
                label: t(
                  'Step ${_step + 1} of 4',
                  'مرحله ${cocoonDigits('${_step + 1}', true)} از ۴',
                ),
                child: LinearProgressIndicator(
                  value: (_step + 1) / 4,
                  minHeight: 5,
                  color: CocoonTheme.coral,
                  backgroundColor: CocoonTheme.coralSoft,
                ),
              ),
            ),
          ),
          body: SafeArea(
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: SingleChildScrollView(
                key: ValueKey(_step),
                padding: const EdgeInsetsDirectional.fromSTEB(24, 28, 24, 140),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: switch (_step) {
                    0 => _WelcomeStep(fa: widget.fa),
                    1 => _DatingSourceStep(
                        fa: widget.fa,
                        value: _source,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  _source = value;
                                  _date = null;
                                }),
                      ),
                    2 => _PregnancyDetailsStep(
                        fa: widget.fa,
                        source: _source!,
                        date: _date,
                        multiplicity: _multiplicity,
                        timezone: widget.timezone,
                        enabled: !_busy,
                        onPickDate: _pickDate,
                        onMultiplicityChanged: (value) =>
                            setState(() => _multiplicity = value),
                      ),
                    _ => _ReviewStep(
                        fa: widget.fa,
                        source: _source!,
                        date: _date!,
                        multiplicity: _multiplicity,
                        timezone: widget.timezone,
                        hasError: _activationState ==
                            CocoonPregnancyActivationState.error,
                      ),
                  },
                ),
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFFFDFC),
                border: Border(top: BorderSide(color: CocoonTheme.line)),
              ),
              padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 14),
              child: FilledButton.icon(
                onPressed: _canContinue ? _continue : null,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(_step == 3
                        ? Icons.favorite_rounded
                        : Icons.arrow_forward_rounded),
                label: Text(
                  _busy
                      ? t('Activating…', 'در حال فعال‌سازی…')
                      : _step == 3
                          ? t('Start my pregnancy journey', 'شروع همراهی من')
                          : t('Continue', 'ادامه'),
                ),
              ),
            ),
          ),
        ),
      );

  bool get _canContinue =>
      !_busy &&
      switch (_step) {
        0 => true,
        1 => _source != null,
        2 => _date != null,
        _ => true,
      };

  Future<void> _pickDate() async {
    final selection = await widget.onPickDate(_source!);
    if (selection != null && mounted) setState(() => _date = selection);
  }

  Future<void> _continue() async {
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    setState(() =>
        _localActivationState = CocoonPregnancyActivationState.submitting);
    try {
      final activated = await widget.onActivate(
        CocoonPregnancySetupDraft(
          datingSource: _source!,
          date: _date!,
          multiplicity: _multiplicity,
          timezone: widget.timezone,
        ),
      );
      if (!mounted) return;
      if (activated) {
        Navigator.of(context).pop();
      } else {
        setState(
            () => _localActivationState = CocoonPregnancyActivationState.error);
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _localActivationState = CocoonPregnancyActivationState.error);
      }
    }
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                color: CocoonTheme.warm,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.spa_outlined,
                size: 48,
                color: CocoonTheme.coral,
              ),
            ),
          ),
          const SizedBox(height: 34),
          Text(
            fa
                ? 'این مسیر برای تو ساخته می‌شود'
                : 'A journey shaped around you',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 16),
          Text(
            fa
                ? 'با چند پاسخ کوتاه، زمان‌بندی بارداری را آماده می‌کنیم. پیش از فعال‌سازی همه‌چیز را مرور خواهی کرد.'
                : 'A few short answers prepare your pregnancy timeline. You will review everything before activation.',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: CocoonTheme.muted),
          ),
          const SizedBox(height: 30),
          _OnboardingAssurance(
            icon: Icons.lock_outline_rounded,
            text: fa
                ? 'اطلاعات به پرونده محافظت‌شده LifeMate متصل می‌ماند.'
                : 'Information stays connected to your protected LifeMate record.',
          ),
          const SizedBox(height: 12),
          _OnboardingAssurance(
            icon: Icons.people_outline_rounded,
            text: fa
                ? 'هیچ دسترسی برای همسر یا مراقب خودکار فعال نمی‌شود.'
                : 'Partner or caregiver access is never enabled automatically.',
          ),
        ],
      );
}

class _OnboardingAssurance extends StatelessWidget {
  const _OnboardingAssurance({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: CocoonTheme.sage,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: CocoonTheme.sageStrong),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(top: 9),
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
        ],
      );
}

class _DatingSourceStep extends StatelessWidget {
  const _DatingSourceStep({
    required this.fa,
    required this.value,
    required this.onChanged,
  });

  final bool fa;
  final CocoonDatingSource? value;
  final ValueChanged<CocoonDatingSource>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            fa
                ? 'زمان‌بندی را از کجا می‌دانی؟'
                : 'How is your pregnancy dated?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            fa
                ? 'گزینه‌ای را انتخاب کن که همین حالا در اختیار داری.'
                : 'Choose the information you have right now.',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: CocoonTheme.muted),
          ),
          const SizedBox(height: 26),
          for (final source in CocoonDatingSource.values) ...[
            _DatingSourceTile(
              fa: fa,
              source: source,
              selected: value == source,
              onTap: onChanged == null ? null : () => onChanged!(source),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          Text(
            fa
                ? 'اگر تاریخ سونوگرافی با تاریخ قبلی فرق دارد، منبعی را انتخاب کن که پزشک یا ماما برای زمان‌بندی تأیید کرده است.'
                : 'If ultrasound dating differs, choose the source your clinician uses for your care timeline.',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      );
}

class _DatingSourceTile extends StatelessWidget {
  const _DatingSourceTile({
    required this.fa,
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final bool fa;
  final CocoonDatingSource source;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = switch (source) {
      CocoonDatingSource.lastPeriod => (
          Icons.water_drop_outlined,
          fa ? 'اولین روز آخرین قاعدگی' : 'First day of last period',
          fa ? 'LMP' : 'LMP',
        ),
      CocoonDatingSource.estimatedDueDate => (
          Icons.flag_outlined,
          fa ? 'تاریخ احتمالی زایمان' : 'Estimated due date',
          fa ? 'EDD' : 'EDD',
        ),
      CocoonDatingSource.ultrasound => (
          Icons.monitor_heart_outlined,
          fa ? 'تاریخ‌گذاری سونوگرافی' : 'Ultrasound dating',
          fa ? 'تاریخ ثبت‌شده در گزارش' : 'Date from your report',
        ),
    };
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsetsDirectional.all(18),
          decoration: BoxDecoration(
            color: selected ? CocoonTheme.coralSoft : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? CocoonTheme.coral : CocoonTheme.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? CocoonTheme.coral : CocoonTheme.muted),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(body, style: Theme.of(context).textTheme.labelMedium),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? CocoonTheme.coral : CocoonTheme.line,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PregnancyDetailsStep extends StatelessWidget {
  const _PregnancyDetailsStep({
    required this.fa,
    required this.source,
    required this.date,
    required this.multiplicity,
    required this.timezone,
    required this.enabled,
    required this.onPickDate,
    required this.onMultiplicityChanged,
  });

  final bool fa;
  final CocoonDatingSource source;
  final CocoonPregnancyDateSelection? date;
  final CocoonPregnancyMultiplicity multiplicity;
  final String timezone;
  final bool enabled;
  final VoidCallback onPickDate;
  final ValueChanged<CocoonPregnancyMultiplicity> onMultiplicityChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            switch (source) {
              CocoonDatingSource.lastPeriod =>
                fa ? 'تاریخ آخرین قاعدگی' : 'Last period date',
              CocoonDatingSource.estimatedDueDate =>
                fa ? 'تاریخ احتمالی زایمان' : 'Estimated due date',
              CocoonDatingSource.ultrasound =>
                fa ? 'تاریخ سونوگرافی' : 'Ultrasound date',
            },
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            fa
                ? 'تاریخ را با تقویم محلی خودت انتخاب کن.'
                : 'Choose the date using your local calendar.',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: CocoonTheme.muted),
          ),
          const SizedBox(height: 24),
          Semantics(
            button: true,
            label: date?.semanticLabel ?? (fa ? 'انتخاب تاریخ' : 'Select date'),
            child: InkWell(
              onTap: enabled ? onPickDate : null,
              borderRadius: BorderRadius.circular(22),
              child: Ink(
                padding: const EdgeInsetsDirectional.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: date == null ? CocoonTheme.line : CocoonTheme.coral,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_outlined,
                        color: CocoonTheme.coral),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        date?.displayLabel ??
                            (fa ? 'انتخاب تاریخ' : 'Select date'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const Icon(Icons.expand_more_rounded),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            fa ? 'نوع بارداری (اختیاری)' : 'Pregnancy type (optional)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            fa
                ? 'اگر هنوز مشخص نیست، می‌توانی بعداً کاملش کنی.'
                : 'If you are unsure, you can add this later.',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CocoonPregnancyMultiplicity.values
                .map(
                  (value) => ChoiceChip(
                    selected: multiplicity == value,
                    onSelected:
                        enabled ? (_) => onMultiplicityChanged(value) : null,
                    label: Text(switch (value) {
                      CocoonPregnancyMultiplicity.notSpecified =>
                        fa ? 'فعلاً نمی‌دانم' : 'Not sure yet',
                      CocoonPregnancyMultiplicity.singleton =>
                        fa ? 'تک‌قلویی' : 'Singleton',
                      CocoonPregnancyMultiplicity.multiple =>
                        fa ? 'چندقلویی' : 'Multiple',
                    }),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 28),
          _OnboardingAssurance(
            icon: Icons.public_outlined,
            text: fa ? 'منطقه زمانی: $timezone' : 'Timezone: $timezone',
          ),
        ],
      );
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.fa,
    required this.source,
    required this.date,
    required this.multiplicity,
    required this.timezone,
    required this.hasError,
  });

  final bool fa;
  final CocoonDatingSource source;
  final CocoonPregnancyDateSelection date;
  final CocoonPregnancyMultiplicity multiplicity;
  final String timezone;
  final bool hasError;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            fa ? 'یک مرور کوتاه' : 'A quick review',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            fa
                ? 'تا تأیید نهایی، هیچ بارداری فعالی ساخته نمی‌شود.'
                : 'No active pregnancy is created until you confirm.',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: CocoonTheme.muted),
          ),
          if (hasError) ...[
            const SizedBox(height: 18),
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsetsDirectional.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE9E7),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFB42318)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        fa
                            ? 'فعال‌سازی انجام نشد؛ اطلاعاتت تغییر نکرده است.'
                            : 'Activation failed; your information was not changed.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsetsDirectional.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: CocoonTheme.line),
            ),
            child: Column(
              children: [
                _ReviewRow(
                  label: fa ? 'منبع تاریخ‌گذاری' : 'Dating source',
                  value: switch (source) {
                    CocoonDatingSource.lastPeriod =>
                      fa ? 'آخرین قاعدگی' : 'LMP',
                    CocoonDatingSource.estimatedDueDate =>
                      fa ? 'تاریخ احتمالی زایمان' : 'EDD',
                    CocoonDatingSource.ultrasound =>
                      fa ? 'سونوگرافی' : 'Ultrasound',
                  },
                ),
                const Divider(height: 28),
                _ReviewRow(
                    label: fa ? 'تاریخ' : 'Date', value: date.displayLabel),
                const Divider(height: 28),
                _ReviewRow(
                  label: fa ? 'نوع بارداری' : 'Pregnancy type',
                  value: switch (multiplicity) {
                    CocoonPregnancyMultiplicity.notSpecified =>
                      fa ? 'بعداً مشخص می‌کنم' : 'Add later',
                    CocoonPregnancyMultiplicity.singleton =>
                      fa ? 'تک‌قلویی' : 'Singleton',
                    CocoonPregnancyMultiplicity.multiple =>
                      fa ? 'چندقلویی' : 'Multiple',
                  },
                ),
                const Divider(height: 28),
                _ReviewRow(
                    label: fa ? 'منطقه زمانی' : 'Timezone', value: timezone),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _OnboardingAssurance(
            icon: Icons.edit_calendar_outlined,
            text: fa
                ? 'هفته بارداری از منبع تاریخ‌گذاری محاسبه می‌شود و به‌صورت دستی ذخیره نمی‌شود.'
                : 'Gestational week is derived from the dating source and is never stored as a manual value.',
          ),
        ],
      );
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      );
}
