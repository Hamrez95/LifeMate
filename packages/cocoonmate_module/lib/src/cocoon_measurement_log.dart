part of '../cocoonmate_module.dart';

enum CocoonMeasurementSubmitState { idle, submitting, queued, confirmed, error, offline }

class CocoonMeasurementFieldSpec {
  const CocoonMeasurementFieldSpec({
    required this.id,
    required this.label,
    required this.unit,
    this.hint,
  });

  final String id;
  final String label;
  final String unit;
  final String? hint;
}

class CocoonMeasurementOption {
  const CocoonMeasurementOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.fields,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<CocoonMeasurementFieldSpec> fields;
}

class CocoonMeasurementDraft {
  const CocoonMeasurementDraft({
    required this.metricId,
    required this.values,
    this.note,
  });

  final String metricId;
  final Map<String, String> values;
  final String? note;
}

class CocoonMeasurementLogScreen extends StatefulWidget {
  const CocoonMeasurementLogScreen({
    required this.fa,
    required this.options,
    required this.submitState,
    required this.onSubmit,
    super.key,
  });

  final bool fa;
  final List<CocoonMeasurementOption> options;
  final CocoonMeasurementSubmitState submitState;
  final Future<void> Function(CocoonMeasurementDraft draft) onSubmit;

  @override
  State<CocoonMeasurementLogScreen> createState() =>
      _CocoonMeasurementLogScreenState();
}

class _CocoonMeasurementLogScreenState
    extends State<CocoonMeasurementLogScreen> {
  final _note = TextEditingController();
  final Map<String, TextEditingController> _values = {};
  CocoonMeasurementOption? _option;
  bool _showErrors = false;

  bool get _busy =>
      widget.submitState == CocoonMeasurementSubmitState.submitting;
  String t(String en, String fa) => widget.fa ? fa : en;

  @override
  void dispose() {
    _note.dispose();
    for (final controller in _values.values) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(t('Add measurement', 'ثبت اندازه‌گیری'))),
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
                      _MeasurementHero(fa: widget.fa),
                      if (widget.submitState !=
                          CocoonMeasurementSubmitState.idle) ...[
                        const SizedBox(height: 14),
                        _MeasurementStatus(
                          fa: widget.fa,
                          state: widget.submitState,
                        ),
                      ],
                      const SizedBox(height: 28),
                      CocoonSectionHeading(
                        title: t('Measurement type', 'نوع اندازه‌گیری'),
                        supporting: t(
                          'Only available record types are shown',
                          'فقط داده‌های قابل ثبت نمایش داده می‌شوند',
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (widget.options.isEmpty)
                        _MeasurementUnavailable(fa: widget.fa)
                      else
                        Wrap(
                          spacing: 9,
                          runSpacing: 9,
                          children: widget.options
                              .map(
                                (option) => ChoiceChip(
                                  avatar: Icon(option.icon, size: 18),
                                  selected: _option?.id == option.id,
                                  onSelected: _busy
                                      ? null
                                      : (_) => _selectOption(option),
                                  label: Text(option.label),
                                ),
                              )
                              .toList(),
                        ),
                      if (_showErrors && _option == null) ...[
                        const SizedBox(height: 8),
                        _FieldError(
                          text: t('Choose a measurement type', 'نوع اندازه‌گیری را انتخاب کن'),
                        ),
                      ],
                      if (_option != null) ...[
                        const SizedBox(height: 30),
                        CocoonSectionHeading(
                          title: t('Value', 'مقدار'),
                          supporting: t(
                            'Use the unit shown beside each field',
                            'مقدار را با واحد کنار هر فیلد وارد کن',
                          ),
                        ),
                        const SizedBox(height: 14),
                        for (final field in _option!.fields) ...[
                          _MeasurementValueField(
                            spec: field,
                            controller: _controller(field.id),
                            enabled: !_busy,
                            error: _showErrors &&
                                _controller(field.id).text.trim().isEmpty,
                            fa: widget.fa,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 14),
                        ],
                        const SizedBox(height: 8),
                        TextField(
                          controller: _note,
                          enabled: !_busy,
                          maxLength: 300,
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: t('Personal note', 'یادداشت شخصی'),
                            helperText: t('Optional', 'اختیاری'),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _MeasurementPrivacy(fa: widget.fa),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFFFDFC),
              border: Border(top: BorderSide(color: CocoonTheme.line)),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(20, 11, 20, 14),
            child: FilledButton.icon(
              onPressed: _busy || widget.options.isEmpty ? null : _submit,
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
                    : t('Save measurement', 'ثبت اندازه‌گیری'),
              ),
            ),
          ),
        ),
      );

  TextEditingController _controller(String id) =>
      _values.putIfAbsent(id, TextEditingController.new);

  void _selectOption(CocoonMeasurementOption option) {
    setState(() {
      _option = option;
      _showErrors = false;
    });
  }

  Future<void> _submit() async {
    final option = _option;
    final valid = option != null &&
        option.fields.every(
          (field) => _controller(field.id).text.trim().isNotEmpty,
        );
    if (!valid) {
      setState(() => _showErrors = true);
      return;
    }
    final note = _note.text.trim();
    await widget.onSubmit(
      CocoonMeasurementDraft(
        metricId: option.id,
        values: {
          for (final field in option.fields)
            field.id: _controller(field.id).text.trim(),
        },
        note: note.isEmpty ? null : note,
      ),
    );
  }
}

class _MeasurementHero extends StatelessWidget {
  const _MeasurementHero({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.all(20),
        decoration: BoxDecoration(
          color: CocoonTheme.sage,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 27,
              backgroundColor: Colors.white,
              child: Icon(Icons.monitor_weight_outlined,
                  color: CocoonTheme.sageStrong),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fa ? 'داده‌ای برای دیدن روند' : 'A data point for your trend',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    fa
                        ? 'واحد و ساختار هر داده از پرونده سلامت می‌آید.'
                        : 'Each field and unit comes from your health record schema.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: CocoonTheme.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _MeasurementValueField extends StatelessWidget {
  const _MeasurementValueField({
    required this.spec,
    required this.controller,
    required this.enabled,
    required this.error,
    required this.fa,
    required this.onChanged,
  });
  final CocoonMeasurementFieldSpec spec;
  final TextEditingController controller;
  final bool enabled;
  final bool error;
  final bool fa;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        onChanged: onChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: spec.label,
          hintText: spec.hint,
          errorText: error ? (fa ? 'مقدار را وارد کن' : 'Enter a value') : null,
          suffixText: spec.unit,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      );
}

class _FieldError extends StatelessWidget {
  const _FieldError({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
      );
}

class _MeasurementPrivacy extends StatelessWidget {
  const _MeasurementPrivacy({required this.fa});
  final bool fa;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded,
              size: 20, color: CocoonTheme.sageStrong),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              fa
                  ? 'ثبت داده به‌تنهایی دسترسی جدیدی برای همسر یا مراقب ایجاد نمی‌کند.'
                  : 'Logging data does not grant new partner or caregiver access.',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      );
}

class _MeasurementUnavailable extends StatelessWidget {
  const _MeasurementUnavailable({required this.fa});
  final bool fa;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.all(16),
        decoration: BoxDecoration(
          color: CocoonTheme.sky,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          fa
              ? 'ساختار تأییدشده اندازه‌گیری در دسترس نیست؛ ثبت جدید غیرفعال است.'
              : 'The approved measurement schema is unavailable; new logging is disabled.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
}

class _MeasurementStatus extends StatelessWidget {
  const _MeasurementStatus({required this.fa, required this.state});
  final bool fa;
  final CocoonMeasurementSubmitState state;

  @override
  Widget build(BuildContext context) {
    final (icon, background, text) = switch (state) {
      CocoonMeasurementSubmitState.submitting =>
        (Icons.sync_rounded, CocoonTheme.sky, fa ? 'در حال ثبت امن' : 'Saving securely'),
      CocoonMeasurementSubmitState.queued => (
          Icons.schedule_send_outlined,
          CocoonTheme.warm,
          fa ? 'در صف همگام‌سازی؛ هنوز تأیید نشده' : 'Queued; not yet confirmed',
        ),
      CocoonMeasurementSubmitState.confirmed => (
          Icons.cloud_done_outlined,
          CocoonTheme.sage,
          fa ? 'ثبت و تأیید شد' : 'Saved and confirmed',
        ),
      CocoonMeasurementSubmitState.error => (
          Icons.error_outline,
          const Color(0xFFFFE9E7),
          fa ? 'ثبت انجام نشد' : 'Not saved',
        ),
      CocoonMeasurementSubmitState.offline => (
          Icons.wifi_off_outlined,
          CocoonTheme.sky,
          fa ? 'آفلاین؛ ثبت جدید در دسترس نیست' : 'Offline; new logging unavailable',
        ),
      CocoonMeasurementSubmitState.idle =>
        (Icons.info_outline, CocoonTheme.cream, ''),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsetsDirectional.all(13),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 9),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
