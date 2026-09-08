part of '../cocoonmate_module.dart';

enum CocoonMedicationLogAction { taken, skipped }

enum CocoonMedicationSubmitState { idle, submitting, queued, confirmed, error, offline }

class CocoonMedicationOption {
  const CocoonMedicationOption({
    required this.id,
    required this.name,
    required this.doseLabel,
  });

  final String id;
  final String name;
  final String doseLabel;
}

class CocoonMedicationLogDraft {
  const CocoonMedicationLogDraft({
    required this.medicationId,
    required this.action,
    required this.timeLabel,
    this.note,
  });

  final String medicationId;
  final CocoonMedicationLogAction action;
  final String timeLabel;
  final String? note;
}

class CocoonMedicationLogScreen extends StatefulWidget {
  const CocoonMedicationLogScreen({
    required this.fa,
    required this.options,
    required this.initialTimeLabel,
    required this.submitState,
    required this.onPickTime,
    required this.onSubmit,
    super.key,
  });

  final bool fa;
  final List<CocoonMedicationOption> options;
  final String initialTimeLabel;
  final CocoonMedicationSubmitState submitState;
  final Future<String?> Function() onPickTime;
  final Future<void> Function(CocoonMedicationLogDraft draft) onSubmit;

  @override
  State<CocoonMedicationLogScreen> createState() =>
      _CocoonMedicationLogScreenState();
}

class _CocoonMedicationLogScreenState
    extends State<CocoonMedicationLogScreen> {
  final _note = TextEditingController();
  String? _medicationId;
  late String _timeLabel = widget.initialTimeLabel;
  CocoonMedicationLogAction _action = CocoonMedicationLogAction.taken;
  bool _showErrors = false;

  bool get _busy =>
      widget.submitState == CocoonMedicationSubmitState.submitting;
  String t(String en, String fa) => widget.fa ? fa : en;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(t('Medication log', 'ثبت دارو و مکمل'))),
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
                      _MedicationHero(fa: widget.fa),
                      if (widget.submitState !=
                          CocoonMedicationSubmitState.idle) ...[
                        const SizedBox(height: 14),
                        _MedicationStatus(
                          fa: widget.fa,
                          state: widget.submitState,
                        ),
                      ],
                      const SizedBox(height: 28),
                      CocoonSectionHeading(
                        title: t('Medication or supplement', 'دارو یا مکمل'),
                        supporting: t(
                          'Only items already in your care plan appear here',
                          'فقط موارد موجود در برنامه مراقبتی نمایش داده می‌شوند',
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (widget.options.isEmpty)
                        _MedicationUnavailable(fa: widget.fa)
                      else
                        for (final option in widget.options) ...[
                          _MedicationOptionTile(
                            option: option,
                            selected: _medicationId == option.id,
                            enabled: !_busy,
                            onTap: () =>
                                setState(() => _medicationId = option.id),
                          ),
                          const SizedBox(height: 10),
                        ],
                      if (_showErrors && _medicationId == null) ...[
                        const SizedBox(height: 4),
                        Text(
                          t('Choose an item to continue', 'برای ادامه یک مورد انتخاب کن'),
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ],
                      if (widget.options.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          t('What happened?', 'وضعیت مصرف'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<CocoonMedicationLogAction>(
                          segments: [
                            ButtonSegment(
                              value: CocoonMedicationLogAction.taken,
                              icon: const Icon(Icons.check_circle_outline),
                              label: Text(t('Taken', 'مصرف شد')),
                            ),
                            ButtonSegment(
                              value: CocoonMedicationLogAction.skipped,
                              icon: const Icon(Icons.remove_circle_outline),
                              label: Text(t('Skipped', 'مصرف نشد')),
                            ),
                          ],
                          selected: {_action},
                          onSelectionChanged: _busy
                              ? null
                              : (value) =>
                                  setState(() => _action = value.first),
                        ),
                        const SizedBox(height: 24),
                        Semantics(
                          button: true,
                          label: t(
                            'Recorded time, $_timeLabel',
                            'زمان ثبت، $_timeLabel',
                          ),
                          child: InkWell(
                            onTap: _busy ? null : _pickTime,
                            borderRadius: BorderRadius.circular(18),
                            child: Ink(
                              padding: const EdgeInsetsDirectional.all(17),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: CocoonTheme.line),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.schedule_outlined,
                                      color: CocoonTheme.coral),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t('Recorded time', 'زمان ثبت'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium,
                                        ),
                                        Text(
                                          _timeLabel,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.expand_more_rounded),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
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
                        _MedicationBoundary(fa: widget.fa),
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
                _busy ? t('Saving…', 'در حال ثبت…') : t('Save log', 'ثبت وضعیت'),
              ),
            ),
          ),
        ),
      );

  Future<void> _pickTime() async {
    final value = await widget.onPickTime();
    if (value != null && mounted) setState(() => _timeLabel = value);
  }

  Future<void> _submit() async {
    if (_medicationId == null) {
      setState(() => _showErrors = true);
      return;
    }
    final note = _note.text.trim();
    await widget.onSubmit(
      CocoonMedicationLogDraft(
        medicationId: _medicationId!,
        action: _action,
        timeLabel: _timeLabel,
        note: note.isEmpty ? null : note,
      ),
    );
  }
}

class _MedicationOptionTile extends StatelessWidget {
  const _MedicationOptionTile({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final CocoonMedicationOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsetsDirectional.all(16),
            decoration: BoxDecoration(
              color: selected ? CocoonTheme.coralSoft : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? CocoonTheme.coral : CocoonTheme.line,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.medication_outlined,
                    color: CocoonTheme.coral),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(option.doseLabel,
                          style: Theme.of(context).textTheme.labelMedium),
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

class _MedicationHero extends StatelessWidget {
  const _MedicationHero({required this.fa});
  final bool fa;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.all(20),
        decoration: BoxDecoration(
          color: CocoonTheme.warm,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 27,
              backgroundColor: Colors.white,
              child: Icon(Icons.medication_outlined, color: CocoonTheme.coral),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fa ? 'فقط ثبت آنچه انجام شد' : 'Only log what happened',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    fa
                        ? 'بدون تغییر برنامه یا توصیه مصرف.'
                        : 'Without changing your plan or suggesting a dose.',
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

class _MedicationBoundary extends StatelessWidget {
  const _MedicationBoundary({required this.fa});
  final bool fa;
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              size: 20, color: CocoonTheme.skyStrong),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              fa
                  ? 'این صفحه فقط برای ثبت است؛ تغییر یا قطع مصرف را با پزشک یا ماما هماهنگ کن.'
                  : 'This page only records events; coordinate plan changes with your clinician.',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      );
}

class _MedicationUnavailable extends StatelessWidget {
  const _MedicationUnavailable({required this.fa});
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
              ? 'موردی از برنامه مراقبتی برای ثبت در دسترس نیست.'
              : 'No care-plan medication is available to log.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
}

class _MedicationStatus extends StatelessWidget {
  const _MedicationStatus({required this.fa, required this.state});
  final bool fa;
  final CocoonMedicationSubmitState state;
  @override
  Widget build(BuildContext context) {
    final (icon, background, text) = switch (state) {
      CocoonMedicationSubmitState.submitting =>
        (Icons.sync_rounded, CocoonTheme.sky, fa ? 'در حال ثبت امن' : 'Saving securely'),
      CocoonMedicationSubmitState.queued => (
          Icons.schedule_send_outlined,
          CocoonTheme.warm,
          fa ? 'در صف همگام‌سازی؛ هنوز تأیید نشده' : 'Queued; not yet confirmed',
        ),
      CocoonMedicationSubmitState.confirmed => (
          Icons.cloud_done_outlined,
          CocoonTheme.sage,
          fa ? 'ثبت و تأیید شد' : 'Saved and confirmed',
        ),
      CocoonMedicationSubmitState.error => (
          Icons.error_outline,
          const Color(0xFFFFE9E7),
          fa ? 'ثبت انجام نشد' : 'Not saved',
        ),
      CocoonMedicationSubmitState.offline => (
          Icons.wifi_off_outlined,
          CocoonTheme.sky,
          fa ? 'آفلاین؛ ثبت جدید در دسترس نیست' : 'Offline; new logging unavailable',
        ),
      CocoonMedicationSubmitState.idle =>
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
