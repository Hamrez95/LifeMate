part of '../cocoonmate_module.dart';

enum CocoonCheckInSyncState {
  idle,
  submitting,
  queued,
  confirmed,
  error,
  offline,
}

enum CocoonCheckInFeeling { comfortable, mixed, difficult }

enum CocoonCheckInEnergy { low, steady, high }

class CocoonCheckInDraft {
  const CocoonCheckInDraft({required this.feeling, required this.energy});

  final CocoonCheckInFeeling feeling;
  final CocoonCheckInEnergy energy;
}

class CocoonQuickCheckInScreen extends StatefulWidget {
  const CocoonQuickCheckInScreen({
    required this.fa,
    required this.syncState,
    required this.onSubmit,
    super.key,
  });

  final bool fa;
  final CocoonCheckInSyncState syncState;
  final Future<void> Function(CocoonCheckInDraft draft) onSubmit;

  @override
  State<CocoonQuickCheckInScreen> createState() =>
      _CocoonQuickCheckInScreenState();
}

class _CocoonQuickCheckInScreenState extends State<CocoonQuickCheckInScreen> {
  CocoonCheckInFeeling? _feeling;
  CocoonCheckInEnergy? _energy;

  bool get _busy => widget.syncState == CocoonCheckInSyncState.submitting;
  bool get _ready => _feeling != null && _energy != null && !_busy;
  String t(String en, String fa) => widget.fa ? fa : en;

  @override
  Widget build(BuildContext context) => CustomScrollView(
        key: const PageStorageKey('cocoon-quick-checkin'),
        slivers: [
          SliverToBoxAdapter(
            child: CocoonPagePadding(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CheckInHero(fa: widget.fa),
                  const SizedBox(height: 22),
                  if (widget.syncState != CocoonCheckInSyncState.idle)
                    _CheckInStatus(fa: widget.fa, state: widget.syncState),
                  if (widget.syncState != CocoonCheckInSyncState.idle)
                    const SizedBox(height: 24),
                  CocoonSectionHeading(
                    title: t('How do you feel?', 'امروز چه حالی داری؟'),
                    supporting: t(
                      'Choose the closest answer—there is no right answer.',
                      'نزدیک‌ترین گزینه را انتخاب کن؛ پاسخ درست یا غلطی وجود ندارد.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ChoiceGroup<CocoonCheckInFeeling>(
                    values: CocoonCheckInFeeling.values,
                    selected: _feeling,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _feeling = value),
                    item: (value) => switch (value) {
                      CocoonCheckInFeeling.comfortable => _ChoiceData(
                          icon: Icons.wb_sunny_outlined,
                          label: t('Comfortable', 'آرام و خوب'),
                          color: CocoonTheme.sage,
                          foreground: CocoonTheme.sageStrong,
                        ),
                      CocoonCheckInFeeling.mixed => _ChoiceData(
                          icon: Icons.cloud_outlined,
                          label: t('Mixed', 'ترکیبی'),
                          color: CocoonTheme.warm,
                          foreground: CocoonTheme.gold,
                        ),
                      CocoonCheckInFeeling.difficult => _ChoiceData(
                          icon: Icons.air_outlined,
                          label: t('A difficult day', 'روز سختی است'),
                          color: CocoonTheme.lilac,
                          foreground: CocoonTheme.ink,
                        ),
                    },
                  ),
                  const SizedBox(height: 30),
                  CocoonSectionHeading(
                    title: t('Your energy', 'انرژی امروزت'),
                    supporting: t(
                      'This is wellbeing tracking, not a diagnosis.',
                      'این فقط ثبت حال عمومی است، نه تشخیص پزشکی.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  _EnergySelector(
                    fa: widget.fa,
                    selected: _energy,
                    enabled: !_busy,
                    onChanged: (value) => setState(() => _energy = value),
                  ),
                  const SizedBox(height: 28),
                  _PrivacyNote(fa: widget.fa),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _ready
                        ? () => widget.onSubmit(
                              CocoonCheckInDraft(
                                feeling: _feeling!,
                                energy: _energy!,
                              ),
                            )
                        : null,
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
                          : t('Save today’s check-in', 'ثبت حال امروز'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t(
                      'For urgent concerns, use the medical attention pathway instead of this check-in.',
                      'برای نگرانی فوری پزشکی، به‌جای این فرم از مسیر توجه پزشکی استفاده کن.',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

class _CheckInHero extends StatelessWidget {
  const _CheckInHero({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(22, 22, 22, 20),
        decoration: BoxDecoration(
          color: CocoonTheme.warm,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: CocoonTheme.coral.withValues(alpha: .2)),
          boxShadow: CocoonElevation.subtle,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CocoonBrandMark(
              semanticLabel: fa ? 'کوکون‌میت' : 'CocoonMate',
              size: 58,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fa ? 'یک مکث کوتاه برای خودت' : 'A small pause for you',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fa
                        ? 'با دو انتخاب ساده، حال امروزت را ثبت کن.'
                        : 'Capture today in two gentle choices.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: CocoonTheme.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ChoiceData {
  const _ChoiceData({
    required this.icon,
    required this.label,
    required this.color,
    required this.foreground,
  });
  final IconData icon;
  final String label;
  final Color color;
  final Color foreground;
}

class _ChoiceGroup<T> extends StatelessWidget {
  const _ChoiceGroup({
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.item,
  });

  final List<T> values;
  final T? selected;
  final ValueChanged<T>? onChanged;
  final _ChoiceData Function(T value) item;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final vertical = constraints.maxWidth < 330 ||
              MediaQuery.textScalerOf(context).scale(14) > 19;
          final reduceMotion =
              MediaQuery.maybeOf(context)?.disableAnimations ?? false;
          final children = values.map((value) {
            final data = item(value);
            final active = value == selected;
            return Semantics(
              button: true,
              selected: active,
              label: data.label,
              child: InkWell(
                onTap: onChanged == null ? null : () => onChanged!(value),
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minHeight: 84),
                  padding: const EdgeInsetsDirectional.all(12),
                  decoration: BoxDecoration(
                    color: active ? data.color : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: active ? data.foreground : CocoonTheme.line,
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(data.icon, color: data.foreground),
                      const SizedBox(height: 7),
                      Text(
                        data.label,
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        )
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: CocoonTheme.ink),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList();
          if (vertical) {
            return Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  SizedBox(width: double.infinity, child: children[i]),
                  if (i != children.length - 1) const SizedBox(height: 10),
                ],
              ],
            );
          }
          return Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                Expanded(child: children[i]),
                if (i != children.length - 1) const SizedBox(width: 10),
              ],
            ],
          );
        },
      );
}

class _EnergySelector extends StatelessWidget {
  const _EnergySelector({
    required this.fa,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final bool fa;
  final CocoonCheckInEnergy? selected;
  final bool enabled;
  final ValueChanged<CocoonCheckInEnergy> onChanged;

  String _label(CocoonCheckInEnergy value) => switch (value) {
        CocoonCheckInEnergy.low => fa ? 'کم' : 'Low',
        CocoonCheckInEnergy.steady => fa ? 'معمولی' : 'Steady',
        CocoonCheckInEnergy.high => fa ? 'زیاد' : 'High',
      };

  IconData _icon(CocoonCheckInEnergy value) => switch (value) {
        CocoonCheckInEnergy.low => Icons.battery_2_bar_rounded,
        CocoonCheckInEnergy.steady => Icons.battery_4_bar_rounded,
        CocoonCheckInEnergy.high => Icons.battery_full_rounded,
      };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(14) > 19;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < CocoonCheckInEnergy.values.length; i++) ...[
                  Semantics(
                    button: true,
                    selected: selected == CocoonCheckInEnergy.values[i],
                    label: _label(CocoonCheckInEnergy.values[i]),
                    child: ChoiceChip(
                      selected: selected == CocoonCheckInEnergy.values[i],
                      onSelected: enabled
                          ? (_) => onChanged(CocoonCheckInEnergy.values[i])
                          : null,
                      avatar:
                          Icon(_icon(CocoonCheckInEnergy.values[i]), size: 18),
                      label: SizedBox(
                        width: double.infinity,
                        child: Text(
                          _label(CocoonCheckInEnergy.values[i]),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  if (i != CocoonCheckInEnergy.values.length - 1)
                    const SizedBox(height: 8),
                ],
              ],
            );
          }
          return SegmentedButton<CocoonCheckInEnergy>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            selected: selected == null ? const {} : {selected!},
            onSelectionChanged: enabled
                ? (values) {
                    if (values.isNotEmpty) onChanged(values.first);
                  }
                : null,
            segments: [
              for (final value in CocoonCheckInEnergy.values)
                ButtonSegment(
                  value: value,
                  icon: Icon(_icon(value)),
                  label: Text(_label(value)),
                ),
            ],
          );
        },
      );
}

class _CheckInStatus extends StatelessWidget {
  const _CheckInStatus({required this.fa, required this.state});
  final bool fa;
  final CocoonCheckInSyncState state;

  @override
  Widget build(BuildContext context) {
    final (icon, color, foreground, text) = switch (state) {
      CocoonCheckInSyncState.submitting => (
          Icons.sync_rounded,
          CocoonTheme.sky,
          CocoonTheme.skyStrong,
          fa ? 'در حال ثبت امن اطلاعات' : 'Saving securely',
        ),
      CocoonCheckInSyncState.queued => (
          Icons.schedule_send_outlined,
          CocoonTheme.warm,
          CocoonTheme.gold,
          fa
              ? 'در صف همگام‌سازی؛ هنوز سرور تأیید نکرده'
              : 'Queued; not yet server-confirmed',
        ),
      CocoonCheckInSyncState.confirmed => (
          Icons.cloud_done_outlined,
          CocoonTheme.sage,
          CocoonTheme.sageStrong,
          fa ? 'ثبت و توسط سرور تأیید شد' : 'Saved and server-confirmed',
        ),
      CocoonCheckInSyncState.error => (
          Icons.error_outline_rounded,
          const Color(0xFFFFE9E7),
          const Color(0xFFB42318),
          fa ? 'ثبت انجام نشد؛ دوباره تلاش کن' : 'Not saved; please try again',
        ),
      CocoonCheckInSyncState.offline => (
          Icons.cloud_off_outlined,
          CocoonTheme.sky,
          CocoonTheme.skyStrong,
          fa
              ? 'آفلاین؛ وضعیت ثبت را پیش از خروج بررسی کن'
              : 'Offline; check save status before leaving',
        ),
      CocoonCheckInSyncState.idle => (
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
          color: color,
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

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            color: CocoonTheme.sageStrong,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              fa
                  ? 'ثبت امروز به‌صورت پیش‌فرض فقط برای خودت است و خودکار با مراقب به اشتراک گذاشته نمی‌شود.'
                  : 'Today’s check-in is owner-only by default and is not automatically shared with a caregiver.',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      );
}
