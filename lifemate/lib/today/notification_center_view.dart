import 'package:flutter/material.dart';

import 'notification_center_contract.dart';
import 'today_contract.dart';
import 'today_views.dart';

Future<void> showNotificationCenter({
  required BuildContext context,
  required NotificationCenterSource source,
  required bool isPersian,
  required TodayActionHandler onAction,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.82,
      child: NotificationCenterView(
        source: source,
        isPersian: isPersian,
        onAction: onAction,
      ),
    ),
  );
}

class NotificationCenterView extends StatefulWidget {
  const NotificationCenterView({
    super.key,
    required this.source,
    required this.isPersian,
    required this.onAction,
  });

  final NotificationCenterSource source;
  final bool isPersian;
  final TodayActionHandler onAction;

  @override
  State<NotificationCenterView> createState() => _NotificationCenterViewState();
}

class _NotificationCenterViewState extends State<NotificationCenterView> {
  late Future<List<NotificationCenterItem>> _load = widget.source.load();
  final Set<String> _pending = <String>{};

  String _t(String en, String fa) => widget.isPersian ? fa : en;

  void _reload() => setState(() => _load = widget.source.load());

  @override
  void didUpdateWidget(covariant NotificationCenterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      _load = widget.source.load();
    }
  }

  Future<void> _toggleRead(NotificationCenterItem item) async {
    if (_pending.contains(item.notificationId)) return;
    setState(() => _pending.add(item.notificationId));
    try {
      await widget.source.setRead(item.notificationId, isRead: !item.isRead);
      if (mounted) _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('Could not update read state.', 'وضعیت خواندن بروزرسانی نشد.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _pending.remove(item.notificationId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Semantics(
        container: true,
        label: _t('Notification Center', 'مرکز اعلان‌ها'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 12),
              child: Text(
                _t('Notifications', 'اعلان‌ها'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<NotificationCenterItem>>(
                future: _load,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    final unavailable = snapshot.error is NotificationCenterUnavailable;
                    return _FailureState(
                      isPersian: widget.isPersian,
                      unavailable: unavailable,
                      onRetry: _reload,
                    );
                  }
                  final items = snapshot.data ?? const <NotificationCenterItem>[];
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _t('No notifications yet.', 'هنوز اعلانی ندارید.'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 20),
                    children: [
                      if (widget.source.mode == NotificationSourceMode.synthetic)
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 8),
                          child: Text(
                            _t('Preview data — not live notification state', 'داده نمایشی — وضعیت زنده اعلان‌ها نیست'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      for (final item in items)
                        _NotificationCard(
                          item: item,
                          isPersian: widget.isPersian,
                          pending: _pending.contains(item.notificationId),
                          onToggleRead: () => _toggleRead(item),
                          onAction: item.action == null ? null : () => widget.onAction(item.action!),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.isPersian,
    required this.pending,
    required this.onToggleRead,
    required this.onAction,
  });

  final NotificationCenterItem item;
  final bool isPersian;
  final bool pending;
  final VoidCallback onToggleRead;
  final VoidCallback? onAction;

  String _t(String en, String fa) => isPersian ? fa : en;

  @override
  Widget build(BuildContext context) {
    final owner = item.owner.kind == TodayOwnerKind.currentPerson
        ? _t('You', 'شما')
        : item.owner.displayName;
    final severity = switch (item.severity) {
      TodaySeverity.normal => _t('Normal', 'عادی'),
      TodaySeverity.needsAttention => _t('Needs attention', 'نیازمند توجه'),
      TodaySeverity.urgent => _t('Urgent', 'فوری'),
    };
    final severityIcon = switch (item.severity) {
      TodaySeverity.normal => Icons.notifications_none_rounded,
      TodaySeverity.needsAttention => Icons.priority_high_rounded,
      TodaySeverity.urgent => Icons.warning_amber_rounded,
    };

    return Semantics(
      container: true,
      label: '${item.display.title}, $owner, $severity, ${item.isRead ? _t('read', 'خوانده‌شده') : _t('unread', 'خوانده‌نشده')}',
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(severityIcon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.display.title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w800,
                                ),
                          ),
                        ),
                        if (!item.isRead)
                          Semantics(
                            label: _t('Unread', 'خوانده‌نشده'),
                            child: const Icon(Icons.circle, size: 10),
                          ),
                      ],
                    ),
                    if (item.display.subtitle case final subtitle?) ...[
                      const SizedBox(height: 4),
                      Text(subtitle),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _Meta(icon: Icons.person_outline, text: owner),
                        _Meta(icon: severityIcon, text: severity),
                        if (item.display.sourceLabel case final source?)
                          _Meta(icon: Icons.apps_outlined, text: source),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: pending ? null : onToggleRead,
                          icon: Icon(item.isRead ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined),
                          label: Text(item.isRead ? _t('Mark unread', 'خوانده‌نشده') : _t('Mark read', 'خوانده‌شده')),
                        ),
                        if (onAction != null)
                          TextButton.icon(
                            onPressed: onAction,
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: Text(_t('Open', 'باز کردن')),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _FailureState extends StatelessWidget {
  const _FailureState({required this.isPersian, required this.unavailable, required this.onRetry});

  final bool isPersian;
  final bool unavailable;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.notifications_off_outlined, size: 44),
              const SizedBox(height: 12),
              Text(
                unavailable
                    ? (isPersian ? 'مرکز اعلان‌ها هنوز متصل نیست' : 'Notification Center is not connected yet')
                    : (isPersian ? 'اعلان‌ها بروزرسانی نشد' : 'Notifications could not refresh'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isPersian
                    ? 'هیچ وضعیت ساختگی به‌عنوان اعلان زنده نمایش داده نمی‌شود.'
                    : 'No synthetic notification is shown as live state.',
                textAlign: TextAlign.center,
              ),
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
