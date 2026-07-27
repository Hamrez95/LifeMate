import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  bool _accepting = false;
  String? _error;
  String? _currentUserId;
  String? _selectedRelationshipId;
  List<Map<String, dynamic>> _relationships = const [];
  List<Map<String, dynamic>> _doses = const [];

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
      final api = context.read<LifeMateApiClient>();
      final results = await Future.wait([
        api.getCurrentUser(),
        api.getCareRelationships(),
      ]);
      final currentUser = results[0] as Map<String, dynamic>;
      final relationships = results[1] as List<Map<String, dynamic>>;
      final user = currentUser['user'] as Map<String, dynamic>? ?? const {};
      final currentUserId = user['id']?.toString();
      final caregiverRelationships = relationships
          .where(
            (relationship) =>
                relationship['status']?.toString() == 'active' &&
                relationship['caregiverUserId']?.toString() == currentUserId,
          )
          .toList(growable: false);

      var selectedId = _selectedRelationshipId;
      if (!caregiverRelationships
          .any((relationship) => relationship['id']?.toString() == selectedId)) {
        selectedId = caregiverRelationships.isEmpty
            ? null
            : caregiverRelationships.first['id']?.toString();
      }

      if (!mounted) return;
      setState(() {
        _currentUserId = currentUserId;
        _relationships = caregiverRelationships;
        _selectedRelationshipId = selectedId;
      });
      await _loadSelectedDoses();
    } on LifeMateApiException catch (error) {
      _setError(_friendlyApiError(error));
    } catch (error) {
      debugPrint('CareMate refresh failed: $error');
      _setError('اطلاعات مراقبت دریافت نشد. اتصال اینترنت را بررسی کنید.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSelectedDoses() async {
    final selected = _selectedRelationship;
    if (selected == null) {
      if (mounted) setState(() => _doses = const []);
      return;
    }

    final today = DateTime.now();
    final doses = await context
        .read<LifeMateApiClient>()
        .getCareRecipientDoseOccurrences(
          patientUserId: selected['patientUserId'].toString(),
          fromDate: today,
          toDate: today,
        );
    if (mounted) setState(() => _doses = doses);
  }

  Map<String, dynamic>? get _selectedRelationship {
    for (final relationship in _relationships) {
      if (relationship['id']?.toString() == _selectedRelationshipId) {
        return relationship;
      }
    }
    return null;
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  Future<void> _selectRelationship(String? relationshipId) async {
    setState(() {
      _selectedRelationshipId = relationshipId;
      _loading = true;
      _error = null;
    });
    try {
      await _loadSelectedDoses();
    } on LifeMateApiException catch (error) {
      _setError(_friendlyApiError(error));
    } catch (error) {
      debugPrint('CareMate patient switch failed: $error');
      _setError('وضعیت بیمار دریافت نشد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAcceptInvitation() async {
    final tokenController = TextEditingController();
    var confirmed = false;
    final token = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('پذیرش دعوت مراقبت'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'کد دعوت را فقط زمانی وارد کنید که بیمار آن را مستقیماً برای شما فرستاده باشد.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: tokenController,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(
                  labelText: 'کد دعوت',
                  border: OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: confirmed,
                onChanged: (value) =>
                    setDialogState(() => confirmed = value ?? false),
                title: const Text(
                  'می‌پذیرم وضعیت مصرف داروی این بیمار را فقط برای مراقبت مجاز مشاهده کنم.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: confirmed && tokenController.text.trim().isNotEmpty
                  ? () => Navigator.pop(
                        dialogContext,
                        tokenController.text.trim(),
                      )
                  : null,
              child: const Text('پذیرش امن'),
            ),
          ],
        ),
      ),
    );
    tokenController.dispose();
    if (token == null || !mounted) return;

    setState(() => _accepting = true);
    try {
      await context
          .read<LifeMateApiClient>()
          .acceptCareInvitation(token: token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('دعوت مراقبت با موفقیت پذیرفته شد.')),
      );
      await _refresh();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyApiError(error)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _revokeSelectedRelationship() async {
    final relationship = _selectedRelationship;
    if (relationship == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('قطع دسترسی مراقبت؟'),
        content: const Text(
          'پس از قطع دسترسی، دیگر وضعیت داروهای این بیمار را مشاهده نمی‌کنید. بیمار می‌تواند بعداً دعوت جدیدی بسازد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('قطع دسترسی'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await context.read<LifeMateApiClient>().revokeCareRelationship(
            relationshipId: relationship['id'].toString(),
          );
      await _refresh();
    } on LifeMateApiException catch (error) {
      _setError(_friendlyApiError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedRelationship;
    final taken = _doses.where((dose) => dose['status'] == 'taken').length;
    final skipped = _doses.where((dose) => dose['status'] == 'skipped').length;
    final missed = _doses.where((dose) => dose['status'] == 'missed').length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'CareMate',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'پذیرش دعوت',
            onPressed: _accepting ? null : _showAcceptInvitation,
            icon: _accepting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1_rounded),
          ),
          IconButton(
            tooltip: 'خروج از حساب',
            onPressed: () => LifeMateAuth.signOut(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            if (_currentUserId == null && _loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_relationships.isEmpty)
              _EmptyCareState(onAccept: _showAcceptInvitation)
            else ...[
              DropdownButtonFormField<String>(
                value: _selectedRelationshipId,
                decoration: const InputDecoration(
                  labelText: 'فرد تحت مراقبت',
                  prefixIcon: Icon(Icons.family_restroom_rounded),
                  border: OutlineInputBorder(),
                ),
                items: _relationships
                    .map(
                      (relationship) => DropdownMenuItem(
                        value: relationship['id'].toString(),
                        child: Text(
                          relationship['patientDisplayName']?.toString() ??
                              'بیمار',
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _loading ? null : _selectRelationship,
              ),
              const SizedBox(height: 20),
              if (selected != null)
                _SummaryCard(
                  patientName:
                      selected['patientDisplayName']?.toString() ?? 'بیمار',
                  total: _doses.length,
                  taken: taken,
                  skipped: skipped,
                  missed: missed,
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'برنامه دارویی امروز',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _loading ? null : _revokeSelectedRelationship,
                    icon: const Icon(Icons.link_off_rounded, size: 18),
                    label: const Text('قطع دسترسی'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _ErrorState(message: _error!, onRetry: _refresh)
              else if (_doses.isEmpty)
                const _NoDosesState()
              else
                ..._doses.map((dose) => _DoseCard(dose: dose)),
            ],
            if (_relationships.isEmpty && _error != null)
              _ErrorState(message: _error!, onRetry: _refresh),
          ],
        ),
      ),
    );
  }

  static String _friendlyApiError(LifeMateApiException error) {
    switch (error.code) {
      case 'care_access_denied':
        return 'دسترسی مراقبت لغو شده است. فهرست را تازه‌سازی کنید.';
      case 'invitation_contact_mismatch':
        return 'این دعوت برای حساب دیگری صادر شده است.';
      case 'invitation_expired':
        return 'مهلت این دعوت تمام شده است؛ از بیمار دعوت جدید بخواهید.';
      case 'invitation_not_found':
        return 'کد دعوت معتبر نیست.';
      default:
        return error.isUnauthorized
            ? 'نشست شما منقضی شده است. دوباره وارد شوید.'
            : 'درخواست انجام نشد. دوباره تلاش کنید.';
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.patientName,
    required this.total,
    required this.taken,
    required this.skipped,
    required this.missed,
  });

  final String patientName;
  final int total;
  final int taken;
  final int skipped;
  final int missed;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : taken / total;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppColors.softDecoration(color: Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            patientName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text('$taken از $total دوز امروز مصرف شده'),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: const Color(0xFFE8EDF3),
              color: const Color(0xFF36A269),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(label: 'مصرف‌شده $taken', color: const Color(0xFF36A269)),
              _StatusChip(label: 'مصرف‌نشده $skipped', color: Colors.orange),
              _StatusChip(label: 'ازدست‌رفته $missed', color: Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: CircleAvatar(radius: 5, backgroundColor: color),
        label: Text(label),
        backgroundColor: color.withValues(alpha: 0.08),
        side: BorderSide.none,
      );
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({required this.dose});

  final Map<String, dynamic> dose;

  @override
  Widget build(BuildContext context) {
    final status = dose['status']?.toString() ?? 'scheduled';
    final statusView = switch (status) {
      'taken' => ('مصرف شده', Icons.check_circle_rounded, const Color(0xFF36A269)),
      'skipped' => ('مصرف نشده', Icons.remove_circle_rounded, Colors.orange),
      'missed' => ('ازدست‌رفته', Icons.error_rounded, Colors.redAccent),
      _ => ('در انتظار', Icons.schedule_rounded, AppColors.primaryBlue),
    };
    final rawTime = dose['scheduledLocalTime']?.toString() ?? '--:--';
    final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      child: ListTile(
        minVerticalPadding: 14,
        leading: CircleAvatar(
          backgroundColor: statusView.$3.withValues(alpha: 0.1),
          child: Icon(statusView.$2, color: statusView.$3),
        ),
        title: Text(
          dose['medicationName']?.toString() ?? 'دارو',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('${dose['doseText'] ?? ''} • $time'),
        trailing: Text(
          statusView.$1,
          style: TextStyle(
            color: statusView.$3,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _EmptyCareState extends StatelessWidget {
  const _EmptyCareState({required this.onAccept});

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(
          children: [
            const Icon(
              Icons.health_and_safety_outlined,
              size: 72,
              color: AppColors.primaryBlue,
            ),
            const SizedBox(height: 18),
            const Text(
              'هنوز فردی به مراقبت شما متصل نیست',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'کد دعوتی را که بیمار در WellMate ساخته است وارد کنید.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAccept,
              icon: const Icon(Icons.vpn_key_rounded),
              label: const Text('واردکردن کد دعوت'),
            ),
          ],
        ),
      );
}

class _NoDosesState extends StatelessWidget {
  const _NoDosesState();

  @override
  Widget build(BuildContext context) => const Card(
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            children: [
              Icon(Icons.event_available_rounded, size: 48),
              SizedBox(height: 10),
              Text(
                'برای امروز دوز فعالی ثبت نشده است.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('تلاش دوباره'),
            ),
          ],
        ),
      );
}
