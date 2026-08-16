import 'package:flutter/material.dart';

import 'app_notice.dart';
import 'lifemate_api_client.dart';
import 'runtime_locale.dart';

enum LifeMateCareAccessRole { patient, caregiver }

class LifeMateCareAccessInventoryScreen extends StatefulWidget {
  const LifeMateCareAccessInventoryScreen({
    required this.apiClient,
    required this.role,
    required this.accent,
    required this.background,
    required this.ink,
    this.onManage,
    super.key,
  });

  final LifeMateApiClient apiClient;
  final LifeMateCareAccessRole role;
  final Color accent;
  final Color background;
  final Color ink;
  final VoidCallback? onManage;

  @override
  State<LifeMateCareAccessInventoryScreen> createState() =>
      _LifeMateCareAccessInventoryScreenState();
}

class _LifeMateCareAccessInventoryScreenState
    extends State<LifeMateCareAccessInventoryScreen> {
  bool _loading = true;
  String? _error;
  String? _currentUserId;
  List<Map<String, dynamic>> _relationships = const [];
  List<Map<String, dynamic>> _outgoing = const [];
  List<Map<String, dynamic>> _incoming = const [];
  final Set<String> _busyIds = <String>{};

  bool get _isPatient => widget.role == LifeMateCareAccessRole.patient;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<Object>([
        widget.apiClient.getCurrentUser(),
        widget.apiClient.getCareRelationships(),
        if (_isPatient) widget.apiClient.getOutgoingCareInvitations(),
        if (_isPatient) widget.apiClient.getIncomingCareRequests(),
        if (!_isPatient) widget.apiClient.getOutgoingCareRequests(),
      ]);
      final current = results[0] as Map<String, dynamic>;
      final userId = (current['user'] as Map<String, dynamic>?)?['id']?.toString();
      final relationships = (results[1] as List<Map<String, dynamic>>)
          .where((row) {
            final field = _isPatient ? 'patientUserId' : 'caregiverUserId';
            return userId != null && row[field]?.toString() == userId;
          })
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _currentUserId = userId;
        _relationships = relationships;
        if (_isPatient) {
          _outgoing = results[2] as List<Map<String, dynamic>>;
          _incoming = results[3] as List<Map<String, dynamic>>;
        } else {
          _outgoing = results[2] as List<Map<String, dynamic>>;
          _incoming = const [];
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = LifeMateRuntimeLocale.select(
            fa: 'فهرست دسترسی‌ها دریافت نشد. دوباره تلاش کنید.',
            en: 'Access inventory could not be loaded. Try again.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(Map<String, dynamic> relationship) async {
    final id = relationship['id']?.toString();
    if (id == null || id.isEmpty || _busyIds.contains(id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          LifeMateRuntimeLocale.select(
            fa: 'قطع دسترسی؟',
            en: 'Revoke access?',
          ),
        ),
        content: Text(
          LifeMateRuntimeLocale.select(
            fa: 'این ارتباط فوراً غیرفعال می‌شود و برای دسترسی دوباره به رضایت جدید نیاز دارد.',
            en: 'This relationship will be disabled immediately and new consent is required before access can return.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              LifeMateRuntimeLocale.select(fa: 'انصراف', en: 'Cancel'),
            ),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              LifeMateRuntimeLocale.select(fa: 'قطع دسترسی', en: 'Revoke'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyIds.add(id));
    try {
      await widget.apiClient.revokeCareRelationship(relationshipId: id);
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: LifeMateRuntimeLocale.select(
          fa: 'دسترسی قطع شد',
          en: 'Access revoked',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: 'ارتباط به تاریخچه منتقل شد.',
          en: 'The relationship moved to access history.',
        ),
      );
      await _refresh();
    } catch (_) {
      if (mounted) {
        LifeMateNotice.show(
          context,
          type: LifeMateNoticeType.error,
          title: LifeMateRuntimeLocale.select(
            fa: 'قطع دسترسی انجام نشد',
            en: 'Access was not revoked',
          ),
          message: LifeMateRuntimeLocale.select(
            fa: 'اتصال را بررسی کنید و دوباره تلاش کنید.',
            en: 'Check your connection and try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _relationships
        .where((row) => _status(row) == 'active')
        .toList(growable: false);
    final pending = <_AccessHistoryItem>[
      ..._outgoing
          .where((row) => _status(row) == 'pending')
          .map((row) => _itemFromOutgoing(row, pending: true)),
      ..._incoming
          .where((row) => _status(row) == 'pending')
          .map((row) => _itemFromIncoming(row, pending: true)),
    ];
    final history = <_AccessHistoryItem>[
      ..._relationships
          .where((row) => _status(row) != 'active')
          .map(_itemFromRelationship),
      ..._outgoing
          .where((row) => _status(row) != 'pending')
          .map((row) => _itemFromOutgoing(row, pending: false)),
      ..._incoming
          .where((row) => _status(row) != 'pending')
          .map((row) => _itemFromIncoming(row, pending: false)),
    ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    return Scaffold(
      backgroundColor: widget.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(
          LifeMateRuntimeLocale.select(
            fa: 'دسترسی و ارتباط‌ها',
            en: 'Access & relationships',
          ),
          style: TextStyle(color: widget.ink, fontWeight: FontWeight.w900),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
          children: [
            _InventoryHero(
              accent: widget.accent,
              ink: widget.ink,
              role: widget.role,
              onManage: widget.onManage,
            ),
            const SizedBox(height: 22),
            if (_loading && _currentUserId == null)
              const Center(child: Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(),
              ))
            else if (_error != null)
              _InventoryError(message: _error!, onRetry: _refresh)
            else ...[
              _InventorySection(
                title: LifeMateRuntimeLocale.select(
                  fa: _isPatient ? 'مراقبان فعال' : 'افراد تحت مراقبت',
                  en: _isPatient ? 'Active caregivers' : 'Active care recipients',
                ),
                count: active.length,
                child: active.isEmpty
                    ? _EmptyInventoryCard(
                        text: LifeMateRuntimeLocale.select(
                          fa: 'ارتباط فعالی وجود ندارد.',
                          en: 'There is no active relationship.',
                        ),
                      )
                    : Column(
                        children: active
                            .map((row) => _ActiveRelationshipCard(
                                  row: row,
                                  role: widget.role,
                                  accent: widget.accent,
                                  busy: _busyIds.contains(row['id']?.toString()),
                                  onRevoke: () => _revoke(row),
                                ))
                            .toList(growable: false),
                      ),
              ),
              const SizedBox(height: 22),
              _InventorySection(
                title: LifeMateRuntimeLocale.select(
                  fa: 'در انتظار پاسخ',
                  en: 'Pending',
                ),
                count: pending.length,
                child: pending.isEmpty
                    ? _EmptyInventoryCard(
                        text: LifeMateRuntimeLocale.select(
                          fa: 'درخواست یا دعوت بازی وجود ندارد.',
                          en: 'There is no pending request or invitation.',
                        ),
                      )
                    : Column(
                        children: pending
                            .map((item) => _HistoryCard(
                                  item: item,
                                  accent: widget.accent,
                                  pending: true,
                                ))
                            .toList(growable: false),
                      ),
              ),
              const SizedBox(height: 22),
              _InventorySection(
                title: LifeMateRuntimeLocale.select(
                  fa: 'تاریخچه دسترسی',
                  en: 'Access history',
                ),
                count: history.length,
                child: history.isEmpty
                    ? _EmptyInventoryCard(
                        text: LifeMateRuntimeLocale.select(
                          fa: 'هنوز رویداد بسته‌شده‌ای در تاریخچه نیست.',
                          en: 'There is no closed access event yet.',
                        ),
                      )
                    : Column(
                        children: history
                            .map((item) => _HistoryCard(
                                  item: item,
                                  accent: widget.accent,
                                  pending: false,
                                ))
                            .toList(growable: false),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _AccessHistoryItem _itemFromRelationship(Map<String, dynamic> row) {
    final label = _isPatient
        ? _safeLabel(row['caregiverDisplayName'])
        : _safeLabel(row['patientDisplayName']);
    return _AccessHistoryItem(
      label: label,
      status: _status(row),
      kind: LifeMateRuntimeLocale.select(fa: 'ارتباط مراقبتی', en: 'Care relationship'),
      occurredAt: _timestamp(row, const ['revokedAtUtc', 'updatedAtUtc', 'createdAtUtc']),
    );
  }

  _AccessHistoryItem _itemFromOutgoing(
    Map<String, dynamic> row, {
    required bool pending,
  }) {
    final fallback = _isPatient
        ? LifeMateRuntimeLocale.select(fa: 'دعوت مراقب', en: 'Caregiver invitation')
        : LifeMateRuntimeLocale.select(fa: 'درخواست مراقبت', en: 'Care request');
    return _AccessHistoryItem(
      label: _safeLabel(row['contactHint'], fallback: fallback),
      status: _status(row),
      kind: fallback,
      occurredAt: _timestamp(row, const [
        'respondedAtUtc',
        'revokedAtUtc',
        'expiresAtUtc',
        'createdAtUtc',
      ]),
    );
  }

  _AccessHistoryItem _itemFromIncoming(
    Map<String, dynamic> row, {
    required bool pending,
  }) => _AccessHistoryItem(
        label: _safeLabel(
          row['requesterDisplayName'],
          fallback: LifeMateRuntimeLocale.select(
            fa: 'درخواست مراقب',
            en: 'Caregiver request',
          ),
        ),
        status: _status(row),
        kind: LifeMateRuntimeLocale.select(
          fa: 'درخواست مراقب',
          en: 'Caregiver request',
        ),
        occurredAt: _timestamp(row, const [
          'respondedAtUtc',
          'revokedAtUtc',
          'expiresAtUtc',
          'createdAtUtc',
        ]),
      );

  static String _status(Map<String, dynamic> row) =>
      row['status']?.toString().trim().toLowerCase() ?? 'unknown';

  static String _safeLabel(Object? value, {String? fallback}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.length > 100) {
      return fallback ?? LifeMateRuntimeLocale.select(fa: 'ارتباط مراقبتی', en: 'Care relationship');
    }
    return text;
  }

  static DateTime _timestamp(
    Map<String, dynamic> row,
    List<String> candidates,
  ) {
    for (final key in candidates) {
      final parsed = DateTime.tryParse(row[key]?.toString() ?? '');
      if (parsed != null) return parsed.toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}

class _AccessHistoryItem {
  const _AccessHistoryItem({
    required this.label,
    required this.status,
    required this.kind,
    required this.occurredAt,
  });

  final String label;
  final String status;
  final String kind;
  final DateTime occurredAt;
}

class _InventoryHero extends StatelessWidget {
  const _InventoryHero({
    required this.accent,
    required this.ink,
    required this.role,
    required this.onManage,
  });

  final Color accent;
  final Color ink;
  final LifeMateCareAccessRole role;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.admin_panel_settings_rounded, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    LifeMateRuntimeLocale.select(
                      fa: 'چه کسی به چه چیزی دسترسی دارد، همیشه باید روشن باشد.',
                      en: 'Who has access should always be clear.',
                    ),
                    style: TextStyle(
                      color: ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            if (onManage != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onManage,
                  icon: const Icon(Icons.tune_rounded),
                  label: Text(
                    LifeMateRuntimeLocale.select(
                      fa: role == LifeMateCareAccessRole.patient
                          ? 'مدیریت مراقبان و دعوت‌ها'
                          : 'مدیریت اتصال و درخواست‌ها',
                      en: role == LifeMateCareAccessRole.patient
                          ? 'Manage caregivers & invitations'
                          : 'Manage pairing & requests',
                    ),
                  ),
                  style: FilledButton.styleFrom(backgroundColor: accent),
                ),
              ),
            ],
          ],
        ),
      );
}

class _InventorySection extends StatelessWidget {
  const _InventorySection({
    required this.title,
    required this.count,
    required this.child,
  });

  final String title;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    )),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F3F7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$count',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      );
}

class _ActiveRelationshipCard extends StatelessWidget {
  const _ActiveRelationshipCard({
    required this.row,
    required this.role,
    required this.accent,
    required this.busy,
    required this.onRevoke,
  });

  final Map<String, dynamic> row;
  final LifeMateCareAccessRole role;
  final Color accent;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final label = role == LifeMateCareAccessRole.patient
        ? row['caregiverDisplayName']?.toString()
        : row['patientDisplayName']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: .12),
          child: Icon(Icons.people_alt_rounded, color: accent),
        ),
        title: Text(
          (label?.trim().isNotEmpty ?? false)
              ? label!.trim()
              : LifeMateRuntimeLocale.select(fa: 'ارتباط فعال', en: 'Active relationship'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          LifeMateRuntimeLocale.select(fa: 'فعال', en: 'Active'),
          style: const TextStyle(color: Color(0xFF4F7A67)),
        ),
        trailing: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : IconButton(
                tooltip: LifeMateRuntimeLocale.select(fa: 'قطع دسترسی', en: 'Revoke access'),
                onPressed: onRevoke,
                icon: const Icon(Icons.link_off_rounded),
              ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.item,
    required this.accent,
    required this.pending,
  });

  final _AccessHistoryItem item;
  final Color accent;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final status = _statusLabel(item.status);
    final date = item.occurredAt.millisecondsSinceEpoch == 0
        ? ''
        : MaterialLocalizations.of(context).formatMediumDate(item.occurredAt.toLocal());
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        leading: Icon(
          pending ? Icons.schedule_rounded : Icons.history_rounded,
          color: accent,
        ),
        title: Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [item.kind, status, if (date.isNotEmpty) date].join(' • '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
        'active' => LifeMateRuntimeLocale.select(fa: 'فعال', en: 'Active'),
        'pending' => LifeMateRuntimeLocale.select(fa: 'در انتظار', en: 'Pending'),
        'accepted' => LifeMateRuntimeLocale.select(fa: 'پذیرفته‌شده', en: 'Accepted'),
        'rejected' => LifeMateRuntimeLocale.select(fa: 'ردشده', en: 'Rejected'),
        'revoked' => LifeMateRuntimeLocale.select(fa: 'لغوشده', en: 'Revoked'),
        'expired' => LifeMateRuntimeLocale.select(fa: 'منقضی‌شده', en: 'Expired'),
        'cancelled' => LifeMateRuntimeLocale.select(fa: 'لغوشده', en: 'Cancelled'),
        _ => LifeMateRuntimeLocale.select(fa: 'بسته‌شده', en: 'Closed'),
      };
}

class _EmptyInventoryCard extends StatelessWidget {
  const _EmptyInventoryCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(text, style: const TextStyle(color: Color(0xFF6B7585))),
      );
}

class _InventoryError extends StatelessWidget {
  const _InventoryError({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 36),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: Text(LifeMateRuntimeLocale.select(fa: 'تلاش دوباره', en: 'Try again')),
            ),
          ],
        ),
      );
}
