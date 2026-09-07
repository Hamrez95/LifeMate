part of '../cocoonmate_module.dart';

enum CocoonAppointmentStatus { scheduled, completed, cancelled, pendingSync }

class CocoonAppointmentViewData {
  const CocoonAppointmentViewData({
    required this.id,
    required this.title,
    required this.dateLabel,
    required this.timeLabel,
    required this.status,
    this.provider,
    this.location,
    this.cached = false,
  });

  final String id;
  final String title;
  final String dateLabel;
  final String timeLabel;
  final CocoonAppointmentStatus status;
  final String? provider;
  final String? location;
  final bool cached;
}

class CocoonAppointmentsScreen extends StatelessWidget {
  const CocoonAppointmentsScreen({
    required this.fa,
    required this.items,
    required this.onAdd,
    required this.onOpen,
    required this.onRetry,
    this.loading = false,
    this.offline = false,
    this.error = false,
    super.key,
  });

  final bool fa;
  final List<CocoonAppointmentViewData> items;
  final VoidCallback onAdd;
  final ValueChanged<String> onOpen;
  final VoidCallback onRetry;
  final bool loading;
  final bool offline;
  final bool error;

  String t(String en, String faText) => fa ? faText : en;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    key: const PageStorageKey('cocoon-appointments'),
    slivers: [
      SliverToBoxAdapter(
        child: CocoonPagePadding(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AppointmentHero(fa: fa, onAdd: onAdd),
              if (offline) ...[
                const SizedBox(height: 14),
                _AppointmentNotice(
                  text: t(
                    'Last information saved on this device',
                    'آخرین اطلاعات ذخیره‌شده روی این دستگاه',
                  ),
                ),
              ],
              const SizedBox(height: 30),
              CocoonSectionHeading(
                title: t('Care timeline', 'مسیر مراقبت'),
                supporting: t(
                  'Appointments, clearly ordered by time',
                  'قرارها، روشن و مرتب بر اساس زمان',
                ),
              ),
              const SizedBox(height: 14),
              if (loading)
                const _AppointmentLoading()
              else if (error)
                _AppointmentError(fa: fa, onRetry: onRetry)
              else if (items.isEmpty)
                _AppointmentEmpty(fa: fa, onAdd: onAdd)
              else
                ...items.map(
                  (item) => _AppointmentRow(
                    fa: fa,
                    item: item,
                    onTap: () => onOpen(item.id),
                  ),
                ),
              const SizedBox(height: 14),
              _AppointmentFootnote(fa: fa),
            ],
          ),
        ),
      ),
    ],
  );
}

class _AppointmentHero extends StatelessWidget {
  const _AppointmentHero({required this.fa, required this.onAdd});
  final bool fa;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.all(22),
    decoration: BoxDecoration(
      color: CocoonTheme.lilac,
      borderRadius: BorderRadius.circular(28),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 330 ||
            MediaQuery.textScalerOf(context).scale(16) > 21;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fa ? 'قرارهای بارداری' : 'Pregnancy appointments',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              fa
                  ? 'ویزیت‌ها و بررسی‌های ثبت‌شده، در یک مسیر آرام.'
                  : 'Saved visits and checks in one calm place.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: CocoonTheme.muted),
            ),
          ],
        );
        final action = FilledButton.tonalIcon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: Text(fa ? 'قرار جدید' : 'New'),
        );
        return compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [copy, const SizedBox(height: 18), action],
              )
            : Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: 14),
                  action,
                ],
              );
      },
    ),
  );
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({
    required this.fa,
    required this.item,
    required this.onTap,
  });
  final bool fa;
  final CocoonAppointmentViewData item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _appointmentStatus(item.status, fa);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 12),
      child: Semantics(
        button: true,
        label: item.title + '، ' + item.dateLabel + '، ' + status.$1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            padding: const EdgeInsetsDirectional.all(17),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: CocoonTheme.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: status.$2,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.medical_services_outlined,
                        color: status.$3,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.dateLabel + ' · ' + item.timeLabel,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: CocoonTheme.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: status.$2,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        status.$1,
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium?.copyWith(color: status.$3),
                      ),
                    ),
                  ],
                ),
                if (item.provider != null || item.location != null) ...[
                  const SizedBox(height: 13),
                  const Divider(height: 1),
                  const SizedBox(height: 11),
                  Text(
                    [
                      item.provider,
                      item.location,
                    ].whereType<String>().join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (item.cached) ...[
                  const SizedBox(height: 10),
                  Text(
                    fa
                        ? 'نسخه‌ی ذخیره‌شده؛ وضعیت آنلاین تأیید نشده'
                        : 'Saved copy; online status not verified',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: CocoonTheme.skyStrong,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

(String, Color, Color) _appointmentStatus(
  CocoonAppointmentStatus status,
  bool fa,
) => switch (status) {
  CocoonAppointmentStatus.scheduled => (
    fa ? 'پیش رو' : 'Upcoming',
    CocoonTheme.sage,
    CocoonTheme.sageStrong,
  ),
  CocoonAppointmentStatus.completed => (
    fa ? 'انجام‌شده' : 'Completed',
    CocoonTheme.sky,
    CocoonTheme.skyStrong,
  ),
  CocoonAppointmentStatus.cancelled => (
    fa ? 'لغوشده' : 'Cancelled',
    const Color(0xFFF3F4F6),
    CocoonTheme.muted,
  ),
  CocoonAppointmentStatus.pendingSync => (
    fa ? 'در انتظار همگام‌سازی' : 'Pending sync',
    CocoonTheme.warm,
    CocoonTheme.gold,
  ),
};

class _AppointmentNotice extends StatelessWidget {
  const _AppointmentNotice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsetsDirectional.all(13),
      decoration: BoxDecoration(
        color: CocoonTheme.sky,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: CocoonTheme.skyStrong,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: CocoonTheme.skyStrong),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AppointmentLoading extends StatelessWidget {
  const _AppointmentLoading();
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading appointments',
    child: Column(
      children: List.generate(
        2,
        (index) => Container(
          height: 112,
          margin: const EdgeInsetsDirectional.only(bottom: 12),
          decoration: BoxDecoration(
            color: index == 0 ? CocoonTheme.warm : CocoonTheme.sky,
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
    ),
  );
}

class _AppointmentEmpty extends StatelessWidget {
  const _AppointmentEmpty({required this.fa, required this.onAdd});
  final bool fa;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.all(22),
    decoration: BoxDecoration(
      color: CocoonTheme.sky,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      children: [
        const Icon(
          Icons.event_available_outlined,
          size: 34,
          color: CocoonTheme.skyStrong,
        ),
        const SizedBox(height: 12),
        Text(
          fa ? 'هنوز قراری ثبت نشده' : 'No appointments yet',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: Text(fa ? 'افزودن قرار' : 'Add appointment'),
        ),
      ],
    ),
  );
}

class _AppointmentError extends StatelessWidget {
  const _AppointmentError({required this.fa, required this.onRetry});
  final bool fa;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE9E7),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: Color(0xFFB42318)),
        const SizedBox(height: 10),
        Text(
          fa ? 'قرارها دریافت نشد' : 'Appointments did not load',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(fa ? 'تلاش دوباره' : 'Try again'),
        ),
      ],
    ),
  );
}

class _AppointmentFootnote extends StatelessWidget {
  const _AppointmentFootnote({required this.fa});
  final bool fa;
  @override
  Widget build(BuildContext context) => Text(
    fa
        ? 'تغییر یا لغو تأییدشده باید در همه‌ی بخش‌های LifeMate یکسان دیده شود.'
        : 'Confirmed changes must stay consistent across LifeMate.',
    style: Theme.of(context).textTheme.labelMedium,
    textAlign: TextAlign.center,
  );
}
