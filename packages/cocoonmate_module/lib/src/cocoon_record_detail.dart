part of '../cocoonmate_module.dart';

/// Read-only detail for the bounded, canonical data already supplied to the
/// Records timeline. It deliberately does not infer clinical facts or request
/// a broader health record from the presentation layer.
class CocoonRecordDetailScreen extends StatelessWidget {
  const CocoonRecordDetailScreen({
    required this.fa,
    required this.record,
    this.onOpenSource,
    super.key,
  });

  final bool fa;
  final CocoonRecordViewData record;

  /// Lets the authenticated host open the original record surface when it has
  /// a separately-authorized source identity. The module neither resolves an
  /// ID nor fetches extra health information itself.
  final ValueChanged<CocoonRecordViewData>? onOpenSource;

  String t(String en, String faValue) => fa ? faValue : en;

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(record.kind);
    final pending = record.syncState != CocoonRecordSyncState.confirmed;
    final canOpenSource = !pending && onOpenSource != null;
    return Scaffold(
      appBar: AppBar(title: Text(t('Record details', 'جزئیات سابقه'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
          children: [
            Semantics(
              header: true,
              child: Container(
                padding: const EdgeInsetsDirectional.all(20),
                decoration: BoxDecoration(
                  color: visual.background,
                  borderRadius: BorderRadius.circular(CocoonRadii.hero),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(visual.icon, color: visual.color, size: 32),
                    const SizedBox(height: 18),
                    Text(
                      record.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _kindLabel(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: CocoonTheme.muted,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            CocoonSectionHeading(
              title: t('Saved details', 'جزئیات ثبت‌شده'),
              supporting: t(
                'Only information already available in your record is shown here.',
                'فقط اطلاعاتی که همین حالا در سابقه‌ات موجود است اینجا نمایش داده می‌شود.',
              ),
            ),
            const SizedBox(height: 12),
            _DetailCard(
              children: [
                _RecordDetailRow(
                  icon: Icons.calendar_today_outlined,
                  label: t('Date', 'تاریخ'),
                  value: record.dateLabel,
                ),
                if (record.summary case final summary?) ...[
                  const Divider(height: 24),
                  _RecordDetailRow(
                    icon: Icons.notes_outlined,
                    label: t('Summary', 'خلاصه'),
                    value: summary,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            _SyncCard(fa: fa, state: record.syncState, pending: pending),
            if (canOpenSource) ...[
              const SizedBox(height: 18),
              Semantics(
                button: true,
                label: t(
                  'Open the original record',
                  'بازکردن سابقهٔ اصلی',
                ),
                hint: t(
                  'Opens the source screen available to this account.',
                  'صفحهٔ منبعی را باز می‌کند که برای این حساب در دسترس است.',
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.tonalIcon(
                    onPressed: () => onOpenSource!(record),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(t('Open original entry', 'بازکردن مورد اصلی')),
                  ),
                ),
              ),
            ],
            if (pending) ...[
              const SizedBox(height: 18),
              Text(
                t(
                  'This entry is not confirmed by the server yet. It will stay marked as pending until a later sync confirms it.',
                  'این مورد هنوز از سوی سرور تأیید نشده است و تا همگام‌سازی بعدی با برچسب در انتظار باقی می‌ماند.',
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: CocoonTheme.muted,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _kindLabel() => switch (record.kind) {
        CocoonRecordKind.checkIn => t('Daily capture', 'ثبت روزانه'),
        CocoonRecordKind.appointment => t('Appointment', 'قرار مراقبتی'),
        CocoonRecordKind.measurement => t('Measurement', 'اندازه‌گیری'),
        CocoonRecordKind.medication => t('Medication', 'دارو'),
        CocoonRecordKind.document => t('Document', 'مدرک'),
      };

  _RecordDetailVisual _visualFor(CocoonRecordKind kind) => switch (kind) {
        CocoonRecordKind.checkIn => const _RecordDetailVisual(
            Icons.favorite_outline_rounded,
            CocoonTheme.coral,
            CocoonTheme.warm,
          ),
        CocoonRecordKind.appointment => const _RecordDetailVisual(
            Icons.event_outlined,
            CocoonTheme.skyStrong,
            CocoonTheme.sky,
          ),
        CocoonRecordKind.measurement => const _RecordDetailVisual(
            Icons.monitor_weight_outlined,
            CocoonTheme.sageStrong,
            CocoonTheme.sage,
          ),
        CocoonRecordKind.medication => const _RecordDetailVisual(
            Icons.medication_outlined,
            CocoonTheme.gold,
            CocoonTheme.warm,
          ),
        CocoonRecordKind.document => const _RecordDetailVisual(
            Icons.description_outlined,
            CocoonTheme.ink,
            CocoonTheme.lilac,
          ),
      };
}

class _RecordDetailVisual {
  const _RecordDetailVisual(this.icon, this.color, this.background);
  final IconData icon;
  final Color color;
  final Color background;
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(CocoonRadii.control),
          border: Border.all(color: CocoonTheme.line),
        ),
        child: Column(children: children),
      );
}

class _RecordDetailRow extends StatelessWidget {
  const _RecordDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label: $value',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: CocoonTheme.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 3),
                  Text(value, style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
          ],
        ),
      );
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.fa,
    required this.state,
    required this.pending,
  });
  final bool fa;
  final CocoonRecordSyncState state;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body, color) = switch (state) {
      CocoonRecordSyncState.confirmed => (
          Icons.cloud_done_outlined,
          fa ? 'تأییدشده' : 'Confirmed',
          fa
              ? 'این مورد توسط سرور تأیید شده است.'
              : 'This entry is confirmed by the server.',
          CocoonTheme.sageStrong,
        ),
      CocoonRecordSyncState.pending => (
          Icons.cloud_upload_outlined,
          fa ? 'در انتظار همگام‌سازی' : 'Pending sync',
          fa
              ? 'این مورد برای ارسال نگه‌داری می‌شود.'
              : 'This entry is retained for upload.',
          CocoonTheme.gold,
        ),
      CocoonRecordSyncState.cached => (
          Icons.devices_outlined,
          fa ? 'ذخیره‌شده روی دستگاه' : 'Saved on device',
          fa
              ? 'این نمایش از دادهٔ ذخیره‌شده روی دستگاه است.'
              : 'This view comes from data saved on this device.',
          CocoonTheme.skyStrong,
        ),
    };
    return Semantics(
      liveRegion: pending,
      child: Container(
        padding: const EdgeInsetsDirectional.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(CocoonRadii.control),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 3),
                  Text(body, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
