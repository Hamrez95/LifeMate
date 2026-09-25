part of '../cocoonmate_module.dart';

enum CocoonMedicationLogAction { taken, skipped }

enum CocoonMedicationSubmitState {
  idle,
  submitting,
  queued,
  confirmed,
  error,
  offline
}

class CocoonMedicationOption {
  const CocoonMedicationOption({
    required this.occurrenceId,
    required this.occurrenceVersion,
    required this.name,
    required this.doseLabel,
  });

  /// Canonical dose-occurrence identity. This is deliberately not a medication
  /// or treatment-plan id: adherence is a fact about one scheduled dose.
  final String occurrenceId;
  final int occurrenceVersion;
  final String name;
  final String doseLabel;
}

class CocoonMedicationLogDraft {
  const CocoonMedicationLogDraft({
    required this.occurrenceId,
    required this.occurrenceVersion,
    required this.action,
    required this.occurredAtUtc,
    this.note,
  });

  final String occurrenceId;
  final int occurrenceVersion;
  final CocoonMedicationLogAction action;
  final DateTime occurredAtUtc;
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
    this.onOpenTreatments,
    super.key,
  });

  final bool fa;
  final List<CocoonMedicationOption> options;
  final String initialTimeLabel;
  final CocoonMedicationSubmitState submitState;
  final Future<DateTime?> Function() onPickTime;
  final Future<void> Function(CocoonMedicationLogDraft draft) onSubmit;
  final VoidCallback? onOpenTreatments;

  @override
  State<CocoonMedicationLogScreen> createState() =>
      _CocoonMedicationLogScreenState();
}

class _CocoonMedicationLogScreenState extends State<CocoonMedicationLogScreen> {
  final _note = TextEditingController();
  String? _occurrenceId;
  late DateTime _occurredAtUtc = DateTime.now().toUtc();
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
        appBar: AppBar(
          title: Text(t('Medication log', 'ثبت دارو و مکمل')),
          actions: [
            if (widget.onOpenTreatments != null)
              IconButton(
                tooltip: t('Treatments', 'درمان‌ها'),
                onPressed: widget.onOpenTreatments,
                icon: const Icon(Icons.medication_outlined),
              ),
          ],
        ),
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
                            selected: _occurrenceId == option.occurrenceId,
                            enabled: !_busy,
                            onTap: () => setState(
                              () => _occurrenceId = option.occurrenceId,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      if (_showErrors && _occurrenceId == null) ...[
                        const SizedBox(height: 4),
                        Text(
                          t('Choose an item to continue',
                              'برای ادامه یک مورد انتخاب کن'),
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
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
                            'Recorded time, ${_timeLabel(_occurredAtUtc)}',
                            'زمان ثبت، ${_timeLabel(_occurredAtUtc)}',
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
                                          _timeLabel(_occurredAtUtc),
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
                _busy
                    ? t('Saving…', 'در حال ثبت…')
                    : t('Save log', 'ثبت وضعیت'),
              ),
            ),
          ),
        ),
      );

  Future<void> _pickTime() async {
    final value = await widget.onPickTime();
    if (value != null && mounted) {
      setState(() => _occurredAtUtc = value.toUtc());
    }
  }

  Future<void> _submit() async {
    final occurrenceId = _occurrenceId;
    if (occurrenceId == null) {
      setState(() => _showErrors = true);
      return;
    }
    final note = _note.text.trim();
    await widget.onSubmit(
      CocoonMedicationLogDraft(
        occurrenceId: occurrenceId,
        occurrenceVersion: widget.options
            .firstWhere((option) => option.occurrenceId == occurrenceId)
            .occurrenceVersion,
        action: _action,
        occurredAtUtc: _occurredAtUtc,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  String _timeLabel(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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
                const Icon(Icons.medication_outlined, color: CocoonTheme.coral),
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
          border: Border.all(color: CocoonTheme.coral.withValues(alpha: .2)),
          boxShadow: CocoonElevation.subtle,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CocoonBrandMark(
              semanticLabel: fa ? 'کوکون‌میت' : 'CocoonMate',
              size: 56,
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
      CocoonMedicationSubmitState.submitting => (
          Icons.sync_rounded,
          CocoonTheme.sky,
          fa ? 'در حال ثبت امن' : 'Saving securely'
        ),
      CocoonMedicationSubmitState.queued => (
          Icons.schedule_send_outlined,
          CocoonTheme.warm,
          fa
              ? 'در صف همگام‌سازی؛ هنوز تأیید نشده'
              : 'Queued; not yet confirmed',
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
          fa
              ? 'آفلاین؛ ثبت جدید در دسترس نیست'
              : 'Offline; new logging unavailable',
        ),
      CocoonMedicationSubmitState.idle => (
          Icons.info_outline,
          CocoonTheme.cream,
          ''
        ),
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

/// Presentation-only state for the canonical treatment feed supplied by a
/// host. This module neither derives a treatment plan nor interprets it.
enum CocoonTreatmentsLoadState { loading, ready, empty, error }

/// A host-authored representation of one active treatment.
///
/// The text fields are deliberately display values: dose, timing, status, and
/// any clinical wording remain owned by the canonical API. `id` is opaque to
/// the module and is returned untouched when a user opens an item.
class CocoonActiveTreatmentViewData {
  const CocoonActiveTreatmentViewData({
    required this.id,
    required this.title,
    required this.details,
    this.nextDoseLabel,
    this.statusLabel,
    this.isPendingSync = false,
  });

  final String id;
  final String title;
  final String details;
  final String? nextDoseLabel;
  final String? statusLabel;
  final bool isPendingSync;
}

/// Read-only active-treatment and next-dose presentation.
///
/// Mutation, plan changes, and medication recommendations stay outside this
/// surface. The host chooses which authorized canonical treatments to inject.
class CocoonTreatmentsScreen extends StatelessWidget {
  const CocoonTreatmentsScreen({
    required this.fa,
    required this.state,
    required this.items,
    required this.onRetry,
    required this.onOpenTreatment,
    super.key,
  });

  final bool fa;
  final CocoonTreatmentsLoadState state;
  final List<CocoonActiveTreatmentViewData> items;
  final VoidCallback onRetry;
  final ValueChanged<String> onOpenTreatment;

  String t(String en, String faText) => fa ? faText : en;

  @override
  Widget build(BuildContext context) {
    if (state == CocoonTreatmentsLoadState.loading) {
      return Scaffold(
        appBar: AppBar(title: Text(t('Treatments', 'درمان‌ها'))),
        body: CocoonPagePadding(
          child: CocoonLoadingState(
            semanticLabel: t('Loading treatments', 'در حال بارگذاری درمان‌ها'),
          ),
        ),
      );
    }
    if (state == CocoonTreatmentsLoadState.error && items.isEmpty) {
      return CocoonStatePage(
        icon: Icons.sync_problem_outlined,
        eyebrow: t('Treatments', 'درمان‌ها'),
        title: t(
            'Treatments could not be refreshed', 'درمان‌ها به‌روزرسانی نشدند'),
        body: t(
          'Your active treatment list is not available right now. Try again when you are connected.',
          'فهرست درمان‌های فعال اکنون در دسترس نیست. هنگام اتصال دوباره تلاش کن.',
        ),
        action: t('Try again', 'تلاش دوباره'),
        onPressed: onRetry,
      );
    }

    final showEmpty = items.isEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(t('Treatments', 'درمان‌ها'))),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 28),
          children: [
            Semantics(
              header: true,
              child: Text(
                t('Your care plan', 'برنامه مراقبتی شما'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t(
                'Shown from your approved care plan. This screen does not change a treatment or dose.',
                'موارد از برنامه مراقبتی تأییدشده نمایش داده می‌شوند. این صفحه درمان یا مقدار مصرف را تغییر نمی‌دهد.',
              ),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: CocoonTheme.muted),
            ),
            if (state == CocoonTreatmentsLoadState.error) ...[
              const SizedBox(height: 16),
              CocoonOfflineStrip(
                message: t(
                  'Showing the last available treatment list.',
                  'آخرین فهرست در دسترس درمان‌ها نمایش داده می‌شود.',
                ),
                retryLabel: t('Retry', 'تلاش دوباره'),
                onRetry: onRetry,
              ),
            ],
            const SizedBox(height: 28),
            if (showEmpty)
              CocoonEmptyState(
                icon: Icons.medication_outlined,
                title: t('No active treatments to show',
                    'درمان فعالی برای نمایش نیست'),
                body: t(
                  'When an approved care-plan item is available, it will appear here.',
                  'وقتی موردی از برنامه مراقبتی تأییدشده در دسترس باشد، اینجا نمایش داده می‌شود.',
                ),
              )
            else ...[
              CocoonSectionHeading(
                title: t('Active treatments', 'درمان‌های فعال'),
                supporting: t(
                  'Open an item to view its source details.',
                  'برای دیدن جزئیات منبع، یک مورد را باز کن.',
                ),
              ),
              const SizedBox(height: 12),
              for (final item in items) ...[
                _ActiveTreatmentTile(
                  item: item,
                  fa: fa,
                  onTap: () => onOpenTreatment(item.id),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ActiveTreatmentTile extends StatelessWidget {
  const _ActiveTreatmentTile({
    required this.item,
    required this.fa,
    required this.onTap,
  });

  final CocoonActiveTreatmentViewData item;
  final bool fa;
  final VoidCallback onTap;

  String t(String en, String faText) => fa ? faText : en;

  @override
  Widget build(BuildContext context) {
    final nextDose = item.nextDoseLabel;
    final status = item.statusLabel;
    final semantics = <String>[item.title, item.details];
    if (nextDose != null && nextDose.isNotEmpty) semantics.add(nextDose);
    if (status != null && status.isNotEmpty) semantics.add(status);
    if (item.isPendingSync) {
      semantics.add(t('Pending sync', 'در انتظار همگام‌سازی'));
    }
    semantics.add(t('Open treatment details', 'باز کردن جزئیات درمان'));

    return Semantics(
      button: true,
      label: semantics.join(', '),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 88),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CocoonRadii.card),
          child: CocoonSurface(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.medication_outlined,
                  color: CocoonTheme.coral,
                  size: 26,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.details,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: CocoonTheme.muted),
                      ),
                      if (nextDose != null && nextDose.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _TreatmentMetaRow(
                          icon: Icons.schedule_outlined,
                          label: nextDose,
                        ),
                      ],
                      if (status != null && status.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _TreatmentMetaRow(
                          icon: Icons.info_outline,
                          label: status,
                        ),
                      ],
                      if (item.isPendingSync) ...[
                        const SizedBox(height: 8),
                        CocoonStatusBadge(
                          icon: Icons.schedule_send_outlined,
                          label: t('Pending sync', 'در انتظار همگام‌سازی'),
                          foreground: CocoonTheme.skyStrong,
                          background: CocoonTheme.sky,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  fa ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                  color: CocoonTheme.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TreatmentMetaRow extends StatelessWidget {
  const _TreatmentMetaRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18, color: CocoonTheme.skyStrong),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: CocoonTheme.ink),
            ),
          ),
        ],
      );
}
