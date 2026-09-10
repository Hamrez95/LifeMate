part of '../cocoonmate_module.dart';

enum CocoonRecordsState { loading, ready, empty, error }

enum CocoonRecordKind {
  checkIn,
  appointment,
  measurement,
  medication,
  document
}

enum CocoonRecordSyncState { confirmed, pending, cached }

class CocoonRecordViewData {
  const CocoonRecordViewData({
    required this.id,
    required this.title,
    required this.dateLabel,
    required this.sectionLabel,
    required this.kind,
    required this.syncState,
    this.summary,
  });

  final String id;
  final String title;
  final String dateLabel;
  final String sectionLabel;
  final String? summary;
  final CocoonRecordKind kind;
  final CocoonRecordSyncState syncState;
}

class CocoonRecordsScreen extends StatefulWidget {
  const CocoonRecordsScreen({
    required this.fa,
    required this.state,
    required this.items,
    required this.onOpen,
    required this.onRetry,
    required this.onAdd,
    super.key,
  });

  final bool fa;
  final CocoonRecordsState state;
  final List<CocoonRecordViewData> items;
  final ValueChanged<CocoonRecordViewData>? onOpen;
  final VoidCallback onRetry;
  final VoidCallback onAdd;

  @override
  State<CocoonRecordsScreen> createState() => _CocoonRecordsScreenState();
}

class _CocoonRecordsScreenState extends State<CocoonRecordsScreen> {
  CocoonRecordKind? _filter;
  String t(String en, String fa) => widget.fa ? fa : en;

  @override
  Widget build(BuildContext context) {
    if (widget.state == CocoonRecordsState.loading) {
      return _RecordsLoading(fa: widget.fa);
    }
    if (widget.state == CocoonRecordsState.error && widget.items.isEmpty) {
      return CocoonStatePage(
        icon: Icons.folder_open_outlined,
        eyebrow: t('Records', 'سوابق'),
        title: t('Could not refresh records', 'سوابق به‌روز نشد'),
        body: t(
          'Saved information was not replaced. Try again when connected.',
          'اطلاعات ذخیره‌شده جایگزین نشده؛ پس از اتصال دوباره تلاش کن.',
        ),
        action: t('Try again', 'تلاش دوباره'),
        onPressed: widget.onRetry,
      );
    }
    final visible = _filter == null
        ? widget.items
        : widget.items.where((item) => item.kind == _filter).toList();
    if (widget.state == CocoonRecordsState.empty || widget.items.isEmpty) {
      return _RecordsEmpty(fa: widget.fa, onAdd: widget.onAdd);
    }
    return CustomScrollView(
      key: const PageStorageKey('cocoon-records'),
      slivers: [
        SliverToBoxAdapter(
          child: CocoonPagePadding(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RecordsHero(fa: widget.fa, count: widget.items.length),
                if (widget.state == CocoonRecordsState.error) ...[
                  const SizedBox(height: 14),
                  _RecordsRefreshNotice(
                    fa: widget.fa,
                    onRetry: widget.onRetry,
                  ),
                ],
                const SizedBox(height: 24),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        selected: _filter == null,
                        onSelected: (_) => setState(() => _filter = null),
                        label: Text(t('All', 'همه')),
                      ),
                      const SizedBox(width: 8),
                      for (final kind in CocoonRecordKind.values) ...[
                        ChoiceChip(
                          selected: _filter == kind,
                          onSelected: (_) => setState(() => _filter = kind),
                          label: Text(_kindLabel(kind)),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                if (visible.isEmpty)
                  _FilteredEmpty(fa: widget.fa)
                else
                  _RecordsTimeline(
                    fa: widget.fa,
                    items: visible,
                    onOpen: widget.onOpen,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _kindLabel(CocoonRecordKind kind) => switch (kind) {
        CocoonRecordKind.checkIn => t('Check-ins', 'حال روزانه'),
        CocoonRecordKind.appointment => t('Appointments', 'قرارها'),
        CocoonRecordKind.measurement => t('Measurements', 'اندازه‌گیری‌ها'),
        CocoonRecordKind.medication => t('Medication', 'داروها'),
        CocoonRecordKind.document => t('Documents', 'مدارک'),
      };
}

class _RecordsHero extends StatelessWidget {
  const _RecordsHero({required this.fa, required this.count});
  final bool fa;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(22, 24, 22, 22),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF3EC),
          borderRadius: BorderRadius.circular(CocoonRadii.hero),
          border: Border.all(color: Colors.white),
          boxShadow: CocoonElevation.subtle,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: CocoonBrandMark(
                semanticLabel: fa
                    ? 'نشان پرونده سلامت کوکون‌میت'
                    : 'CocoonMate health record mark',
                size: 58,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              fa ? 'پروندهٔ سلامت' : 'Health record',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 5),
            Text(
              fa
                  ? '${cocoonDigits('$count', true)} مورد، مرتب و یک‌جا'
                  : '$count items, organised in one place',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: CocoonTheme.muted),
            ),
          ],
        ),
      );
}

class _RecordsTimeline extends StatelessWidget {
  const _RecordsTimeline({
    required this.fa,
    required this.items,
    required this.onOpen,
  });

  final bool fa;
  final List<CocoonRecordViewData> items;
  final ValueChanged<CocoonRecordViewData>? onOpen;

  @override
  Widget build(BuildContext context) {
    String? section;
    final children = <Widget>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (item.sectionLabel != section) {
        section = item.sectionLabel;
        if (children.isNotEmpty) children.add(const SizedBox(height: 24));
        children.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 12),
            child: Text(section, style: Theme.of(context).textTheme.titleLarge),
          ),
        );
      }
      children.add(
        _RecordTimelineItem(
          fa: fa,
          item: item,
          last: index == items.length - 1 ||
              items[index + 1].sectionLabel != item.sectionLabel,
          onTap: onOpen == null ? null : () => onOpen!(item),
        ),
      );
    }
    return Column(children: children);
  }
}

class _RecordTimelineItem extends StatelessWidget {
  const _RecordTimelineItem({
    required this.fa,
    required this.item,
    required this.last,
    required this.onTap,
  });

  final bool fa;
  final CocoonRecordViewData item;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, color, background) = switch (item.kind) {
      CocoonRecordKind.checkIn => (
          Icons.favorite_outline_rounded,
          CocoonTheme.coral,
          CocoonTheme.warm
        ),
      CocoonRecordKind.appointment => (
          Icons.event_outlined,
          CocoonTheme.skyStrong,
          CocoonTheme.sky
        ),
      CocoonRecordKind.measurement => (
          Icons.monitor_weight_outlined,
          CocoonTheme.sageStrong,
          CocoonTheme.sage
        ),
      CocoonRecordKind.medication => (
          Icons.medication_outlined,
          CocoonTheme.gold,
          CocoonTheme.warm
        ),
      CocoonRecordKind.document => (
          Icons.description_outlined,
          CocoonTheme.ink,
          CocoonTheme.lilac
        ),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: color, size: 21),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 1, color: CocoonTheme.line),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 18),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(18),
                child: Ink(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 13, 12, 13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(CocoonRadii.control),
                    border: Border.all(color: CocoonTheme.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title,
                                style: Theme.of(context).textTheme.titleMedium),
                            if (item.summary != null) ...[
                              const SizedBox(height: 3),
                              Text(item.summary!,
                                  style:
                                      Theme.of(context).textTheme.bodyMedium),
                            ],
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(item.dateLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium),
                                if (item.syncState !=
                                    CocoonRecordSyncState.confirmed)
                                  _RecordSyncLabel(
                                      fa: fa, state: item.syncState),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (onTap != null)
                        Icon(
                          fa
                              ? Icons.chevron_left_rounded
                              : Icons.chevron_right_rounded,
                          color: CocoonTheme.muted,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordSyncLabel extends StatelessWidget {
  const _RecordSyncLabel({required this.fa, required this.state});
  final bool fa;
  final CocoonRecordSyncState state;

  @override
  Widget build(BuildContext context) => Text(
        switch (state) {
          CocoonRecordSyncState.pending =>
            fa ? 'در انتظار همگام‌سازی' : 'Pending sync',
          CocoonRecordSyncState.cached =>
            fa ? 'ذخیره‌شده روی دستگاه' : 'Saved on device',
          CocoonRecordSyncState.confirmed => '',
        },
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: CocoonTheme.ink,
            ),
      );
}

class _RecordsRefreshNotice extends StatelessWidget {
  const _RecordsRefreshNotice({required this.fa, required this.onRetry});
  final bool fa;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: CocoonTheme.warm,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Icon(Icons.sync_problem_outlined,
                  color: CocoonTheme.gold, size: 21),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  fa
                      ? 'سوابق ذخیره‌شده نمایش داده می‌شود؛ به‌روزرسانی انجام نشد.'
                      : 'Saved records are shown; refresh failed.',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: CocoonTheme.ink,
                      ),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                child: Text(fa ? 'تلاش دوباره' : 'Retry'),
              ),
            ],
          ),
        ),
      );
}

class _RecordsEmpty extends StatelessWidget {
  const _RecordsEmpty({required this.fa, required this.onAdd});
  final bool fa;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 38,
                  backgroundColor: CocoonTheme.sage,
                  child: Icon(Icons.folder_open_outlined,
                      color: CocoonTheme.sageStrong, size: 34),
                ),
                const SizedBox(height: 24),
                Text(
                  fa ? 'هنوز سابقه‌ای اینجا نیست' : 'No records here yet',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  fa
                      ? 'ثبت‌های روزانه، قرارها و داده‌های مراقبتی به‌ترتیب زمان اینجا دیده می‌شوند.'
                      : 'Check-ins, appointments and care data will appear here in time order.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: CocoonTheme.muted),
                ),
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(fa ? 'اولین ثبت' : 'Add first record'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _FilteredEmpty extends StatelessWidget {
  const _FilteredEmpty({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: 48),
        child: Column(
          children: [
            const Icon(Icons.filter_alt_off_outlined,
                size: 34, color: CocoonTheme.muted),
            const SizedBox(height: 12),
            Text(
              fa ? 'در این دسته موردی نیست' : 'Nothing in this category',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
}

class _RecordsLoading extends StatelessWidget {
  const _RecordsLoading({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: fa ? 'در حال آماده‌سازی سوابق' : 'Loading records',
        child: ListView.separated(
          padding: const EdgeInsetsDirectional.all(20),
          itemCount: 5,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, __) => Container(
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: CocoonTheme.line),
            ),
          ),
        ),
      );
}
