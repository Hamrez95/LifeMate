part of '../cocoonmate_module.dart';

enum CocoonMood { veryLow, low, neutral, good, veryGood }

enum CocoonMoodSubmitState {
  idle,
  submitting,
  queued,
  confirmed,
  error,
  offline
}

class CocoonMoodDraft {
  const CocoonMoodDraft({required this.mood});
  final CocoonMood mood;
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
  final Future<void> Function(CocoonMoodDraft draft) onSubmit;

  @override
  State<CocoonMoodLogScreen> createState() => _CocoonMoodLogScreenState();
}

class _CocoonMoodLogScreenState extends State<CocoonMoodLogScreen> {
  CocoonMood? _selected;
  bool get _busy => widget.submitState == CocoonMoodSubmitState.submitting;
  String t(String en, String fa) => widget.fa ? fa : en;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(t('How are you feeling?', 'حال روحی‌ات چطور است؟'))),
        body: SafeArea(
          bottom: false,
          child: CocoonPagePadding(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsetsDirectional.all(20),
                  decoration: BoxDecoration(
                    color: CocoonTheme.sky,
                    borderRadius: BorderRadius.circular(CocoonRadii.hero),
                  ),
                  child: Text(
                    t(
                      'A short self-check-in. This does not diagnose or label you.',
                      'یک ثبت کوتاه برای خودت؛ این بخش تشخیص یا برچسب‌گذاری نمی‌کند.',
                    ),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(height: 28),
                Semantics(
                  label: t('Choose your mood', 'حال روحی خود را انتخاب کن'),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: CocoonMood.values.map((mood) {
                      final selected = _selected == mood;
                      return Semantics(
                        selected: selected,
                        button: true,
                        child: ChoiceChip(
                          selected: selected,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _selected = mood),
                          label: Padding(
                            padding: const EdgeInsetsDirectional.symmetric(
                                vertical: 8),
                            child: Text(_label(mood)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                if (widget.submitState != CocoonMoodSubmitState.idle) ...[
                  const SizedBox(height: 18),
                  _MoodStatus(fa: widget.fa, state: widget.submitState),
                ],
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 14),
            child: FilledButton.icon(
              onPressed: _selected == null || _busy
                  ? null
                  : () => widget.onSubmit(CocoonMoodDraft(mood: _selected!)),
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: Text(_busy
                  ? t('Saving…', 'در حال ثبت…')
                  : t('Save mood', 'ثبت حال روحی')),
            ),
          ),
        ),
      );

  String _label(CocoonMood mood) => switch (mood) {
        CocoonMood.veryLow => t('Very low', 'خیلی پایین'),
        CocoonMood.low => t('Low', 'پایین'),
        CocoonMood.neutral => t('Neutral', 'معمولی'),
        CocoonMood.good => t('Good', 'خوب'),
        CocoonMood.veryGood => t('Very good', 'خیلی خوب'),
      };
}

class _MoodStatus extends StatelessWidget {
  const _MoodStatus({required this.fa, required this.state});
  final bool fa;
  final CocoonMoodSubmitState state;

  @override
  Widget build(BuildContext context) {
    final text = switch (state) {
      CocoonMoodSubmitState.submitting =>
        fa ? 'در حال ثبت امن' : 'Saving securely',
      CocoonMoodSubmitState.queued =>
        fa ? 'در صف همگام‌سازی؛ هنوز تأیید نشده' : 'Queued; not yet confirmed',
      CocoonMoodSubmitState.confirmed =>
        fa ? 'ثبت و تأیید شد' : 'Saved and confirmed',
      CocoonMoodSubmitState.error =>
        fa ? 'ثبت انجام نشد؛ دوباره تلاش کن' : 'Not saved; try again',
      CocoonMoodSubmitState.offline => fa
          ? 'آفلاین؛ ثبت جدید در دسترس نیست'
          : 'Offline; new logging unavailable',
      CocoonMoodSubmitState.idle => '',
    };
    return Semantics(liveRegion: true, child: Text(text));
  }
}
