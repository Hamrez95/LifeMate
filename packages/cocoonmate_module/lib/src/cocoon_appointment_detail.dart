part of '../cocoonmate_module.dart';

class CocoonAppointmentDetailViewData {
  const CocoonAppointmentDetailViewData({
    required this.appointment,
    required this.reminderLabel,
    this.address,
    this.phone,
    this.note,
  });

  final CocoonAppointmentViewData appointment;
  final String reminderLabel;
  final String? address;
  final String? phone;
  final String? note;
}

class CocoonAppointmentDetailScreen extends StatelessWidget {
  const CocoonAppointmentDetailScreen({
    required this.fa,
    required this.data,
    required this.canMutate,
    required this.onEdit,
    required this.onCancel,
    super.key,
  });

  final bool fa;
  final CocoonAppointmentDetailViewData data;
  final bool canMutate;
  final VoidCallback onEdit;
  final Future<void> Function() onCancel;

  String t(String en, String faText) => fa ? faText : en;

  @override
  Widget build(BuildContext context) {
    final appointment = data.appointment;
    final status = _appointmentStatus(appointment.status, fa);
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Appointment details', 'جزئیات قرار')),
        actions: [
          IconButton(
            tooltip: t('Edit appointment', 'ویرایش قرار'),
            onPressed: canMutate ? onEdit : null,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsetsDirectional.all(22),
                decoration: BoxDecoration(
                  color: CocoonTheme.warm,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 10,
                        vertical: 6,
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
                    const SizedBox(height: 18),
                    Text(
                      appointment.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _DetailInlineMeta(
                          icon: Icons.calendar_today_outlined,
                          text: appointment.dateLabel,
                        ),
                        _DetailInlineMeta(
                          icon: Icons.schedule_outlined,
                          text: appointment.timeLabel,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (appointment.cached) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsetsDirectional.all(13),
                  decoration: BoxDecoration(
                    color: CocoonTheme.sky,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    t(
                      'Saved copy; connect to verify changes before editing.',
                      'نسخه‌ی ذخیره‌شده است؛ پیش از ویرایش برای تأیید تغییرات متصل شو.',
                    ),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: CocoonTheme.skyStrong,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              CocoonSectionHeading(
                title: t('Visit information', 'اطلاعات مراجعه'),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: CocoonTheme.line),
                ),
                child: Column(
                  children: [
                    if (appointment.provider != null)
                      _DetailRow(
                        icon: Icons.person_outline,
                        label: t('Doctor or specialist', 'پزشک یا متخصص'),
                        value: appointment.provider!,
                      ),
                    if (appointment.location != null)
                      _DetailRow(
                        icon: Icons.apartment_outlined,
                        label: t('Center', 'مرکز'),
                        value: appointment.location!,
                      ),
                    if (data.address != null)
                      _DetailRow(
                        icon: Icons.location_on_outlined,
                        label: t('Address', 'نشانی'),
                        value: data.address!,
                      ),
                    if (data.phone != null)
                      _DetailRow(
                        icon: Icons.phone_outlined,
                        label: t('Phone', 'تلفن'),
                        value: data.phone!,
                      ),
                    _DetailRow(
                      icon: Icons.notifications_none_rounded,
                      label: t('Reminder', 'یادآوری'),
                      value: data.reminderLabel,
                      last: data.note == null,
                    ),
                    if (data.note != null)
                      _DetailRow(
                        icon: Icons.notes_rounded,
                        label: t('Note', 'یادداشت'),
                        value: data.note!,
                        last: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: canMutate ? () => _confirmCancel(context) : null,
                icon: const Icon(Icons.event_busy_outlined),
                label: Text(t('Cancel appointment', 'لغو قرار')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB42318),
                  minimumSize: const Size(48, 50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('Cancel this appointment?', 'این قرار لغو شود؟'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                t(
                  'The change is final only after the server confirms it.',
                  'تغییر فقط پس از تأیید سرور نهایی می‌شود.',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB42318),
                ),
                child: Text(t('Confirm cancellation', 'تأیید لغو')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t('Keep appointment', 'قرار باقی بماند')),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) await onCancel();
  }
}

class _DetailInlineMeta extends StatelessWidget {
  const _DetailInlineMeta({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: CocoonTheme.coral),
      const SizedBox(width: 6),
      Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool last;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 21, color: CocoonTheme.sageStrong),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 3),
                  Text(value, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
      if (!last) const Divider(height: 1, indent: 48),
    ],
  );
}
