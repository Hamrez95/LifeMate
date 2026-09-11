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
                    for (final candidate in value.candidates)
                      _CandidateTile(
                        candidate: candidate,
                        selected: value.selectedPresentationIds.contains(
                          candidate.presentationId,
                        ),
                        saving: _saving,
                        isPersian: widget.isPersian,
                        onPressed: () => _toggle(value, candidate),
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
    required this.onPressed,
  });

  final CampCompanionCandidate candidate;
  final bool selected;
  final bool saving;
  final bool isPersian;
  final VoidCallback onPressed;

  String _t(String en, String fa) => isPersian ? fa : en;

  @override
  Widget build(BuildContext context) {
    final enabled = candidate.isEligible && !saving;
    final status = selected
        ? _t('Selected for Camp', 'برای کمپ انتخاب شده')
        : candidate.isEligible
        ? _t('Not selected', 'انتخاب نشده')
        : candidate.ineligibleReason ??
              _t('Not currently eligible for Camp', 'فعلاً برای کمپ واجد شرایط نیست');

    return Card(
      child: Semantics(
        button: candidate.isEligible,
        enabled: enabled,
        selected: selected,
        label:
            '${candidate.displayName}, ${candidate.relationshipLabel}, $status',
        child: ListTile(
          enabled: enabled,
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
              ? Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  semanticLabel: selected
                      ? _t('Selected', 'انتخاب شده')
                      : _t('Not selected', 'انتخاب نشده'),
                )
              : const Icon(Icons.lock_outline_rounded),
          onTap: enabled ? onPressed : null,
        ),
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
