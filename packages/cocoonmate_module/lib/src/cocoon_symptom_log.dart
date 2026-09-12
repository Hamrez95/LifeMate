part of '../cocoonmate_module.dart';

enum CocoonSymptomIntensity { mild, moderate, strong }

enum CocoonSymptomSubmitState {
  idle,
  submitting,
  queued,
  confirmed,
  error,
  offline
}

/// Presentation-only state for the host-owned approved symptom catalog.
/// It does not imply persistence, clinical evaluation, or server authority.
enum CocoonSymptomCatalogState { loading, ready, empty, error, offline }

class CocoonSymptomOption {
  const CocoonSymptomOption({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

class CocoonSymptomDraft {
  const CocoonSymptomDraft({
    required this.symptomId,
    required this.intensity,
    this.note,
  });

  final String symptomId;
  final CocoonSymptomIntensity intensity;
  final String? note;
}

class CocoonSymptomLogScreen extends StatefulWidget {
  const CocoonSymptomLogScreen({
    required this.fa,
    required this.options,
    required this.submitState,
    required this.onSubmit,
    required this.onOpenMedicalAttention,
    this.catalogState = CocoonSymptomCatalogState.ready,
    this.onRetryCatalog,
    super.key,
  });

  final bool fa;
  final List<CocoonSymptomOption> options;
  final CocoonSymptomCatalogState catalogState;
  final CocoonSymptomSubmitState submitState;
  final Future<void> Function(CocoonSymptomDraft draft) onSubmit;
  final VoidCallback? onOpenMedicalAttention;
  final VoidCallback? onRetryCatalog;

  @override
  State<CocoonSymptomLogScreen> createState() => _CocoonSymptomLogScreenState();
}

class _CocoonSymptomLogScreenState extends State<CocoonSymptomLogScreen> {
  final _note = TextEditingController();
  String? _symptomId;
  CocoonSymptomIntensity? _intensity;
  bool _showErrors = false;

  bool get _busy => widget.submitState == CocoonSymptomSubmitState.submitting;
  bool get _catalogReady =>
      widget.catalogState == CocoonSymptomCatalogState.ready &&
      widget.options.isNotEmpty;
  bool get _ready =>
      _catalogReady && _symptomId != null && _intensity != null && !_busy;
  String t(String en, String fa) => widget.fa ? fa : en;

  @override
  void didUpdateWidget(covariant CocoonSymptomLogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_catalogReady ||
        !widget.options.any((option) => option.id == _symptomId)) {
      _symptomId = null;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(t('Log a symptom', 'ثبت نشانه'))),
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
                      _SymptomHero(fa: widget.fa),
                      if (widget.submitState !=
                          CocoonSymptomSubmitState.idle) ...[
                        const SizedBox(height: 14),
                        _SymptomStatus(
                          fa: widget.fa,
                          state: widget.submitState,
                        ),
                      ],
                      const SizedBox(height: 28),
                      CocoonSectionHeading(
                        title: t('What did you notice?', 'چه چیزی حس کردی؟'),
                        supporting: t(
                          'Choose one item from the approved symptom list.',
                          'یک مورد را از فهرست تأییدشده انتخاب کن.',
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildCatalog(context),
                      if (_showErrors &&
                          _catalogReady &&
                          _symptomId == null) ...[
                        const SizedBox(height: 8),
                        Text(
                          t(
                            'Choose a symptom to continue',
                            'برای ادامه یک نشانه انتخاب کن',
                          ),
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                        ),
                      ],
                      const SizedBox(height: 30),
                      CocoonSectionHeading(
                        title: t('How noticeable was it?', 'شدت آن چقدر بود؟'),
                        supporting: t(
                          'Your own experience, not a diagnosis',
                          'برداشت خودت، نه تشخیص پزشکی',
                        ),
                      ),
                      const SizedBox(height: 14),
                      _IntensitySelector(
                        fa: widget.fa,
                        selected: _intensity,
                        enabled: !_busy && _catalogReady,
                        onChanged: (value) =>
                            setState(() => _intensity = value),
                      ),
                      if (_showErrors &&
                          _catalogReady &&
                          _intensity == null) ...[
                        const SizedBox(height: 8),
                        Text(
                          t('Choose an intensity', 'شدت را انتخاب کن'),
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                        ),
                      ],
                      const SizedBox(height: 26),
                      TextField(
                        controller: _note,
                        enabled: !_busy && _catalogReady,
                        minLines: 3,
                        maxLines: 5,
                        maxLength: 400,
                        decoration: InputDecoration(
                          labelText: t('Personal note', 'یادداشت شخصی'),
                          helperText: t('Optional', 'اختیاری'),
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _MedicalAttentionEntry(
                        fa: widget.fa,
                        onTap: widget.onOpenMedicalAttention,
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
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFFFDFC),
              border: Border(top: BorderSide(color: CocoonTheme.line)),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(20, 11, 20, 14),
            child: FilledButton.icon(
              onPressed: _busy || !_catalogReady ? null : _submit,
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
                    : t('Save symptom', 'ثبت نشانه'),
              ),
            ),
          ),
        ),
      );

  Widget _buildCatalog(BuildContext context) {
    final state = widget.catalogState == CocoonSymptomCatalogState.ready &&
            widget.options.isEmpty
        ? CocoonSymptomCatalogState.empty
        : widget.catalogState;
    if (state != CocoonSymptomCatalogState.ready) {
      return _SymptomCatalogStateCard(
        fa: widget.fa,
        state: state,
        onRetry: widget.onRetryCatalog,
      );
    }
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: widget.options
          .map(
            (option) => Semantics(
              selected: _symptomId == option.id,
              button: true,
              label: option.label,
              child: ChoiceChip(
                avatar: Icon(option.icon, size: 18),
                selected: _symptomId == option.id,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _symptomId = option.id),
                label: Text(option.label),
              ),
            ),
          )
          .toList(),
    );
  }

  Future<void> _submit() async {
    if (!_ready) {
      setState(() => _showErrors = true);
      return;
    }
    final note = _note.text.trim();
    await widget.onSubmit(
      CocoonSymptomDraft(
        symptomId: _symptomId!,
        intensity: _intensity!,
        note: note.isEmpty ? null : note,
      ),
    );
  }
}

class _SymptomHero extends StatelessWidget {
  const _SymptomHero({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.all(20),
        decoration: BoxDecoration(
          color: CocoonTheme.lilac,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: CocoonTheme.coral.withValues(alpha: .18)),
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
                        ? 'آنچه بدنت امروز می‌گوید'
                        : 'What your body says today',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    fa
                        ? 'ثبت کوتاه برای مرور روند؛ بدون نتیجه‌گیری پزشکی.'
                        : 'A short log for patterns, without medical conclusions.',
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

class _IntensitySelector extends StatelessWidget {
  const _IntensitySelector({
    required this.fa,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });
  final bool fa;
  final CocoonSymptomIntensity? selected;
  final bool enabled;
  final ValueChanged<CocoonSymptomIntensity> onChanged;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final choices = CocoonSymptomIntensity.values
        .map(
          (value) => ChoiceChip(
            selected: selected == value,
            onSelected: enabled ? (_) => onChanged(value) : null,
            label: Text(
              switch (value) {
                CocoonSymptomIntensity.mild => fa ? 'کم' : 'Mild',
                CocoonSymptomIntensity.moderate => fa ? 'متوسط' : 'Moderate',
                CocoonSymptomIntensity.strong => fa ? 'زیاد' : 'Strong',
              },
              textAlign: TextAlign.center,
            ),
          ),
        )
        .toList();
    if (largeText) {
      return Wrap(spacing: 8, runSpacing: 8, children: choices);
    }
    return Row(
      children: choices
          .map(
            (choice) => Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: SizedBox(width: double.infinity, child: choice),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MedicalAttentionEntry extends StatelessWidget {
  const _MedicalAttentionEntry({required this.fa, required this.onTap});
  final bool fa;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4E5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF2C27B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFF8A4B08),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    fa
                        ? 'اگر این نشانه برایت نگران‌کننده یا فوری است، آن را فقط به‌عنوان ثبت روزانه رها نکن.'
                        : 'If this feels concerning or urgent, do not leave it only as a routine log.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF6B3A06),
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.arrow_outward_rounded),
              label: Text(fa ? 'مسیر توجه پزشکی' : 'Medical attention pathway'),
            ),
          ],
        ),
      );
}

class _SymptomCatalogStateCard extends StatelessWidget {
  const _SymptomCatalogStateCard({
    required this.fa,
    required this.state,
    required this.onRetry,
  });

  final bool fa;
  final CocoonSymptomCatalogState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, text, canRetry) = switch (state) {
      CocoonSymptomCatalogState.loading => (
          Icons.hourglass_top_rounded,
          fa
              ? 'در حال دریافت فهرست تأییدشده…'
              : 'Loading the approved symptom catalog…',
          false,
        ),
      CocoonSymptomCatalogState.empty => (
          Icons.inbox_outlined,
          fa
              ? 'در حال حاضر مورد تأییدشده‌ای برای ثبت وجود ندارد.'
              : 'There are currently no approved symptoms available to log.',
          false,
        ),
      CocoonSymptomCatalogState.error => (
          Icons.error_outline_rounded,
          fa
              ? 'فهرست تأییدشده بارگیری نشد.'
              : 'The approved symptom catalog could not be loaded.',
          true,
        ),
      CocoonSymptomCatalogState.offline => (
          Icons.cloud_off_outlined,
          fa
              ? 'آفلاین هستی و فهرست تأییدشده روی این دستگاه موجود نیست.'
              : 'You are offline and no approved catalog is available on this device.',
          true,
        ),
      CocoonSymptomCatalogState.ready => (
          Icons.check_circle_outline,
          '',
          false,
        ),
    };
    return Semantics(
      liveRegion: state == CocoonSymptomCatalogState.loading ||
          state == CocoonSymptomCatalogState.error,
      child: Container(
        padding: const EdgeInsetsDirectional.all(16),
        decoration: BoxDecoration(
          color: CocoonTheme.sky,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: CocoonTheme.skyStrong),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (state == CocoonSymptomCatalogState.loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 3),
            ],
            if (canRetry && onRetry != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(fa ? 'تلاش دوباره' : 'Retry'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SymptomStatus extends StatelessWidget {
  const _SymptomStatus({required this.fa, required this.state});
  final bool fa;
  final CocoonSymptomSubmitState state;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (state) {
      CocoonSymptomSubmitState.submitting => (
          Icons.sync_rounded,
          CocoonTheme.sky,
          fa ? 'در حال ثبت امن' : 'Saving securely',
        ),
      CocoonSymptomSubmitState.queued => (
          Icons.schedule_send_outlined,
          CocoonTheme.warm,
          fa
              ? 'در صف همگام‌سازی؛ هنوز تأیید نشده'
              : 'Queued; not yet confirmed',
        ),
      CocoonSymptomSubmitState.confirmed => (
          Icons.cloud_done_outlined,
          CocoonTheme.sage,
          fa ? 'ثبت و تأیید شد' : 'Saved and confirmed',
        ),
      CocoonSymptomSubmitState.error => (
          Icons.error_outline,
          const Color(0xFFFFE9E7),
          fa ? 'ثبت انجام نشد؛ دوباره تلاش کن' : 'Not saved; try again',
        ),
      CocoonSymptomSubmitState.offline => (
          Icons.wifi_off_outlined,
          CocoonTheme.sky,
          fa
              ? 'آفلاین؛ ثبت جدید در دسترس نیست'
              : 'Offline; new logging unavailable',
        ),
      CocoonSymptomSubmitState.idle => (
          Icons.info_outline,
          CocoonTheme.cream,
          '',
        ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsetsDirectional.all(13),
        decoration: BoxDecoration(
          color: color,
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
