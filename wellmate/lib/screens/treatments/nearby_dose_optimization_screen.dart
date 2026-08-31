import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/state/wellmate_refresh.dart';
import '../../core/theme/app_style.dart';

class NearbyDoseOptimizationScreen extends StatefulWidget {
  const NearbyDoseOptimizationScreen({
    super.key,
    this.api,
    this.undoApi,
  });

  final LifeMateMedicationScheduleApi? api;
  final LifeMateNearbyDoseUndoApi? undoApi;

  @override
  State<NearbyDoseOptimizationScreen> createState() =>
      _NearbyDoseOptimizationScreenState();
}

class _NearbyDoseOptimizationScreenState
    extends State<NearbyDoseOptimizationScreen> {
  late final LifeMateMedicationScheduleApi _api =
      widget.api ?? LifeMateMedicationScheduleApi.fromEnvironment();
  late final LifeMateNearbyDoseUndoApi _undoApi =
      widget.undoApi ?? LifeMateNearbyDoseUndoApi.fromEnvironment();
  LifeMateNearbyDoseProposal? _proposal;
  String? _appliedProposalId;
  bool _loading = true;
  bool _applying = false;
  bool _undoing = false;
  String? _error;

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';
  String _copy(String fa, String en) => _fa ? fa : en;

  @override
  void initState() {
    super.initState();
    _preview();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    if (widget.undoApi == null) _undoApi.close();
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
            ? _copy(
                'برنامه دارو تغییر کرده است. دوباره بررسی کن.',
                'Your medication schedule changed. Preview again.',
              )
            : _copy(
                'پیشنهاد زمان‌بندی آماده نشد. دوباره تلاش کن.',
                'The timing proposal could not be prepared. Try again.',
              );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _copy(
          'پیشنهاد زمان‌بندی آماده نشد. اتصال را بررسی کن.',
          'The timing proposal could not be prepared. Check your connection.',
        );
      });
    }
  }

  Future<void> _apply() async {
    final proposal = _proposal;
    if (proposal == null || !proposal.hasChanges || _applying) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_copy('اعمال تغییر زمان‌ها؟', 'Apply timing changes?')),
        content: Text(
          _copy(
            'فقط زمان شروع برنامه‌های نشان‌داده‌شده تغییر می‌کند. فاصله مصرف هر دارو دقیقاً ثابت می‌ماند. LifeMate تداخل دارویی را بررسی نمی‌کند.',
            'Only the shown schedule anchors will change. Every medication interval remains exact. LifeMate does not check drug interactions.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_copy('انصراف', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_copy('تأیید و اعمال', 'Confirm & apply')),
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
      await _api.applyNearbyDoseOptimization(proposal.proposalId);
      if (!mounted) return;
      WellMateRefreshSignal.notifyChanged();
      setState(() {
        _applying = false;
        _appliedProposalId = proposal.proposalId;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _copy(
              'زمان‌های تأییدشده اعمال شد. فاصله مصرف داروها تغییر نکرد.',
              'Approved times were applied. Medication intervals were not changed.',
            ),
          ),
        ),
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _error = error.statusCode == 409
            ? _copy(
                'این پیشنهاد دیگر معتبر نیست. یک پیش‌نمایش تازه بگیر.',
                'This proposal is stale. Create a fresh preview.',
              )
            : _copy(
                'اعمال تغییرات انجام نشد. دوباره تلاش کن.',
                'Changes were not applied. Try again.',
              );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _error = _copy(
          'اعمال تغییرات انجام نشد. اتصال را بررسی کن.',
          'Changes were not applied. Check your connection.',
        );
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
      await _undoApi.undo(proposalId);
      if (!mounted) return;
      WellMateRefreshSignal.notifyChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _copy(
              'زمان‌های قبلی برگشتند. سابقه مصرف دارو تغییر نکرد.',
              'Previous times were restored. Medication adherence history was not changed.',
            ),
          ),
        ),
      );
      await _preview();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _undoing = false;
        _error = error.statusCode == 409
            ? _copy(
                'بعد از اعمال، برنامه تغییر کرده و بازگردانی خودکار امن نیست.',
                'The schedule changed after apply, so automatic undo is no longer safe.',
              )
            : _copy(
                'بازگردانی انجام نشد. دوباره تلاش کن.',
                'Undo failed. Try again.',
              );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _undoing = false;
        _error = _copy(
          'بازگردانی انجام نشد. اتصال را بررسی کن.',
          'Undo failed. Check your connection.',
        );
      });
    }
  }

  String _reason(String reason) => switch (reason) {
        'timing_locked' => _copy('زمان این دارو قفل است', 'Timing is locked'),
        'manual_spacing' => _copy(
            'برای این دارو دستور فاصله ثبت شده',
            'A spacing instruction is saved',
          ),
        'not_opted_in' => _copy(
            'پیشنهاد زمان نزدیک برای این دارو فعال نیست',
            'Nearby proposals are not enabled',
          ),
        'ambiguous_cluster' => _copy(
            'گروه زمانی مبهم بود؛ تغییری پیشنهاد نشد',
            'The timing cluster was ambiguous; no change was proposed',
          ),
        _ => _copy('زمان نزدیک دیگری پیدا نشد', 'No nearby candidate was found'),
      };

  @override
  Widget build(BuildContext context) {
    final proposal = _proposal;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          _copy('یکپارچه‌سازی زمان‌های نزدیک', 'Combine nearby medication times'),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _InfoCard(
                    icon: Icons.info_outline_rounded,
                    text: _copy(
                      'این قابلیت فقط زمان‌هایی را که خودت وارد کرده‌ای نزدیک‌تر می‌کند. LifeMate تداخل دارویی، ایمنی یا مناسب‌بودن مصرف همزمان را بررسی نمی‌کند.',
                      'This feature only combines nearby times you entered. LifeMate does not check drug interactions, safety, or whether medications should be taken together.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_error != null) ...[
                    _InfoCard(icon: Icons.error_outline_rounded, text: _error!),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _preview,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(_copy('بررسی دوباره', 'Preview again')),
                    ),
                  ] else if (_appliedProposalId != null) ...[
                    _InfoCard(
                      icon: Icons.check_circle_outline_rounded,
                      text: _copy(
                        'تغییرات تأییدشده اعمال شدند. فاصله زمانی اصلی هر دارو ثابت مانده است.',
                        'Approved changes were applied. Each medication keeps its original exact interval.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _undoing ? null : _undo,
                      icon: _undoing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.undo_rounded),
                      label: Text(_copy('بازگرداندن تغییرات', 'Undo changes')),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(_copy('تمام', 'Done')),
                    ),
                  ] else if (proposal == null || !proposal.hasChanges) ...[
                    _InfoCard(
                      icon: Icons.check_circle_outline_rounded,
                      text: _copy(
                        'فعلاً دو برنامه واجد شرایط با فاصله کمتر از ۳۰ دقیقه پیدا نشد. هیچ زمانی تغییر نکرد.',
                        'No two eligible schedules are currently less than 30 minutes apart. Nothing was changed.',
                      ),
                    ),
                  ] else ...[
                    Text(
                      _copy('پیش‌نمایش تغییرات', 'Change preview'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final group in proposal.groups) ...[
                      _GroupCard(group: group, fa: _fa),
                      const SizedBox(height: 10),
                    ],
                    _InfoCard(
                      icon: Icons.notifications_active_outlined,
                      text: _copy(
                        'در این پیش‌نمایش حدود ${proposal.expectedNotificationReduction} اعلان جداگانه کمتر می‌شود.',
                        'This preview reduces about ${proposal.expectedNotificationReduction} separate notifications.',
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
                      label: Text(_copy('اعمال تغییرات', 'Apply changes')),
                    ),
                  ],
                  if (_appliedProposalId == null &&
                      proposal != null &&
                      proposal.exclusions.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Text(
                      _copy('موارد بدون تغییر', 'Unchanged items'),
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
  const _GroupCard({required this.group, required this.fa});

  final LifeMateNearbyDoseGroup group;
  final bool fa;

  String _copy(String faText, String enText) => fa ? faText : enText;

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
                    '${_copy('زمان پیشنهادی', 'Proposed time')}: ${group.sharedLocalTime}',
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
                          _copy(
                            'فاصله هر ${change.intervalHoursAfter} ساعت بدون تغییر می‌ماند.',
                            'The exact ${change.intervalHoursAfter}-hour interval remains unchanged.',
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
