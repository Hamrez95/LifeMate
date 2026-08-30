import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import 'women_circle_api.dart';

class WomenCircleCard extends StatefulWidget {
  const WomenCircleCard({super.key});

  @override
  State<WomenCircleCard> createState() => _WomenCircleCardState();
}

class _WomenCircleCardState extends State<WomenCircleCard> {
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _circles = const [];
  List<Map<String, dynamic>> _invitations = const [];
  List<Map<String, dynamic>> _relationships = const [];
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final dashboard = await context.read<LifeMateApiClient>().getWomenCalendarDashboard(
        fromDate: now.subtract(const Duration(days: 30)),
        toDate: now,
      );
      if (!mounted) return;
      _applyDashboard(dashboard);
    } catch (_) {
      // Circle is additive; a failed refresh must not block the period calendar.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyDashboard(Map<String, dynamic> dashboard) {
    final profile = dashboard['profile'] as Map<String, dynamic>? ?? const {};
    final currentUser = dashboard['currentUser'] as Map<String, dynamic>? ?? const {};
    final user = currentUser['user'] as Map<String, dynamic>? ?? const {};
    setState(() {
      _circles = (profile['circles'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      _invitations = (profile['circleInvitations'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      _relationships = (dashboard['relationships'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      _currentUserId = user['id']?.toString();
    });
  }

  Future<void> _run(Map<String, dynamic> command) async {
    if (_saving) return;
    setState(() => _saving = true);
    final api = WomenCircleApi.fromEnvironment();
    try {
      final profile = await api.command(command);
      if (!mounted) return;
      setState(() {
        _circles = (profile['circles'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
        _invitations = (profile['circleInvitations'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
      });
    } on LifeMateApiException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_rtl ? 'تغییر Circle ذخیره نشد. دوباره تلاش کن.' : 'Circle change was not saved. Try again.')),
      );
    } finally {
      api.close();
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  List<Map<String, dynamic>> get _friendRelationships {
    final current = _currentUserId;
    return _relationships.where((row) {
      if (row['status']?.toString().toLowerCase() != 'active') return false;
      final type = (row['relationshipType'] ?? row['presentationType'])
          ?.toString()
          .toLowerCase();
      if (type != 'friend') return false;
      final patient = row['patientUserId']?.toString();
      final caregiver = row['caregiverUserId']?.toString();
      return current == null || patient == current || caregiver == current;
    }).toList(growable: false);
  }

  String? _otherAppUserId(Map<String, dynamic> row) {
    final current = _currentUserId;
    final patient = row['patientUserId']?.toString();
    final caregiver = row['caregiverUserId']?.toString();
    if (current != null && patient == current) return caregiver;
    if (current != null && caregiver == current) return patient;
    return caregiver ?? patient;
  }

  String _friendName(Map<String, dynamic> row) {
    final current = _currentUserId;
    if (row['patientUserId']?.toString() == current) {
      return row['caregiverDisplayName']?.toString() ?? (_rtl ? 'دوست' : 'Friend');
    }
    return row['patientDisplayName']?.toString() ?? (_rtl ? 'دوست' : 'Friend');
  }

  Future<void> _createCircle() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_rtl ? 'ساخت Circle' : 'Create Circle'),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _rtl ? 'نام Circle' : 'Circle name',
            hintText: _rtl ? 'مثلاً Girls Trip 🌸' : 'e.g. Girls Trip 🌸',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_rtl ? 'انصراف' : 'Cancel')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: Text(_rtl ? 'ساخت' : 'Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null) await _run({'action': 'create', 'name': name, 'iconKey': 'flower'});
  }

  Future<void> _inviteFriend(Map<String, dynamic> circle) async {
    final friends = _friendRelationships;
    if (friends.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_rtl ? 'برای دعوت، ابتدا یک رابطه Friend فعال داشته باش.' : 'Create an active Friend relationship before inviting someone.')),
        );
      }
      return;
    }
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(_rtl ? 'دعوت دوست' : 'Invite a friend', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              _rtl ? 'عضویت به‌تنهایی هیچ اطلاعات سلامت را به اشتراک نمی‌گذارد.' : 'Membership alone never shares health data.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            for (final friend in friends)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                title: Text(_friendName(friend)),
                onTap: () => Navigator.pop(sheetContext, friend),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final invitee = _otherAppUserId(selected);
    if (invitee == null || invitee.isEmpty) return;
    await _run({'action': 'invite', 'circleId': circle['id'], 'inviteeAppUserId': invitee});
  }

  Future<void> _editSharing(Map<String, dynamic> circle) async {
    final own = circle['ownSharing'] as Map<String, dynamic>? ?? const {};
    var mode = own['mode']?.toString() ?? 'none';
    var includePeriod = own['includePeriodWindow'] == true;
    var includePhase = own['includePhaseContext'] == true;
    final version = own['version'] is int ? own['version'] as int : 0;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_rtl ? 'حریم خصوصی این Circle' : 'Circle privacy', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  _rtl ? 'پیش‌فرض امن: هیچ داده حساسی به اشتراک گذاشته نمی‌شود.' : 'Safe default: no sensitive data is shared.',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                RadioListTile<String>(
                  value: 'none', groupValue: mode,
                  title: Text(_rtl ? 'بدون اشتراک' : 'No sharing'),
                  subtitle: Text(_rtl ? 'عضو می‌مانی، اما داده سلامت مشارکت نمی‌کند.' : 'Stay a member without contributing health context.'),
                  onChanged: (v) => setSheetState(() => mode = v!),
                ),
                RadioListTile<String>(
                  value: 'planning_only', groupValue: mode,
                  title: Text(_rtl ? 'فقط برنامه‌ریزی / Privacy Mode' : 'Planning only / Privacy Mode'),
                  subtitle: Text(_rtl ? 'فقط وضعیت مشتق‌شده مناسب/نامناسب؛ بدون تاریخ خام.' : 'Only derived planning suitability; no raw dates.'),
                  onChanged: (v) => setSheetState(() => mode = v!),
                ),
                RadioListTile<String>(
                  value: 'limited_context', groupValue: mode,
                  title: Text(_rtl ? 'اطلاعات محدود' : 'Limited context'),
                  subtitle: Text(_rtl ? 'فقط مواردی که پایین خودت روشن می‌کنی.' : 'Only the context you explicitly enable below.'),
                  onChanged: (v) => setSheetState(() => mode = v!),
                ),
                if (mode == 'limited_context') ...[
                  SwitchListTile(
                    value: includePeriod,
                    title: Text(_rtl ? 'بازه احتمالی دوره' : 'Likely period window'),
                    onChanged: (v) => setSheetState(() => includePeriod = v),
                  ),
                  SwitchListTile(
                    value: includePhase,
                    title: Text(_rtl ? 'زمینه کلی فاز چرخه' : 'General cycle phase context'),
                    onChanged: (v) => setSheetState(() => includePhase = v),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, {
                      'mode': mode,
                      'includePeriodWindow': mode == 'limited_context' && includePeriod,
                      'includePhaseContext': mode == 'limited_context' && includePhase,
                      'includeWellbeingContext': false,
                      'version': version,
                    }),
                    child: Text(_rtl ? 'ذخیره تنظیمات' : 'Save privacy settings'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null) return;
    await _run({'action': 'set_sharing', 'circleId': circle['id'], ...result});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('women-circle-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFD),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEAD7E2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_2_rounded, color: Color(0xFF8765B4)),
              const SizedBox(width: 8),
              Expanded(child: Text(_rtl ? 'Circle' : 'Circle', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
              TextButton.icon(
                onPressed: _saving ? null : _createCircle,
                icon: const Icon(Icons.add_rounded),
                label: Text(_rtl ? 'ساخت Circle' : 'Create Circle'),
              ),
            ],
          ),
          Text(
            _rtl
                ? 'برای برنامه‌ریزی گروهی؛ نه نمایش خام اطلاعات پزشکی.'
                : 'For group planning, never a raw medical-data overlay.',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          if (_invitations.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final invite in _invitations)
              Card(
                child: ListTile(
                  title: Text(invite['circleName']?.toString() ?? 'Circle'),
                  subtitle: Text(_rtl ? 'دعوت از طرف ${invite['inviterDisplayName'] ?? ''}' : 'Invitation from ${invite['inviterDisplayName'] ?? ''}'),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: _rtl ? 'رد' : 'Decline',
                        onPressed: _saving ? null : () => _run({'action': 'respond_invite', 'invitationId': invite['id'], 'response': 'decline'}),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      IconButton(
                        tooltip: _rtl ? 'پذیرش' : 'Accept',
                        onPressed: _saving ? null : () => _run({'action': 'respond_invite', 'invitationId': invite['id'], 'response': 'accept'}),
                        icon: const Icon(Icons.check_rounded),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 10),
          if (_circles.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF8F3FB), borderRadius: BorderRadius.circular(18)),
              child: Text(
                _rtl ? 'هنوز Circle نداری. یک گروه برای سفر یا برنامه مشترک بساز.' : 'No Circle yet. Create one for a trip or shared plan.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            for (final circle in _circles) ...[
              _circleTile(circle),
              const SizedBox(height: 8),
            ],
          if (_saving) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  Widget _circleTile(Map<String, dynamic> circle) {
    final planning = circle['planningSummary'] as Map<String, dynamic>? ?? const {};
    final summary = planning['summary']?.toString() ?? 'insufficient_data';
    final members = circle['memberCount'] ?? 0;
    final owner = circle['owner'] == true;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFEAD7E2))),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(backgroundColor: Color(0xFFFCE5EC), child: Icon(Icons.local_florist_rounded, color: Color(0xFFC83B60))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(circle['name']?.toString() ?? 'Circle', style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                      _rtl ? '${localizeDigits(context, members)} عضو • ${_planningLabel(summary)}' : '$members members • ${_planningLabel(summary)}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'privacy') await _editSharing(circle);
                  if (value == 'invite') await _inviteFriend(circle);
                  if (value == 'leave') await _run({'action': 'leave', 'circleId': circle['id']});
                  if (value == 'close') await _run({'action': 'close', 'circleId': circle['id']});
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'privacy', child: Text(_rtl ? 'حریم خصوصی' : 'Privacy settings')),
                  if (owner) PopupMenuItem(value: 'invite', child: Text(_rtl ? 'دعوت دوست' : 'Invite friend')),
                  PopupMenuItem(value: owner ? 'close' : 'leave', child: Text(owner ? (_rtl ? 'بستن Circle' : 'Close Circle') : (_rtl ? 'خروج' : 'Leave'))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _rtl
                  ? 'Circle فقط خلاصه برنامه‌ریزی مجاز را نشان می‌دهد؛ علائم، درد، یادداشت و تاریخ خام خصوصی می‌مانند.'
                  : 'Circle shows only authorized planning summaries; symptoms, pain, notes and raw dates remain private.',
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF8A7489), height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  String _planningLabel(String value) {
    switch (value) {
      case 'suitable':
        return _rtl ? 'مناسب برای برنامه‌ریزی' : 'Suitable for planning';
      case 'possibly_unsuitable':
        return _rtl ? 'احتمالاً نامناسب' : 'Possibly unsuitable';
      default:
        return _rtl ? 'اطلاعات کافی نیست' : 'Not enough information';
    }
  }
}
