import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../providers/care_notification_provider.dart';
import 'profile_destination_screens.dart';

class CareMateNotificationHubScreen extends StatefulWidget {
  const CareMateNotificationHubScreen({super.key});

  @override
  State<CareMateNotificationHubScreen> createState() =>
      _CareMateNotificationHubScreenState();
}

class _CareMateNotificationHubScreenState
    extends State<CareMateNotificationHubScreen> {
  late Future<_NotificationHubData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_NotificationHubData> _load() async {
    final values = await Future.wait<dynamic>([
      context.read<LifeMateApiClient>().getCareRelationships(),
      context.read<CareNotificationProvider>().notificationPermissionEnabled(),
    ]);
    final relationships = values[0] as List<Map<String, dynamic>>;
    final entries = relationships
        .where(
          (relationship) =>
              relationship['status']?.toString().toLowerCase() == 'active' &&
              relationship['notificationPreferences'] is Map<String, dynamic>,
        )
        .map(_PreferenceEntry.fromRelationship)
        .toList(growable: false);
    return _NotificationHubData(
      entries: entries,
      osNotificationsEnabled: values[1] as bool?,
    );
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(
          LifeMateRuntimeLocale.select(
            fa: 'تنظیمات اعلان‌ها',
            en: 'Notification settings',
          ),
        ),
      ),
      body: FutureBuilder<_NotificationHubData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(onRetry: _retry);
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async {
              final next = _load();
              setState(() => _future = next);
              await next;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
              children: [
                _OsPermissionCard(enabled: data.osNotificationsEnabled),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const CareMateNotificationsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: Text(
                    LifeMateRuntimeLocale.select(
                      fa: 'مشاهده هشدارهای فعال',
                      en: 'View active alerts',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (data.entries.isEmpty)
                  _EmptyState()
                else
                  ...data.entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _PersonPreferenceCard(entry: entry),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PersonPreferenceCard extends StatefulWidget {
  const _PersonPreferenceCard({required this.entry});

  final _PreferenceEntry entry;

  @override
  State<_PersonPreferenceCard> createState() => _PersonPreferenceCardState();
}

class _PersonPreferenceCardState extends State<_PersonPreferenceCard> {
  late bool _enabled;
  late bool _missed;
  late bool _careEvents;
  late bool _dailySummary;
  late String _completionMode;
  late String _dailyTime;
  late String _lockScreen;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final preferences = widget.entry.preferences;
    _enabled = preferences.enabled;
    _missed = preferences.missedAlertsEnabled;
    _careEvents = preferences.careEventsEnabled;
    _dailySummary = preferences.dailySummaryEnabled;
    _completionMode = preferences.completionMode;
    _dailyTime = preferences.dailySummaryLocalTime;
    _lockScreen = preferences.lockScreenDetail;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<LifeMateApiClient>().updateCareNotificationPreferences(
        relationshipId: widget.entry.relationshipId,
        enabled: _enabled,
        missedAlertsEnabled: _missed,
        completionMode: _completionMode,
        careEventsEnabled: _careEvents,
        dailySummaryEnabled: _dailySummary,
        dailySummaryLocalTime: _dailyTime,
        lockScreenDetail: _lockScreen,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: 'تنظیمات ${widget.entry.patientName} ذخیره شد.',
              en: '${widget.entry.patientName} settings saved.',
            ),
          ),
        ),
      );
    } on LifeMateApiException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: 'ذخیره تنظیمات انجام نشد. دوباره تلاش کنید.',
              en: 'Settings were not saved. Try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime() async {
    final parts = _dailyTime.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 20,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final result = await showTimePicker(context: context, initialTime: initial);
    if (result == null || !mounted) return;
    setState(() {
      _dailyTime =
          '${result.hour.toString().padLeft(2, '0')}:${result.minute.toString().padLeft(2, '0')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final disabled = !_enabled;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primaryBlue.withValues(alpha: .10),
                  child: const Icon(Icons.person_outline_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.entry.patientName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Switch(
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
              ],
            ),
            const Divider(height: 24),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _missed,
              onChanged: disabled
                  ? null
                  : (value) => setState(() => _missed = value),
              title: Text(
                LifeMateRuntimeLocale.select(
                  fa: 'درمان فراموش‌شده',
                  en: 'Missed treatment',
                ),
              ),
              subtitle: Text(
                LifeMateRuntimeLocale.select(
                  fa: 'فقط پس از ثبت وضعیت missed/skipped هشدار بده.',
                  en: 'Alert only after a missed/skipped status is recorded.',
                ),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _careEvents,
              onChanged: disabled
                  ? null
                  : (value) => setState(() => _careEvents = value),
              title: Text(
                LifeMateRuntimeLocale.select(
                  fa: 'ویزیت و تزریق',
                  en: 'Visits and injections',
                ),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _completionMode,
              decoration: InputDecoration(
                labelText: LifeMateRuntimeLocale.select(
                  fa: 'اعلان انجام درمان',
                  en: 'Treatment completion',
                ),
              ),
              items: _completionOptions()
                  .map(
                    (option) => DropdownMenuItem(
                      value: option.$1,
                      child: Text(option.$2),
                    ),
                  )
                  .toList(growable: false),
              onChanged: disabled
                  ? null
                  : (value) => setState(() => _completionMode = value ?? 'off'),
            ),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _dailySummary,
              onChanged: disabled
                  ? null
                  : (value) => setState(() => _dailySummary = value),
              title: Text(
                LifeMateRuntimeLocale.select(
                  fa: 'خلاصه روزانه',
                  en: 'Daily summary',
                ),
              ),
              subtitle: Text(
                LifeMateRuntimeLocale.select(
                  fa: 'خلاصه واقعی وضعیت درمان‌های امروز؛ بدون نتیجه‌گیری پزشکی.',
                  en: 'A factual daily treatment summary without medical inference.',
                ),
              ),
            ),
            if (_dailySummary) ...[
              ListTile(
                enabled: !disabled,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded),
                title: Text(
                  LifeMateRuntimeLocale.select(
                    fa: 'زمان خلاصه',
                    en: 'Summary time',
                  ),
                ),
                trailing: Text(_dailyTime),
                onTap: disabled ? null : _pickTime,
              ),
            ],
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _lockScreen,
              decoration: InputDecoration(
                labelText: LifeMateRuntimeLocale.select(
                  fa: 'جزئیات روی صفحه قفل',
                  en: 'Lock-screen details',
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: 'full',
                  child: Text(
                    LifeMateRuntimeLocale.select(fa: 'کامل', en: 'Full'),
                  ),
                ),
                DropdownMenuItem(
                  value: 'limited',
                  child: Text(
                    LifeMateRuntimeLocale.select(fa: 'محدود', en: 'Limited'),
                  ),
                ),
                DropdownMenuItem(
                  value: 'hidden',
                  child: Text(
                    LifeMateRuntimeLocale.select(fa: 'مخفی', en: 'Hidden'),
                  ),
                ),
              ],
              onChanged: disabled
                  ? null
                  : (value) => setState(() => _lockScreen = value ?? 'limited'),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: 'ذخیره تنظیمات این فرد',
                  en: 'Save this person’s settings',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<(String, String)> _completionOptions() => [
    ('off', LifeMateRuntimeLocale.select(fa: 'خاموش', en: 'Off')),
    ('all', LifeMateRuntimeLocale.select(fa: 'همه درمان‌ها', en: 'All treatments')),
    (
      'important',
      LifeMateRuntimeLocale.select(
        fa: 'فقط موارد مهمِ مشخص‌شده',
        en: 'Explicitly important only',
      ),
    ),
    (
      'after_missed',
      LifeMateRuntimeLocale.select(
        fa: 'فقط بعد از missed',
        en: 'Only after a miss',
      ),
    ),
    (
      'daily_summary',
      LifeMateRuntimeLocale.select(fa: 'فقط در خلاصه روزانه', en: 'Daily summary only'),
    ),
  ];
}

class _OsPermissionCard extends StatelessWidget {
  const _OsPermissionCard({required this.enabled});

  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    final isEnabled = enabled == true;
    return Card(
      elevation: 0,
      color: isEnabled ? const Color(0xFFF0FAF5) : const Color(0xFFFFF6EA),
      child: ListTile(
        leading: Icon(
          isEnabled ? Icons.notifications_active : Icons.notifications_off_outlined,
        ),
        title: Text(
          isEnabled
              ? LifeMateRuntimeLocale.select(
                  fa: 'اعلان‌های سیستم فعال‌اند',
                  en: 'System notifications are enabled',
                )
              : LifeMateRuntimeLocale.select(
                  fa: 'اعلان‌های سیستم خاموش یا نامشخص‌اند',
                  en: 'System notifications are off or unavailable',
                ),
        ),
        subtitle: Text(
          LifeMateRuntimeLocale.select(
            fa: 'تنظیمات هر فرد فقط در صورت اجازه Android می‌تواند اعلان نمایش دهد.',
            en: 'Per-person settings can deliver only when Android allows notifications.',
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        LifeMateRuntimeLocale.select(
          fa: 'برای تنظیم اعلان، ابتدا یک ارتباط مراقبتی فعال لازم است.',
          en: 'An active care relationship is required before notifications can be configured.',
        ),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: Text(
        LifeMateRuntimeLocale.select(fa: 'تلاش دوباره', en: 'Try again'),
      ),
    ),
  );
}

class _NotificationHubData {
  const _NotificationHubData({
    required this.entries,
    required this.osNotificationsEnabled,
  });

  final List<_PreferenceEntry> entries;
  final bool? osNotificationsEnabled;
}

class _PreferenceEntry {
  const _PreferenceEntry({
    required this.relationshipId,
    required this.patientName,
    required this.preferences,
  });

  final String relationshipId;
  final String patientName;
  final _Preferences preferences;

  factory _PreferenceEntry.fromRelationship(Map<String, dynamic> value) {
    final preferences = value['notificationPreferences'] as Map<String, dynamic>;
    return _PreferenceEntry(
      relationshipId: value['id'].toString(),
      patientName: value['patientDisplayName']?.toString().trim().isNotEmpty == true
          ? value['patientDisplayName'].toString()
          : LifeMateRuntimeLocale.select(
              fa: 'فرد تحت مراقبت',
              en: 'Person under care',
            ),
      preferences: _Preferences.fromJson(preferences),
    );
  }
}

class _Preferences {
  const _Preferences({
    required this.enabled,
    required this.missedAlertsEnabled,
    required this.completionMode,
    required this.careEventsEnabled,
    required this.dailySummaryEnabled,
    required this.dailySummaryLocalTime,
    required this.lockScreenDetail,
  });

  final bool enabled;
  final bool missedAlertsEnabled;
  final String completionMode;
  final bool careEventsEnabled;
  final bool dailySummaryEnabled;
  final String dailySummaryLocalTime;
  final String lockScreenDetail;

  factory _Preferences.fromJson(Map<String, dynamic> value) => _Preferences(
    enabled: value['enabled'] != false,
    missedAlertsEnabled: value['missedAlertsEnabled'] != false,
    completionMode: value['completionMode']?.toString() ?? 'off',
    careEventsEnabled: value['careEventsEnabled'] != false,
    dailySummaryEnabled: value['dailySummaryEnabled'] == true,
    dailySummaryLocalTime: value['dailySummaryLocalTime']?.toString() ?? '20:00',
    lockScreenDetail: value['lockScreenDetail']?.toString() ?? 'limited',
  );
}
