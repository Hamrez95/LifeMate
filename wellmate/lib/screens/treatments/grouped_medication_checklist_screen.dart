import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';
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
      _showError(
        error.code == 'stale_version'
            ? context.tr('medication.grouped.staleDose')
            : context.tr('medication.grouped.saveFailed'),
      );
    } catch (_) {
      if (mounted) {
        _showError(context.tr('medication.grouped.saveFailed'));
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
          content: Text(context.tr('medication.grouped.snoozed')),
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
        title: Text(context.tr('medication.grouped.title')),
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
                      context.tr('medication.grouped.explanation'),
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
    required this.busy,
    required this.resolved,
    required this.onTaken,
    required this.onSkipped,
    required this.onLater,
  });

  final GroupedMedicationDoseTarget dose;
  final bool busy;
  final bool resolved;
  final VoidCallback onTaken;
  final VoidCallback onSkipped;
  final VoidCallback onLater;

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
              context.tr('medication.grouped.statusRecorded'),
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
                  label: Text(context.tr('medication.grouped.taken')),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onSkipped,
                  icon: const Icon(Icons.block_outlined),
                  label: Text(context.tr('medication.grouped.skipped')),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onLater,
                  icon: const Icon(Icons.snooze_rounded),
                  label: Text(context.tr('common.later')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
