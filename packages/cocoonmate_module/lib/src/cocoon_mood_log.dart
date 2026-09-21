part of '../cocoonmate_module.dart';

enum CocoonMoodSubmitState {
  idle,
  submitting,
  queued,
  confirmed,
  error,
  offline,
}

class CocoonMoodLogScreen extends StatefulWidget {
  const CocoonMoodLogScreen({
    required this.fa,
    required this.submitState,
    required this.onSubmit,
    super.key,
  });

  final bool fa;
  final CocoonMoodSubmitState submitState;
  final Future<CocoonGate3MutationResult> Function(CocoonPregnancyMood mood)
  onSubmit;

  @override
  State<CocoonMoodLogScreen> createState() => _CocoonMoodLogScreenState();
}

class _CocoonMoodLogScreenState extends State<CocoonMoodLogScreen> {
  CocoonPregnancyMood? _mood;
  late CocoonMoodSubmitState _state = widget.submitState;

  bool get _busy => _state == CocoonMoodSubmitState.submitting;
  String t(String en, String fa) => widget.fa ? fa : en;

  Future<void> _submit() async {
    final mood = _mood;
    if (mood == null || _busy) return;
    setState(() => _state = CocoonMoodSubmitState.submitting);
    try {
      final result = await widget.onSubmit(mood);
      if (!mounted) return;
      setState(() {
        _state = result.disposition == CocoonGate3MutationDisposition.queued
            ? CocoonMoodSubmitState.queued
            : CocoonMoodSubmitState.confirmed;
      });
    } on LifeMateApiException catch (error) {
      if (mounted) {
        setState(
          () => _state = error.statusCode == 0
              ? CocoonMoodSubmitState.offline
              : CocoonMoodSubmitState.error,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _state = CocoonMoodSubmitState.error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Mood', 'حال روحی'))),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('How are you feeling?', 'از نظر روحی چه حسی داری؟'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'This is a personal wellbeing check-in, not a diagnosis.',
                'این یک ثبت شخصیِ حال عمومی است، نه تشخیص پزشکی.',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 22),
            for (final mood in CocoonPregnancyMood.values) ...[
              _MoodOption(
                fa: widget.fa,
                mood: mood,
                selected: _mood == mood,
                enabled: !_busy,
                onTap: () => setState(() => _mood = mood),
              ),
              const SizedBox(height: 10),
            ],
            if (_state != CocoonMoodSubmitState.idle) ...[
              const SizedBox(height: 18),
              _MoodStatus(fa: widget.fa, state: _state),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _mood == null || _busy ? null : _submit,
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
                    : t('Save mood', 'ثبت حال روحی'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MoodOption extends StatelessWidget {
  const _MoodOption({
    required this.fa,
    required this.mood,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final bool fa;
  final CocoonPregnancyMood mood;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final label = switch (mood) {
      CocoonPregnancyMood.veryLow => fa ? 'خیلی پایین' : 'Very low',
      CocoonPregnancyMood.low => fa ? 'پایین' : 'Low',
      CocoonPregnancyMood.neutral => fa ? 'معمولی' : 'Neutral',
      CocoonPregnancyMood.good => fa ? 'خوب' : 'Good',
      CocoonPregnancyMood.veryGood => fa ? 'خیلی خوب' : 'Very good',
    };
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          alignment: AlignmentDirectional.centerStart,
          backgroundColor: selected ? CocoonTheme.sky : null,
          side: BorderSide(
            color: selected ? CocoonTheme.skyStrong : CocoonTheme.line,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _MoodStatus extends StatelessWidget {
  const _MoodStatus({required this.fa, required this.state});
  final bool fa;
  final CocoonMoodSubmitState state;
  @override
  Widget build(BuildContext context) {
    final text = switch (state) {
      CocoonMoodSubmitState.queued =>
        fa
            ? 'ثبت شد و در انتظار همگام‌سازی است.'
            : 'Saved and waiting to sync.',
      CocoonMoodSubmitState.confirmed =>
        fa ? 'ثبت و تأیید شد.' : 'Saved and server-confirmed.',
      CocoonMoodSubmitState.error =>
        fa ? 'ثبت انجام نشد؛ دوباره تلاش کن.' : 'Could not save. Try again.',
      CocoonMoodSubmitState.offline =>
        fa
            ? 'اتصال برقرار نیست؛ دوباره تلاش کن.'
            : 'You are offline. Try again when connected.',
      _ => '',
    };
    return Semantics(liveRegion: true, child: Text(text));
  }
}
