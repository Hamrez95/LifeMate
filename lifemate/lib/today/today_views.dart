import 'package:flutter/material.dart';

import 'today_contract.dart';

typedef TodayActionHandler = Future<void> Function(TodayActionIntent intent);

Future<void> showTodayPeekSheet({
  required BuildContext context,
  required TodaySnapshotSource source,
  required bool isPersian,
  required VoidCallback onViewFullDay,
  required TodayActionHandler onAction,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => TodayPeekSheet(
      source: source,
      isPersian: isPersian,
      onViewFullDay: () {
        Navigator.of(sheetContext).pop();
        onViewFullDay();
      },
      onAction: onAction,
    ),
  );
}

class TodayPeekSheet extends StatelessWidget {
  const TodayPeekSheet({
    super.key,
    required this.source,
    required this.isPersian,
    required this.onViewFullDay,
    required this.onAction,
  });

  final TodaySnapshotSource source;
  final bool isPersian;
  final VoidCallback onViewFullDay;
  final TodayActionHandler onAction;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.62,
        ),
        child: TodayResolvedView(
          source: source,
          isPersian: isPersian,
          peek: true,
          onAction: onAction,
          footer: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 20),
            child: FilledButton.icon(
              onPressed: onViewFullDay,
              icon: const Icon(Icons.open_in_full_rounded),
              label: Text(isPersian ? 'مشاهده کل روز' : 'View full day'),
            ),
          ),
        ),
      ),
    );
  }
}

class TodayFullDay extends StatelessWidget {
  const TodayFullDay({
    super.key,
    required this.source,
    required this.isPersian,
    required this.onAction,
  });

  final TodaySnapshotSource source;
  final bool isPersian;
  final TodayActionHandler onAction;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: TodayResolvedView(
        source: source,
        isPersian: isPersian,
        peek: false,
        onAction: onAction,
      ),
    );
  }
}

class TodayResolvedView extends StatefulWidget {
  const TodayResolvedView({
    super.key,
    required this.source,
    required this.isPersian,
    required this.peek,
    required this.onAction,
    this.footer,
  });

  final TodaySnapshotSource source;
  final bool isPersian;
  final bool peek;
  final TodayActionHandler onAction;
  final Widget? footer;

  @override
  State<TodayResolvedView> createState() => _TodayResolvedViewState();
}

class _TodayResolvedViewState extends State<TodayResolvedView> {
  late Future<TodaySnapshot> _load = widget.source.load();

  String _t(String en, String fa) => widget.isPersian ? fa : en;

  void _retry() {
    setState(() => _load = widget.source.load());
  }

  @override
  void didUpdateWidget(covariant TodayResolvedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      _load = widget.source.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: widget.peek
          ? _t('Today priorities', 'اولویت‌های امروز')
          : _t('Today', 'امروز'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 8),
            child: Text(
              widget.peek
                  ? _t('Today', 'امروز')
                  : _t('Your full day', 'کل روز شما'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: FutureBuilder<TodaySnapshot>(
              future: _load,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return _LoadingState(isPersian: widget.isPersian);
                }
                if (snapshot.hasError) {
                  return _FailureState(
                    isPersian: widget.isPersian,
                    unavailable: snapshot.error is TodaySourceUnavailable,
                    onRetry: _retry,
                  );
                }
                final value = snapshot.data!;
                final items = widget.peek ? value.peekItems : value.sortedItems;
                return _LoadedToday(
                  snapshot: value,
                  items: items,
                  isPersian: widget.isPersian,
                  sourceMode: widget.source.mode,
                  onAction: widget.onAction,
                );
              },
            ),
          ),
          if (widget.footer case final footer?) footer,
        ],
      ),
    );
  }
}

class _LoadedToday extends StatelessWidget {
  const _LoadedToday({
    required this.snapshot,
    required this.items,
    required this.isPersian,
    required this.sourceMode,
    required this.onAction,
  });

  final TodaySnapshot snapshot;
  final List<TodayItem> items;
  final bool isPersian;
  final TodaySourceMode sourceMode;
  final TodayActionHandler onAction;

  String _t(String en, String fa) => isPersian ? fa : en;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 8),
      children: [
        if (sourceMode == TodaySourceMode.synthetic)
          _Notice(
            icon: Icons.science_outlined,
            text: _t(
              'Preview data — not live health state',
              'داده نمایشی — وضعیت زنده سلامت نیست',
            ),
          ),
        if (snapshot.freshness == TodayFreshness.cached)
          _Notice(
            icon: Icons.cloud_off_outlined,
            text: _t(
              'Showing the last safe refresh',
              'نمایش آخرین بروزرسانی امن',
            ),
          ),
        if (snapshot.completeness == TodayCompleteness.partial)
          _Notice(
            icon: Icons.info_outline_rounded,
            text: _t(
              'Some information could not refresh',
              'بخشی از اطلاعات بروزرسانی نشد',
            ),
          ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Column(
              children: [
                const Icon(Icons.wb_sunny_outlined, size: 44),
                const SizedBox(height: 12),
                Text(
                  _t(
                    'Nothing needs your attention right now.',
                    'در حال حاضر چیزی نیاز به توجه شما ندارد.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          for (final item in items)
            _TodayItemCard(
              item: item,
              isPersian: isPersian,
              onAction: onAction,
            ),
      ],
    );
  }
}

class _TodayItemCard extends StatelessWidget {
  const _TodayItemCard({
    required this.item,
    required this.isPersian,
    required this.onAction,
  });

  final TodayItem item;
  final bool isPersian;
  final TodayActionHandler onAction;

  String _t(String en, String fa) => isPersian ? fa : en;

  @override
  Widget build(BuildContext context) {
    final owner = item.owner.kind == TodayOwnerKind.currentPerson
        ? _t('You', 'شما')
        : item.owner.displayName;
    final severityLabel = switch (item.severity) {
      TodaySeverity.normal => null,
      TodaySeverity.needsAttention => _t('Needs attention', 'نیازمند توجه'),
      TodaySeverity.urgent => _t('Urgent', 'فوری'),
    };
    final icon = switch (item.severity) {
      TodaySeverity.normal => Icons.check_circle_outline_rounded,
      TodaySeverity.needsAttention => Icons.priority_high_rounded,
      TodaySeverity.urgent => Icons.warning_amber_rounded,
    };
    final action = item.action;

    return Semantics(
      container: true,
      label: [
        item.display.title,
        owner,
        if (item.display.timeLabel case final time?) time,
        if (severityLabel != null) severityLabel,
      ].join(', '),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: ListTile(
          minVerticalPadding: 12,
          leading: Icon(icon),
          title: Text(item.display.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.display.subtitle case final subtitle?) Text(subtitle),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _ChipLabel(icon: Icons.person_outline, label: owner),
                  if (item.display.timeLabel case final time?)
                    _ChipLabel(icon: Icons.schedule_outlined, label: time),
                  if (item.display.sourceLabel case final source?)
                    _ChipLabel(icon: Icons.apps_outlined, label: source),
                  if (severityLabel != null)
                    _ChipLabel(icon: icon, label: severityLabel),
                ],
              ),
            ],
          ),
          trailing: action == null
              ? null
              : const Icon(Icons.chevron_right_rounded),
          enabled: item.state == TodayItemState.actionable && action != null,
          onTap: item.state == TodayItemState.actionable && action != null
              ? () => onAction(action)
              : null,
        ),
      ),
    );
  }
}

class _ChipLabel extends StatelessWidget {
  const _ChipLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.isPersian});

  final bool isPersian;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: isPersian ? 'در حال بارگذاری امروز' : 'Loading Today',
        child: const CircularProgressIndicator(),
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

  @override
  Widget build(BuildContext context) {
    final title = unavailable
        ? (isPersian
              ? 'اطلاعات امروز هنوز متصل نیست'
              : 'Today is not connected yet')
        : (isPersian ? 'بروزرسانی امروز انجام نشد' : 'Today could not refresh');
    final message = unavailable
        ? (isPersian
              ? 'هیچ وظیفه یا وضعیت سلامت ساختگی نمایش داده نمی‌شود.'
              : 'No synthetic task or health state is shown as live data.')
        : (isPersian
              ? 'دوباره تلاش کنید. جزئیات خطای سرویس نمایش داده نمی‌شود.'
              : 'Try again. Service error details are not exposed here.');

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              unavailable ? Icons.link_off_rounded : Icons.sync_problem_rounded,
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(isPersian ? 'تلاش دوباره' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
