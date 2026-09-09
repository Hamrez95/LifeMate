part of '../cocoonmate_module.dart';

enum CocoonQuickAddKind {
  checkIn,
  symptom,
  measurement,
  medication,
  appointment
}

class CocoonQuickAddScreen extends StatelessWidget {
  const CocoonQuickAddScreen({
    required this.fa,
    required this.onOpen,
    this.enabled = const {
      CocoonQuickAddKind.checkIn,
      CocoonQuickAddKind.symptom,
      CocoonQuickAddKind.measurement,
      CocoonQuickAddKind.medication,
      CocoonQuickAddKind.appointment,
    },
    super.key,
  });

  final bool fa;
  final Set<CocoonQuickAddKind> enabled;
  final ValueChanged<CocoonQuickAddKind> onOpen;

  String t(String en, String faText) => fa ? faText : en;

  @override
  Widget build(BuildContext context) => CustomScrollView(
        key: const PageStorageKey('cocoon-quick-add'),
        slivers: [
          SliverToBoxAdapter(
            child: CocoonPagePadding(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _QuickAddHero(fa: fa),
                  const SizedBox(height: 30),
                  CocoonSectionHeading(
                    title: t('What would you like to add?',
                        'چه چیزی می‌خواهی ثبت کنی؟'),
                    supporting: t(
                      'Choose one short path. You can add more later.',
                      'یک مسیر کوتاه را انتخاب کن؛ بقیه را می‌توانی بعداً اضافه کنی.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _QuickAddPrimary(
                    fa: fa,
                    enabled: enabled.contains(CocoonQuickAddKind.checkIn),
                    onTap: () => onOpen(CocoonQuickAddKind.checkIn),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 520 &&
                          MediaQuery.textScalerOf(context).scale(1) < 1.3;
                      final tiles = [
                        _QuickAddTile(
                          fa: fa,
                          kind: CocoonQuickAddKind.symptom,
                          enabled: enabled.contains(CocoonQuickAddKind.symptom),
                          onTap: () => onOpen(CocoonQuickAddKind.symptom),
                        ),
                        _QuickAddTile(
                          fa: fa,
                          kind: CocoonQuickAddKind.measurement,
                          enabled:
                              enabled.contains(CocoonQuickAddKind.measurement),
                          onTap: () => onOpen(CocoonQuickAddKind.measurement),
                        ),
                        _QuickAddTile(
                          fa: fa,
                          kind: CocoonQuickAddKind.medication,
                          enabled:
                              enabled.contains(CocoonQuickAddKind.medication),
                          onTap: () => onOpen(CocoonQuickAddKind.medication),
                        ),
                        _QuickAddTile(
                          fa: fa,
                          kind: CocoonQuickAddKind.appointment,
                          enabled:
                              enabled.contains(CocoonQuickAddKind.appointment),
                          onTap: () => onOpen(CocoonQuickAddKind.appointment),
                        ),
                      ];
                      if (!wide) {
                        return Column(
                          children: [
                            for (var index = 0;
                                index < tiles.length;
                                index++) ...[
                              tiles[index],
                              if (index < tiles.length - 1)
                                const SizedBox(height: 10),
                            ],
                          ],
                        );
                      }
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: tiles
                            .map(
                              (tile) => SizedBox(
                                width: (constraints.maxWidth - 12) / 2,
                                child: tile,
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 26),
                  Container(
                    padding: const EdgeInsetsDirectional.all(16),
                    decoration: BoxDecoration(
                      color: CocoonTheme.sky,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            color: CocoonTheme.skyStrong),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t(
                              'For urgent medical concerns, use the medical attention pathway—not a routine log.',
                              'برای نگرانی فوری پزشکی از مسیر توجه پزشکی استفاده کن، نه ثبت روزمره.',
                            ),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: CocoonTheme.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

class _QuickAddHero extends StatelessWidget {
  const _QuickAddHero({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(22, 28, 22, 26),
        decoration: BoxDecoration(
          color: const Color(0xFFFFECE3),
          borderRadius: BorderRadius.circular(CocoonRadii.hero),
          border: Border.all(color: Colors.white),
          boxShadow: CocoonElevation.hero,
        ),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: CocoonBrandMark(
                semanticLabel: fa ? 'همراه کوکون‌میت' : 'CocoonMate companion',
                size: 48,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fa
                        ? 'چی رو می‌خوای ثبت کنی؟'
                        : 'What would you like to add?',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    fa
                        ? 'هر چیزی که امروز حس کردی، اینجا امن می‌مونه.'
                        : 'Whatever you noticed today has a calm place here.',
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

class _QuickAddPrimary extends StatelessWidget {
  const _QuickAddPrimary({
    required this.fa,
    required this.enabled,
    required this.onTap,
  });
  final bool fa;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: enabled,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsetsDirectional.all(20),
            decoration: BoxDecoration(
              color: CocoonTheme.coralSoft,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.favorite_outline_rounded,
                      color: CocoonTheme.coral),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fa ? 'حال امروز' : 'Today’s check-in',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        fa
                            ? 'حال و انرژی، در دو قدم'
                            : 'Feeling and energy in two steps',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
                Icon(
                  fa ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
                  color: enabled ? CocoonTheme.coral : CocoonTheme.muted,
                ),
              ],
            ),
          ),
        ),
      );
}

class _QuickAddTile extends StatelessWidget {
  const _QuickAddTile({
    required this.fa,
    required this.kind,
    required this.enabled,
    required this.onTap,
  });
  final bool fa;
  final CocoonQuickAddKind kind;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body, color, foreground) = switch (kind) {
      CocoonQuickAddKind.symptom => (
          Icons.healing_outlined,
          fa ? 'نشانه یا علامت' : 'Symptom',
          fa ? 'آنچه امروز حس کردی' : 'What you noticed today',
          CocoonTheme.lilac,
          CocoonTheme.ink,
        ),
      CocoonQuickAddKind.measurement => (
          Icons.monitor_weight_outlined,
          fa ? 'اندازه‌گیری' : 'Measurement',
          fa ? 'وزن، فشار یا داده دیگر' : 'Weight, pressure or another metric',
          CocoonTheme.sage,
          CocoonTheme.sageStrong,
        ),
      CocoonQuickAddKind.medication => (
          Icons.medication_outlined,
          fa ? 'دارو و مکمل' : 'Medication',
          fa
              ? 'ثبت مصرف، بدون توصیه پزشکی'
              : 'Log intake without medical advice',
          CocoonTheme.warm,
          CocoonTheme.gold,
        ),
      CocoonQuickAddKind.appointment => (
          Icons.event_outlined,
          fa ? 'قرار یا آزمایش' : 'Appointment or test',
          fa ? 'ویزیت و مراقبت بعدی' : 'Your next care step',
          CocoonTheme.sky,
          CocoonTheme.skyStrong,
        ),
      CocoonQuickAddKind.checkIn => throw StateError('Primary action only'),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(CocoonRadii.card),
        child: Ink(
          padding: const EdgeInsetsDirectional.all(16),
          decoration: BoxDecoration(
            color: enabled ? color : const Color(0xFFF5F3F1),
            borderRadius: BorderRadius.circular(CocoonRadii.card),
            border: Border.all(
              color: enabled
                  ? foreground.withValues(alpha: .24)
                  : CocoonTheme.line,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white70,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: foreground),
              ),
              const SizedBox(width: 13),
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
              if (!enabled)
                Icon(Icons.lock_outline_rounded,
                    size: 19, color: CocoonTheme.muted),
            ],
          ),
        ),
      ),
    );
  }
}
