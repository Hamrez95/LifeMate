import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../providers/grouped_medication_notification.dart';
import '../../providers/notification_provider.dart';

class GroupedMedicationChecklistScreen extends StatefulWidget {
  const GroupedMedicationChecklistScreen({
    required this.target,
    super.key,
  });

  final GroupedMedicationNotificationTarget target;

  @override
  State<GroupedMedicationChecklistScreen> createState() =>
      _GroupedMedicationChecklistScreenState();
}

class _GroupedMedicationChecklistScreenState
    extends State<GroupedMedicationChecklistScreen> {
  final Set<String> _resolved = <String>{};
  final Set<String> _busy = <String>{};

  bool get _fa => widget.target.isPersian;
  String _copy(String fa, String en) => _fa ? fa : en;

  Future<void> _report(
    GroupedMedicationDoseTarget dose,
    String status,
  ) async {
    if (_busy.contains(dose.occurrenceId)) return;
    setState(() => _busy.add(dose.occurrenceId));
    try {
      await context.read<NotificationProvider>().reportGroupedDose(
            dose,
            status: status,
          );
      if (!mounted) return;
      setState(() => _resolved.add(dose.occurrenceId));
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      _showError(error.code == 'stale_version'
          ? _copy(
              'این نوبت تغییر کرده است. صفحه برنامه را تازه کنید.',
              'This dose changed. Refresh the schedule before trying again.',
            )
          : _copy(
              'ثبت وضعیت انجام نشد. دوباره تلاش کنید.',
              'The dose status could not be saved. Try again.',
            ));
    } catch (_) {
      if (mounted) {
        _showError(
          _copy(
            'ثبت وضعیت انجام نشد. دوباره تلاش کنید.',
            'The dose status could not be saved. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(dose.occurrenceId));
    }
  }

  Future<void> _later(GroupedMedicationDoseTarget dose) async {
    if (_busy.contains(dose.occurrenceId)) return;
    setState(() => _busy.add(dose.occurrenceId));
    try {
      await context.read<NotificationProvider>().snoozeGroupedDose(
            dose,
            isPersian: _fa,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _copy(
              'برای ۱۰ دقیقه بعد یادآوری می‌کنیم.',
              'We will remind you again in 10 minutes.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(dose.occurrenceId));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          _copy(
            'داروهای این نوبت',
            'Medications for this time',
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.medication_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _copy(
                        'این اعلان فقط زمان‌های ثبت‌شده را کنار هم نشان می‌دهد و درباره تداخل یا ایمنی داروها تصمیم نمی‌گیرد. وضعیت هر دارو را جداگانه ثبت کنید.',
                        'This reminder only groups times you entered. It does not check drug interactions or medical safety. Record each medication separately.',
                      ),
                      style: const TextStyle(height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (final dose in widget.target.doses) ...[
              _DoseCard(
                dose: dose,
                isPersian: _fa,
                busy: _busy.contains(dose.occurrenceId),
                resolved: _resolved.contains(dose.occurrenceId),
                onTaken: () => _report(dose, 'taken'),
                onSkipped: () => _report(dose, 'skipped'),
                onLater: () => _later(dose),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({
    required this.dose,
    required this.isPersian,
    required this.busy,
    required this.resolved,
    required this.onTaken,
    required this.onSkipped,
    required this.onLater,
  });

  final GroupedMedicationDoseTarget dose;
  final bool isPersian;
  final bool busy;
  final bool resolved;
  final VoidCallback onTaken;
  final VoidCallback onSkipped;
  final VoidCallback onLater;

  String _copy(String fa, String en) => isPersian ? fa : en;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: resolved
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.primary.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                child: Icon(
                  resolved ? Icons.check_rounded : Icons.medication_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dose.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              if (busy)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (resolved)
            Text(
              _copy('وضعیت ثبت شد.', 'Status recorded.'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onTaken,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: Text(_copy('مصرف کردم', 'Taken')),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onSkipped,
                  icon: const Icon(Icons.block_outlined),
                  label: Text(_copy('مصرف نشد', 'Skipped')),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onLater,
                  icon: const Icon(Icons.snooze_rounded),
                  label: Text(_copy('بعداً', 'Later')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
