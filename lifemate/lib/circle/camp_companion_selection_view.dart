import 'package:flutter/material.dart';

import 'camp_companion_selection.dart';

class CampCompanionSelectionView extends StatefulWidget {
  const CampCompanionSelectionView({
    super.key,
    required this.source,
    required this.isPersian,
  });

  final CampCompanionSelectionSource source;
  final bool isPersian;

  @override
  State<CampCompanionSelectionView> createState() =>
      _CampCompanionSelectionViewState();
}

class _CampCompanionSelectionViewState
    extends State<CampCompanionSelectionView> {
  late Future<CampCompanionSelectionSnapshot> _load = widget.source.load();
  bool _saving = false;

  String _t(String en, String fa) => widget.isPersian ? fa : en;

  void _reload() => setState(() => _load = widget.source.load());

  @override
  void didUpdateWidget(covariant CampCompanionSelectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) _reload();
  }

  Future<void> _toggle(
    CampCompanionSelectionSnapshot snapshot,
    CampCompanionCandidate candidate,
  ) async {
    if (_saving || !candidate.isEligible) return;

    final next = <String>{...snapshot.selectedPresentationIds};
    if (!next.remove(candidate.presentationId)) {
      if (next.length >= snapshot.capacity) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'You can show up to ${snapshot.capacity} companions in Camp.',
                'می‌توانید حداکثر ${snapshot.capacity} همراه را در کمپ نمایش دهید.',
              ),
            ),
          ),
        );
        return;
      }
      next.add(candidate.presentationId);
    }

    setState(() => _saving = true);
    try {
      await widget.source.setSelectedPresentationIds(next);
      if (mounted) _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'Camp companion selection could not be updated.',
                'انتخاب همراهان کمپ به‌روزرسانی نشد.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSummary(CampCompanionCandidate candidate) async {
    CampCompanionCandidate? refreshedCandidate;
    var selected = false;
    var refreshFailed = false;

    try {
      final refreshed = await widget.source.load();
      selected = refreshed.selectedPresentationIds.contains(
        candidate.presentationId,
      );
      for (final item in refreshed.candidates) {
        if (item.presentationId == candidate.presentationId) {
          refreshedCandidate = item;
          break;
        }
      }
    } catch (_) {
      refreshFailed = true;
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CompanionSummarySheet(
        candidate: refreshedCandidate,
        selected: selected,
        refreshFailed: refreshFailed,
        synthetic: widget.source.mode == CampCompanionSourceMode.synthetic,
        isPersian: widget.isPersian,
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 8),
            child: Text(
              _t('Camp companions', 'همراهان کمپ'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 16),
            child: Text(
              _t(
                'Choose who may appear with you in Living Camp. This changes presentation only — it does not change relationships, consent, or access.',
                'انتخاب کنید چه کسانی در Living Camp کنار شما نمایش داده شوند. این فقط نمایش را تغییر می‌دهد و رابطه، رضایت یا دسترسی را تغییر نمی‌دهد.',
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<CampCompanionSelectionSnapshot>(
              future: _load,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final unavailable =
                      snapshot.error is CampCompanionSelectionUnavailable;
                  return _FailureState(
                    isPersian: widget.isPersian,
                    unavailable: unavailable,
                    onRetry: _reload,
                  );
                }
                final value = snapshot.data!;
                if (value.candidates.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _t(
                          'No eligible Circle companions are available yet.',
                          'هنوز همراه واجد شرایطی از Circle در دسترس نیست.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final capacityReached =
                    value.capacity > 0 &&
                    value.selectedPresentationIds.length >= value.capacity;
                return ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 24),
                  children: [
                    if (widget.source.mode == CampCompanionSourceMode.synthetic)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          4,
                          0,
                          4,
                          12,
                        ),
                        child: Text(
                          _t(
                            'Preview data — not live relationship or consent state',
                            'داده نمایشی — وضعیت زنده رابطه یا رضایت نیست',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 8),
                      child: Text(
                        _t(
                          '${value.selectedPresentationIds.length} of ${value.capacity} selected',
                          '${value.selectedPresentationIds.length} از ${value.capacity} انتخاب شده',
                        ),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    if (capacityReached)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          4,
                          0,
                          4,
                          8,
                        ),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _t(
                              'Camp display limit reached. Remove a selected companion before adding another.',
                              'ظرفیت نمایش کمپ تکمیل است. برای افزودن همراه جدید، ابتدا یکی از همراهان انتخاب‌شده را حذف کنید.',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    for (final candidate in value.candidates)
                      _CandidateTile(
                        candidate: candidate,
                        selected: value.selectedPresentationIds.contains(
                          candidate.presentationId,
                        ),
                        saving: _saving,
                        isPersian: widget.isPersian,
                        onSummary: () => _openSummary(candidate),
                        onToggle: () => _toggle(value, candidate),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.selected,
    required this.saving,
    required this.isPersian,
    required this.onSummary,
    required this.onToggle,
  });

  final CampCompanionCandidate candidate;
  final bool selected;
  final bool saving;
  final bool isPersian;
  final VoidCallback onSummary;
  final VoidCallback onToggle;

  String _t(String en, String fa) => isPersian ? fa : en;

  @override
  Widget build(BuildContext context) {
    final toggleEnabled = candidate.isEligible && !saving;
    final status = selected
        ? _t('Selected for Camp', 'برای کمپ انتخاب شده')
        : candidate.isEligible
        ? _t('Not selected', 'انتخاب نشده')
        : candidate.ineligibleReason ??
              _t(
                'Not currently eligible for Camp',
                'فعلاً برای کمپ واجد شرایط نیست',
              );

    return Card(
      key: ValueKey('camp-summary-${candidate.presentationId}'),
      child: Semantics(
        button: true,
        selected: selected,
        label:
            '${candidate.displayName}, ${candidate.relationshipLabel}, $status. ${_t('Open companion summary', 'باز کردن خلاصه همراه')}',
        child: ListTile(
          leading: CircleAvatar(
            child: Text(
              candidate.displayName.isEmpty
                  ? '?'
                  : candidate.displayName.characters.first,
            ),
          ),
          title: Text(candidate.displayName),
          subtitle: Text('${candidate.relationshipLabel}\n$status'),
          isThreeLine: true,
          trailing: candidate.isEligible
              ? IconButton(
                  key: ValueKey('camp-toggle-${candidate.presentationId}'),
                  tooltip: selected
                      ? _t('Remove from Camp', 'حذف از کمپ')
                      : _t('Add to Camp', 'افزودن به کمپ'),
                  onPressed: toggleEnabled ? onToggle : null,
                  icon: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.add_circle_outline_rounded,
                  ),
                )
              : Icon(
                  Icons.lock_outline_rounded,
                  semanticLabel: _t(
                    'Camp presentation unavailable',
                    'نمایش در کمپ در دسترس نیست',
                  ),
                ),
          onTap: onSummary,
        ),
      ),
    );
  }
}

class _CompanionSummarySheet extends StatelessWidget {
  const _CompanionSummarySheet({
    required this.candidate,
    required this.selected,
    required this.refreshFailed,
    required this.synthetic,
    required this.isPersian,
  });

  final CampCompanionCandidate? candidate;
  final bool selected;
  final bool refreshFailed;
  final bool synthetic;
  final bool isPersian;

  String _t(String en, String fa) => isPersian ? fa : en;

  @override
  Widget build(BuildContext context) {
    final current = candidate;
    if (current == null) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 42),
              const SizedBox(height: 12),
              Text(
                _t(
                  'Companion summary unavailable',
                  'خلاصه همراه در دسترس نیست',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                refreshFailed
                    ? _t(
                        'The current relationship and access state could not be refreshed. No cached details are shown.',
                        'وضعیت فعلی رابطه و دسترسی قابل به‌روزرسانی نبود. هیچ جزئیات ذخیره‌شده‌ای نمایش داده نمی‌شود.',
                      )
                    : _t(
                        'This person is no longer available in the current Circle context. The relationship, consent, or active Person may have changed.',
                        'این شخص دیگر در Circle فعلی در دسترس نیست. ممکن است رابطه، رضایت یا Person فعال تغییر کرده باشد.',
                      ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_t('Close', 'بستن')),
              ),
            ],
          ),
        ),
      );
    }

    final accessLabel = current.isEligible
        ? _t('Connected', 'متصل')
        : current.ineligibleReason ??
              _t('Access unavailable', 'دسترسی در دسترس نیست');
    final campLabel = selected
        ? _t('Shown in Camp', 'در کمپ نمایش داده می‌شود')
        : current.isEligible
        ? _t('Not shown in Camp', 'در کمپ نمایش داده نمی‌شود')
        : _t('Camp presentation unavailable', 'نمایش در کمپ در دسترس نیست');

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 4, 24, 24),
        child: Semantics(
          container: true,
          label: _t('Companion summary', 'خلاصه همراه'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    child: Text(
                      current.displayName.isEmpty
                          ? '?'
                          : current.displayName.characters.first,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current.displayName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(current.relationshipLabel),
                      ],
                    ),
                  ),
                ],
              ),
              if (synthetic) ...[
                const SizedBox(height: 16),
                Text(
                  _t(
                    'Preview summary — not live relationship or consent state',
                    'خلاصه نمایشی — وضعیت زنده رابطه یا رضایت نیست',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 20),
              _SummaryRow(
                icon: Icons.people_outline_rounded,
                label: _t('Relationship', 'رابطه'),
                value: current.relationshipLabel,
              ),
              _SummaryRow(
                icon: current.isEligible
                    ? Icons.verified_user_outlined
                    : Icons.lock_outline_rounded,
                label: _t('Circle access', 'دسترسی Circle'),
                value: accessLabel,
              ),
              _SummaryRow(
                icon: selected
                    ? Icons.check_circle_outline_rounded
                    : Icons.landscape_outlined,
                label: _t('Living Camp', 'Living Camp'),
                value: campLabel,
              ),
              const SizedBox(height: 16),
              Semantics(
                label: _t('Privacy note', 'یادداشت حریم خصوصی'),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _t(
                      'This summary intentionally contains no health measurements, medications, contact details, consent events, or authorization details. Protected care information stays inside the relevant authorized module.',
                      'این خلاصه عمداً شامل اندازه‌گیری‌های سلامت، داروها، اطلاعات تماس، رویدادهای رضایت یا جزئیات مجوز دسترسی نیست. اطلاعات محافظت‌شده مراقبتی فقط داخل ماژول مربوط و با مجوز مناسب نمایش داده می‌شود.',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_t('Done', 'تمام')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FailureState extends StatelessWidget {
  const _FailureState({
    required this.isPersian,
    required this.unavailable,
    required this.onRetry,
  });

  final bool isPersian;
  final bool unavailable;
  final VoidCallback onRetry;

  String _t(String en, String fa) => isPersian ? fa : en;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline_rounded, size: 40),
            const SizedBox(height: 12),
            Text(
              unavailable
                  ? _t(
                      'Camp companion selection is not connected yet.',
                      'انتخاب همراهان کمپ هنوز متصل نیست.',
                    )
                  : _t(
                      'Camp companions could not be loaded.',
                      'همراهان کمپ بارگیری نشدند.',
                    ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(_t('Retry', 'تلاش دوباره')),
            ),
          ],
        ),
      ),
    );
  }
}
