import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

import '../../core/theme/app_style.dart';

class NearbyDoseOptimizationScreen extends StatefulWidget {
  const NearbyDoseOptimizationScreen({super.key, this.api});

  final LifeMateMedicationScheduleApi? api;

  @override
  State<NearbyDoseOptimizationScreen> createState() =>
      _NearbyDoseOptimizationScreenState();
}

class _NearbyDoseOptimizationScreenState
    extends State<NearbyDoseOptimizationScreen> {
  late final LifeMateMedicationScheduleApi _api =
      widget.api ?? LifeMateMedicationScheduleApi.fromEnvironment();
  LifeMateNearbyDoseProposal? _proposal;
  String? _appliedProposalId;
  bool _loading = true;
  bool _applying = false;
  bool _undoing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _preview();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _preview() async {
    setState(() {
      _loading = true;
      _error = null;
      _appliedProposalId = null;
    });
    try {
      final proposal = await _api.previewNearbyDoseOptimization();
      if (!mounted) return;
      setState(() {
        _proposal = proposal;
        _loading = false;
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.statusCode == 409
            ? context.tr('medication.optimization.nearby.scheduleChanged')
            : context.tr('medication.optimization.nearby.previewFailed');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr('medication.optimization.nearby.previewConnection');
      });
    }
  }

  Future<void> _apply() async {
    final proposal = _proposal;
    if (proposal == null || !proposal.hasChanges || _applying) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dialogContext.tr('medication.optimization.nearby.applyTitle'),
        ),
        content: Text(
          dialogContext.tr('medication.optimization.nearby.applyDescription'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              dialogContext.tr('medication.optimization.nearby.confirmApply'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      final result = await _api.applyNearbyDoseOptimization(proposal.proposalId);
      if (!mounted) return;
      setState(() {
        _applying = false;
        _appliedProposalId = result.proposalId.isEmpty
            ? proposal.proposalId
            : result.proposalId;
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _error = error.statusCode == 409
            ? context.tr('medication.optimization.nearby.stale')
            : context.tr('medication.optimization.nearby.applyFailed');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _error = context.tr('medication.optimization.nearby.applyConnection');
      });
    }
  }

  Future<void> _undo() async {
    final proposalId = _appliedProposalId;
    if (proposalId == null || _undoing) return;
    setState(() {
      _undoing = true;
      _error = null;
    });
    try {
      await _api.undoNearbyDoseOptimization(proposalId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('medication.optimization.nearby.undoSuccess'),
          ),
        ),
      );
      await _preview();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _undoing = false;
        _error = error.statusCode == 409
            ? context.tr('medication.optimization.nearby.undoStale')
            : context.tr('medication.optimization.nearby.undoFailed');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _undoing = false;
        _error = context.tr('medication.optimization.nearby.undoConnection');
      });
    }
  }

  String _reason(String reason) => switch (reason) {
        'timing_locked' =>
          context.tr('medication.optimization.nearby.reason.locked'),
        'manual_spacing' =>
          context.tr('medication.optimization.nearby.reason.spacing'),
        'not_opted_in' =>
          context.tr('medication.optimization.nearby.reason.notOptedIn'),
        'ambiguous_cluster' =>
          context.tr('medication.optimization.nearby.reason.ambiguous'),
        _ => context.tr('medication.optimization.nearby.reason.noCandidate'),
      };

  @override
  Widget build(BuildContext context) {
    final proposal = _proposal;
    final applied = _appliedProposalId != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(context.tr('medication.optimization.nearby.title')),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _InfoCard(
                    icon: Icons.info_outline_rounded,
                    text: context.tr('medication.optimization.nearby.info'),
                  ),
                  const SizedBox(height: 14),
                  if (applied) ...[
                    _InfoCard(
                      icon: Icons.verified_rounded,
                      text: context.tr(
                        'medication.optimization.nearby.appliedInfo',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey('nearby-optimization-undo'),
                      onPressed: _undoing ? null : _undo,
                      icon: _undoing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.undo_rounded),
                      label: Text(
                        context.tr('medication.optimization.nearby.undoAction'),
                      ),
                    ),
                  ] else if (_error != null) ...[
                    _InfoCard(icon: Icons.error_outline_rounded, text: _error!),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _preview,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(context.tr('common.checkAgain')),
                    ),
                  ] else if (proposal == null || !proposal.hasChanges) ...[
                    _InfoCard(
                      icon: Icons.check_circle_outline_rounded,
                      text: context.tr('medication.optimization.nearby.noChanges'),
                    ),
                  ] else ...[
                    Text(
                      context.tr('medication.optimization.nearby.previewTitle'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final group in proposal.groups) ...[
                      _GroupCard(group: group),
                      const SizedBox(height: 10),
                    ],
                    _InfoCard(
                      icon: Icons.notifications_active_outlined,
                      text: context.tr(
                        'medication.optimization.nearby.notificationReduction',
                        params: {
                          'count': proposal.expectedNotificationReduction,
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _applying ? null : _apply,
                      icon: _applying
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.done_all_rounded),
                      label: Text(
                        context.tr('medication.optimization.nearby.applyChanges'),
                      ),
                    ),
                  ],
                  if (!applied &&
                      proposal != null &&
                      proposal.exclusions.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Text(
                      context.tr('medication.optimization.nearby.unchangedItems'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final exclusion in proposal.exclusions)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.remove_circle_outline_rounded),
                        title: Text(exclusion.medicationName),
                        subtitle: Text(_reason(exclusion.reason)),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final LifeMateNearbyDoseGroup group;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.merge_type_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${context.tr('medication.optimization.nearby.proposedTime')}: ${group.sharedLocalTime}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final change in group.changes) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.medication_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          change.medicationName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${change.oldAnchorLocalTime} → ${change.newAnchorLocalTime}',
                        ),
                        Text(
                          context.tr(
                            'medication.optimization.nearby.exactInterval',
                            params: {'hours': change.intervalHoursAfter},
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
          ],
        ),
      );
}
