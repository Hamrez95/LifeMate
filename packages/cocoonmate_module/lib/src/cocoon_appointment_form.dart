part of '../cocoonmate_module.dart';

enum CocoonAppointmentKind { checkup, ultrasound, lab, other }

enum CocoonAppointmentSubmitState { idle, submitting, queued, confirmed, error }

class CocoonAppointmentDraft {
  const CocoonAppointmentDraft({
    required this.title,
    required this.kind,
    required this.dateLabel,
    required this.timeLabel,
    required this.reminderMinutes,
    this.provider,
    this.location,
  });

  final String title;
  final CocoonAppointmentKind kind;
  final String dateLabel;
  final String timeLabel;
  final int reminderMinutes;
  final String? provider;
  final String? location;
}

class CocoonAppointmentFormScreen extends StatefulWidget {
  const CocoonAppointmentFormScreen({
    required this.fa,
    required this.submitState,
    required this.onPickDate,
    required this.onPickTime,
    required this.onSubmit,
    this.initialDateLabel,
    this.initialTimeLabel,
    super.key,
  });

  final bool fa;
  final CocoonAppointmentSubmitState submitState;
  final Future<String?> Function() onPickDate;
  final Future<String?> Function() onPickTime;
  final Future<void> Function(CocoonAppointmentDraft draft) onSubmit;
  final String? initialDateLabel;
  final String? initialTimeLabel;

  @override
  State<CocoonAppointmentFormScreen> createState() =>
      _CocoonAppointmentFormScreenState();
}

class _CocoonAppointmentFormScreenState
    extends State<CocoonAppointmentFormScreen> {
  final _title = TextEditingController();
  final _provider = TextEditingController();
  final _location = TextEditingController();
  CocoonAppointmentKind _kind = CocoonAppointmentKind.checkup;
  int _reminderMinutes = 30;
  String? _dateLabel;
  String? _timeLabel;
  bool _showErrors = false;

  bool get _busy =>
      widget.submitState == CocoonAppointmentSubmitState.submitting;
  bool get _valid =>
      _title.text.trim().isNotEmpty && _dateLabel != null && _timeLabel != null;
  String t(String en, String fa) => widget.fa ? fa : en;

  @override
  void initState() {
    super.initState();
    _dateLabel = widget.initialDateLabel;
    _timeLabel = widget.initialTimeLabel;
  }

  @override
  void dispose() {
    _title.dispose();
    _provider.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(t('New appointment', 'قرار جدید'))),
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: CocoonPagePadding(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FormIntroduction(fa: widget.fa),
                      if (widget.submitState !=
                          CocoonAppointmentSubmitState.idle) ...[
                        const SizedBox(height: 16),
                        _AppointmentFormStatus(
                          fa: widget.fa,
                          state: widget.submitState,
                        ),
                      ],
                      const SizedBox(height: 28),
                      _CocoonLabeledField(
                        label: t('Appointment title', 'عنوان قرار'),
                        supporting: t(
                          'For example: routine prenatal visit',
                          'مثلاً: ویزیت دوره‌ای بارداری',
                        ),
                        controller: _title,
                        enabled: !_busy,
                        error: _showErrors && _title.text.trim().isEmpty
                            ? t('Enter a clear title', 'یک عنوان روشن وارد کن')
                            : null,
                        icon: Icons.edit_calendar_outlined,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 24),
                      CocoonSectionHeading(
                        title: t('Type of care', 'نوع مراقبت'),
                        supporting: t(
                          'Choose the closest category',
                          'نزدیک‌ترین گزینه را انتخاب کن',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: CocoonAppointmentKind.values
                            .map(
                              (kind) => ChoiceChip(
                                selected: _kind == kind,
                                onSelected: _busy
                                    ? null
                                    : (_) => setState(() => _kind = kind),
                                label: Text(_kindLabel(kind)),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 26),
                      CocoonSectionHeading(
                        title: t('Date and time', 'تاریخ و ساعت'),
                        supporting: t(
                          'Shown in your local calendar and timezone',
                          'بر اساس تقویم و منطقه زمانی خودت',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _PickerTile(
                              icon: Icons.calendar_today_outlined,
                              label: t('Date', 'تاریخ'),
                              value: _dateLabel,
                              placeholder: t('Select', 'انتخاب'),
                              error: _showErrors && _dateLabel == null,
                              enabled: !_busy,
                              onTap: _pickDate,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PickerTile(
                              icon: Icons.schedule_outlined,
                              label: t('Time', 'ساعت'),
                              value: _timeLabel,
                              placeholder: t('Select', 'انتخاب'),
                              error: _showErrors && _timeLabel == null,
                              enabled: !_busy,
                              onTap: _pickTime,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _CocoonLabeledField(
                        label: t('Doctor or specialist', 'پزشک یا متخصص'),
                        supporting: t('Optional', 'اختیاری'),
                        controller: _provider,
                        enabled: !_busy,
                        icon: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 18),
                      _CocoonLabeledField(
                        label: t('Center or location', 'مرکز یا محل مراجعه'),
                        supporting: t('Optional', 'اختیاری'),
                        controller: _location,
                        enabled: !_busy,
                        icon: Icons.location_on_outlined,
                      ),
                      const SizedBox(height: 26),
                      CocoonSectionHeading(
                        title: t('Remind me', 'به من یادآوری کن'),
                        supporting: t(
                          'Scheduling is confirmed only after save succeeds',
                          'یادآوری فقط بعد از ثبت موفق تأیید می‌شود',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [0, 30, 60, 1440]
                            .map(
                              (minutes) => ChoiceChip(
                                selected: _reminderMinutes == minutes,
                                onSelected: _busy
                                    ? null
                                    : (_) => setState(
                                          () => _reminderMinutes = minutes,
                                        ),
                                label: Text(_reminderLabel(minutes)),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        t(
                          'No partner or caregiver reminder is created by this form.',
                          'این فرم برای همسر یا مراقب یادآوری ایجاد نمی‌کند.',
                        ),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 14),
            child: FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                _busy
                    ? t('Saving…', 'در حال ثبت…')
                    : t('Save appointment', 'ثبت قرار'),
              ),
            ),
          ),
        ),
      );

  String _kindLabel(CocoonAppointmentKind kind) => switch (kind) {
        CocoonAppointmentKind.checkup => t('Checkup', 'ویزیت'),
        CocoonAppointmentKind.ultrasound => t('Ultrasound', 'سونوگرافی'),
        CocoonAppointmentKind.lab => t('Lab', 'آزمایش'),
        CocoonAppointmentKind.other => t('Other', 'سایر'),
      };

  String _reminderLabel(int minutes) => switch (minutes) {
        0 => t('None', 'بدون یادآوری'),
        30 => t('30 min before', '۳۰ دقیقه قبل'),
        60 => t('1 hour before', '۱ ساعت قبل'),
        _ => t('1 day before', '۱ روز قبل'),
      };

  Future<void> _pickDate() async {
    final value = await widget.onPickDate();
    if (value != null && mounted) setState(() => _dateLabel = value);
  }

  Future<void> _pickTime() async {
    final value = await widget.onPickTime();
    if (value != null && mounted) setState(() => _timeLabel = value);
  }

  Future<void> _submit() async {
    if (!_valid) {
      setState(() => _showErrors = true);
      return;
    }
    await widget.onSubmit(
      CocoonAppointmentDraft(
        title: _title.text.trim(),
        kind: _kind,
        dateLabel: _dateLabel!,
        timeLabel: _timeLabel!,
        reminderMinutes: _reminderMinutes,
        provider: _optional(_provider.text),
        location: _optional(_location.text),
      ),
    );
  }

  String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _FormIntroduction extends StatelessWidget {
  const _FormIntroduction({required this.fa});
  final bool fa;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.all(18),
        decoration: BoxDecoration(
          color: CocoonTheme.sage,
          borderRadius: BorderRadius.circular(22),
          border:
              Border.all(color: CocoonTheme.sageStrong.withValues(alpha: .2)),
          boxShadow: CocoonElevation.subtle,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CocoonBrandMark(
              semanticLabel: fa ? 'کوکون‌میت' : 'CocoonMate',
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                fa
                    ? 'فقط اطلاعات لازم را وارد کن؛ جزئیات اختیاری را هر زمان می‌توانی کامل کنی.'
                    : 'Add only what you need. Optional details can be completed later.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
}

class _CocoonLabeledField extends StatelessWidget {
  const _CocoonLabeledField({
    required this.label,
    required this.supporting,
    required this.controller,
    required this.enabled,
    required this.icon,
    this.error,
    this.onChanged,
  });
  final String label;
  final String supporting;
  final TextEditingController controller;
  final bool enabled;
  final IconData icon;
  final String? error;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          helperText: supporting,
          errorText: error,
          prefixIcon: Icon(icon),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: CocoonTheme.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: CocoonTheme.line),
          ),
        ),
      );
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.error,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String? value;
  final String placeholder;
  final bool error;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label + '، ' + (value ?? placeholder),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsetsDirectional.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: error ? const Color(0xFFB42318) : CocoonTheme.line,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: CocoonTheme.coral),
                const SizedBox(height: 9),
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 3),
                Text(
                  value ?? placeholder,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color:
                            value == null ? CocoonTheme.muted : CocoonTheme.ink,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _AppointmentFormStatus extends StatelessWidget {
  const _AppointmentFormStatus({required this.fa, required this.state});
  final bool fa;
  final CocoonAppointmentSubmitState state;
  @override
  Widget build(BuildContext context) {
    final (icon, background, foreground, text) = switch (state) {
      CocoonAppointmentSubmitState.submitting => (
          Icons.sync_rounded,
          CocoonTheme.sky,
          CocoonTheme.skyStrong,
          fa ? 'در حال ثبت امن قرار' : 'Saving securely',
        ),
      CocoonAppointmentSubmitState.queued => (
          Icons.schedule_send_outlined,
          CocoonTheme.warm,
          CocoonTheme.gold,
          fa
              ? 'در صف همگام‌سازی؛ هنوز تأیید نشده'
              : 'Queued; not yet confirmed',
        ),
      CocoonAppointmentSubmitState.confirmed => (
          Icons.cloud_done_outlined,
          CocoonTheme.sage,
          CocoonTheme.sageStrong,
          fa ? 'قرار ثبت و تأیید شد' : 'Appointment confirmed',
        ),
      CocoonAppointmentSubmitState.error => (
          Icons.error_outline,
          const Color(0xFFFFE9E7),
          const Color(0xFFB42318),
          fa ? 'ثبت انجام نشد؛ دوباره تلاش کن' : 'Not saved; try again',
        ),
      CocoonAppointmentSubmitState.idle => (
          Icons.info_outline,
          CocoonTheme.cream,
          CocoonTheme.muted,
          '',
        ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsetsDirectional.all(13),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
