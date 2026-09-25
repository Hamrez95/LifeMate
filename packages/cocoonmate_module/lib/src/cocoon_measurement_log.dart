part of '../cocoonmate_module.dart';

enum CocoonMeasurementSubmitState {
  idle,
  submitting,
  queued,
  confirmed,
  error,
  offline
}

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
    this.onOpenHistory,
    super.key,
  });

  final bool fa;
  final List<CocoonMeasurementOption> options;
  final CocoonMeasurementSubmitState submitState;
  final Future<void> Function(CocoonMeasurementDraft draft) onSubmit;
  final VoidCallback? onOpenHistory;

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
        appBar: AppBar(
          title: Text(t('Add measurement', 'ثبت اندازه‌گیری')),
          actions: [
            if (widget.onOpenHistory != null)
              IconButton(
                tooltip: t('Measurement history', 'سابقهٔ اندازه‌گیری'),
                onPressed: widget.onOpenHistory,
                icon: const Icon(Icons.timeline_rounded),
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
                          text: t('Choose a measurement type',
                              'نوع اندازه‌گیری را انتخاب کن'),
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
          border:
              Border.all(color: CocoonTheme.sageStrong.withValues(alpha: .2)),
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
                    fa
                        ? 'داده‌ای برای دیدن روند'
                        : 'A data point for your trend',
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
      CocoonMeasurementSubmitState.submitting => (
          Icons.sync_rounded,
          CocoonTheme.sky,
          fa ? 'در حال ثبت امن' : 'Saving securely'
        ),
      CocoonMeasurementSubmitState.queued => (
          Icons.schedule_send_outlined,
          CocoonTheme.warm,
          fa
              ? 'در صف همگام‌سازی؛ هنوز تأیید نشده'
              : 'Queued; not yet confirmed',
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
          fa
              ? 'آفلاین؛ ثبت جدید در دسترس نیست'
              : 'Offline; new logging unavailable',
        ),
      CocoonMeasurementSubmitState.idle => (
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

/// Presentation-only state for a history supplied by the authenticated host.
///
/// This deliberately carries display-ready canonical data instead of local
/// threshold logic or a second copy of health facts. Hosts should replace the
/// list after a confirmed server refresh and may retain cached entries while a
/// refresh fails.
enum CocoonMeasurementHistoryState { loading, ready, empty, error }

enum CocoonMeasurementHistorySyncState { confirmed, pending, cached }

class CocoonMeasurementHistoryItem {
  const CocoonMeasurementHistoryItem({
    required this.id,
    required this.metricLabel,
    required this.valueLabel,
    required this.recordedAtLabel,
    required this.syncState,
    this.note,
  });

  /// Opaque canonical identity. The module never derives health data from it.
  final String id;
  final String metricLabel;
  final String valueLabel;
  final String recordedAtLabel;
  final CocoonMeasurementHistorySyncState syncState;
  final String? note;
}

/// A non-diagnostic measurement timeline.
///
/// Values, units, dates, ordering, and any pregnancy-context filtering are
/// owned by the authenticated host. This screen intentionally makes no trend,
/// range, or clinical-status claim.
class CocoonMeasurementHistoryScreen extends StatelessWidget {
  const CocoonMeasurementHistoryScreen({
    required this.fa,
    required this.state,
    required this.items,
    required this.onRetry,
    super.key,
  });

  final bool fa;
  final CocoonMeasurementHistoryState state;
  final List<CocoonMeasurementHistoryItem> items;
  final VoidCallback onRetry;

  String t(String en, String faText) => fa ? faText : en;

  @override
  Widget build(BuildContext context) {
    if (state == CocoonMeasurementHistoryState.loading) {
      return _MeasurementHistoryLoading(fa: fa);
    }
    if (state == CocoonMeasurementHistoryState.error && items.isEmpty) {
      return _MeasurementHistoryStatePage(
        fa: fa,
        icon: Icons.sync_problem_outlined,
        title: t('Could not refresh measurements', 'اندازه‌گیری‌ها به‌روز نشد'),
        body: t(
          'Saved measurements were not replaced. Try again when connected.',
          'اندازه‌گیری‌های ذخیره‌شده جایگزین نشده‌اند؛ پس از اتصال دوباره تلاش کن.',
        ),
        action: t('Try again', 'تلاش دوباره'),
        onPressed: onRetry,
      );
    }
    if (state == CocoonMeasurementHistoryState.empty || items.isEmpty) {
      return _MeasurementHistoryStatePage(
        fa: fa,
        icon: Icons.monitor_weight_outlined,
        title: t('No measurements yet', 'هنوز اندازه‌گیری‌ای ثبت نشده'),
        body: t(
          'Confirmed measurements from your care record will appear here.',
          'اندازه‌گیری‌های تأییدشده از پروندهٔ مراقبتی اینجا نمایش داده می‌شوند.',
        ),
      );
    }

    return ListView(
      key: const PageStorageKey('cocoon-measurement-history'),
      padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 36),
      children: [
        _MeasurementHistoryHero(fa: fa, count: items.length),
        if (state == CocoonMeasurementHistoryState.error) ...[
          const SizedBox(height: 14),
          _MeasurementHistoryRefreshNotice(fa: fa, onRetry: onRetry),
        ],
        const SizedBox(height: 24),
        Text(
          t('Recent measurements', 'اندازه‌گیری‌های اخیر'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        for (final item in items) ...[
          _MeasurementHistoryCard(fa: fa, item: item),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _MeasurementHistoryHero extends StatelessWidget {
  const _MeasurementHistoryHero({required this.fa, required this.count});
  final bool fa;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.all(20),
        decoration: BoxDecoration(
          color: CocoonTheme.sage,
          borderRadius: BorderRadius.circular(26),
          border:
              Border.all(color: CocoonTheme.sageStrong.withValues(alpha: .18)),
        ),
        child: Semantics(
          header: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.show_chart_rounded,
                  color: CocoonTheme.sageStrong, size: 30),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fa ? 'تاریخچهٔ اندازه‌گیری‌ها' : 'Measurement history',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      fa
                          ? '$count ثبت از پروندهٔ مراقبتی؛ بدون تفسیر بالینی.'
                          : '$count record${count == 1 ? '' : 's'} from your care record; no clinical interpretation.',
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
        ),
      );
}

class _MeasurementHistoryCard extends StatelessWidget {
  const _MeasurementHistoryCard({required this.fa, required this.item});
  final bool fa;
  final CocoonMeasurementHistoryItem item;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: [
          item.metricLabel,
          item.valueLabel,
          item.recordedAtLabel,
          if (item.syncState != CocoonMeasurementHistorySyncState.confirmed)
            _syncText(),
        ].join(', '),
        child: Container(
          padding: const EdgeInsetsDirectional.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(CocoonRadii.control),
            border: Border.all(color: CocoonTheme.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.monitor_weight_outlined,
                      color: CocoonTheme.sageStrong, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item.metricLabel,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (item.syncState !=
                      CocoonMeasurementHistorySyncState.confirmed)
                    _MeasurementHistorySyncPill(fa: fa, state: item.syncState),
                ],
              ),
              const SizedBox(height: 10),
              Text(item.valueLabel,
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 5),
              Text(item.recordedAtLabel,
                  style: Theme.of(context).textTheme.labelMedium),
              if (item.note != null && item.note!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(item.note!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      );

  String _syncText() => switch (item.syncState) {
        CocoonMeasurementHistorySyncState.pending =>
          fa ? 'در انتظار همگام‌سازی' : 'Pending sync',
        CocoonMeasurementHistorySyncState.cached =>
          fa ? 'ذخیره‌شده روی دستگاه' : 'Saved on device',
        CocoonMeasurementHistorySyncState.confirmed => '',
      };
}

class _MeasurementHistorySyncPill extends StatelessWidget {
  const _MeasurementHistorySyncPill({required this.fa, required this.state});
  final bool fa;
  final CocoonMeasurementHistorySyncState state;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: state == CocoonMeasurementHistorySyncState.pending
              ? CocoonTheme.warm
              : CocoonTheme.sky,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          switch (state) {
            CocoonMeasurementHistorySyncState.pending =>
              fa ? 'در انتظار همگام‌سازی' : 'Pending sync',
            CocoonMeasurementHistorySyncState.cached =>
              fa ? 'ذخیره‌شده' : 'On device',
            CocoonMeasurementHistorySyncState.confirmed => '',
          },
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: CocoonTheme.ink,
              ),
        ),
      );
}

class _MeasurementHistoryRefreshNotice extends StatelessWidget {
  const _MeasurementHistoryRefreshNotice(
      {required this.fa, required this.onRetry});
  final bool fa;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: CocoonTheme.warm,
            borderRadius: BorderRadius.circular(18),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 340 ||
                  MediaQuery.textScalerOf(context).scale(14) > 18;
              final message = Text(
                fa
                    ? 'ثبت‌های ذخیره‌شده نمایش داده می‌شوند؛ به‌روزرسانی انجام نشد.'
                    : 'Saved measurements are shown; refresh failed.',
                style: Theme.of(context).textTheme.labelMedium,
              );
              final retry = TextButton(
                onPressed: onRetry,
                child: Text(fa ? 'تلاش دوباره' : 'Retry'),
              );
              if (stack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [message, const SizedBox(height: 4), retry],
                );
              }
              return Row(children: [Expanded(child: message), retry]);
            },
          ),
        ),
      );
}

class _MeasurementHistoryStatePage extends StatelessWidget {
  const _MeasurementHistoryStatePage({
    required this.fa,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onPressed,
  });
  final bool fa;
  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor: CocoonTheme.sage,
                  child: Icon(icon, color: CocoonTheme.sageStrong, size: 34),
                ),
                const SizedBox(height: 24),
                Text(title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: CocoonTheme.muted),
                ),
                if (action != null && onPressed != null) ...[
                  const SizedBox(height: 24),
                  FilledButton(onPressed: onPressed, child: Text(action!)),
                ],
              ],
            ),
          ),
        ),
      );
}

class _MeasurementHistoryLoading extends StatelessWidget {
  const _MeasurementHistoryLoading({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: fa ? 'در حال آماده‌سازی اندازه‌گیری‌ها' : 'Loading measurements',
        child: ListView.separated(
          padding: const EdgeInsetsDirectional.all(20),
          itemCount: 5,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, __) => Container(
            height: 104,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(CocoonRadii.control),
              border: Border.all(color: CocoonTheme.line),
            ),
          ),
        ),
      );
}
