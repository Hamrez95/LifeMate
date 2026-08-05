from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    if old not in text:
        if new in text:
            return
        raise SystemExit(f'Expected snippet not found in {path}: {old[:140]!r}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


write(
    'wellmate/lib/screens/women_calendar/women_calendar_screen.dart',
    r'''import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../profile/profile_destination_screens.dart';

class WomenCalendarScreen extends StatefulWidget {
  const WomenCalendarScreen({
    super.key,
    this.onProfileChanged,
  });

  final Future<void> Function()? onProfileChanged;

  @override
  State<WomenCalendarScreen> createState() => _WomenCalendarScreenState();
}

class _WomenCalendarScreenState extends State<WomenCalendarScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _profile = const {};
  List<Map<String, dynamic>> _episodes = const [];
  DateTime? _lastPeriodStart;
  int _cycleLength = 28;
  int _periodLength = 5;
  bool _remindersEnabled = true;

  bool get _enabled => _profile['enabled'] == true;
  int get _version => _profile['version'] is int ? _profile['version'] as int : 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final api = context.read<LifeMateApiClient>();
      final results = await Future.wait<dynamic>([
        api.getWomenCalendarProfile(),
        api.getWomenCalendarEpisodes(),
      ]);
      final profile = results[0] as Map<String, dynamic>;
      final episodes = results[1] as List<Map<String, dynamic>>;
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _episodes = episodes;
        _lastPeriodStart = DateTime.tryParse(
          profile['lastPeriodStart']?.toString() ?? '',
        );
        _cycleLength = profile['cycleLength'] is int
            ? profile['cycleLength'] as int
            : 28;
        _periodLength = profile['periodLength'] is int
            ? profile['periodLength'] as int
            : 5;
        _remindersEnabled = profile['remindersEnabled'] != false;
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == 'women_calendar_feature_disabled'
            ? 'تقویم بانوان در این نسخه داخلی فعال نشده است.'
            : 'اطلاعات تقویم بانوان دریافت نشد.';
      });
    } catch (error) {
      debugPrint('Women calendar load failed: $error');
      if (mounted) setState(() => _error = 'اطلاعات تقویم بانوان دریافت نشد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  WomenCalendarEstimate? get _estimate {
    final start = _lastPeriodStart;
    if (!_enabled || start == null) return null;
    return WomenCalendarEstimate.calculate(
      lastPeriodStart: start,
      cycleLength: _cycleLength,
      periodLength: _periodLength,
    );
  }

  Map<String, dynamic>? get _openEpisode {
    for (final episode in _episodes) {
      if (episode['endedOn'] == null) return episode;
    }
    return null;
  }

  Future<void> _openSubscription() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SubscriptionScreen()),
    );
    await _load();
    await widget.onProfileChanged?.call();
  }

  Future<void> _pickStartDate() async {
    final selected = await showAppDatePicker(
      context: context,
      initialDate: _lastPeriodStart ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
      title: 'تاریخ شروع آخرین دوره',
    );
    if (selected != null && mounted) {
      setState(() => _lastPeriodStart = selected);
    }
  }

  Future<void> _saveSettings() async {
    final start = _lastPeriodStart;
    if (start == null || _saving) return;
    setState(() => _saving = true);
    try {
      _profile = await context.read<LifeMateApiClient>().updateWomenCalendarProfile(
            version: _version,
            enabled: true,
            lastPeriodStart: start,
            cycleLength: _cycleLength,
            periodLength: _periodLength,
            remindersEnabled: _remindersEnabled,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تنظیمات تقویم بانوان ذخیره شد.')),
      );
      await _load();
      await widget.onProfileChanged?.call();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'stale_women_calendar_profile'
                ? 'تنظیمات تغییر کرده است؛ صفحه تازه‌سازی شد.'
                : 'ذخیره تنظیمات انجام نشد.',
          ),
        ),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _startPeriodToday() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<LifeMateApiClient>().createWomenCalendarEpisode(
            startedOn: DateTime.now(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('شروع دوره برای امروز ثبت شد.')),
      );
      await _load();
      await widget.onProfileChanged?.call();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'women_calendar_episode_overlap'
                ? 'برای این بازه قبلاً یک دوره ثبت شده است.'
                : 'ثبت شروع دوره انجام نشد.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finishPeriodToday() async {
    final episode = _openEpisode;
    if (episode == null || _saving) return;
    setState(() => _saving = true);
    try {
      await context.read<LifeMateApiClient>().completeWomenCalendarEpisode(
            episodeId: episode['id'].toString(),
            version: episode['version'] is int ? episode['version'] as int : 1,
            endedOn: DateTime.now(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('پایان دوره برای امروز ثبت شد.')),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
      return _LockedFeature(onOpenSubscription: _openSubscription);
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    if (!_enabled) {
      return _InactiveFeature(onOpenSubscription: _openSubscription);
    }

    final estimate = _estimate;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
        children: [
          _SummaryCard(estimate: estimate),
          const SizedBox(height: 18),
          _TimelineCard(estimate: estimate),
          const SizedBox(height: 18),
          _SettingsCard(
            lastPeriodStart: _lastPeriodStart,
            cycleLength: _cycleLength,
            periodLength: _periodLength,
            remindersEnabled: _remindersEnabled,
            saving: _saving,
            onPickDate: _pickStartDate,
            onCycleChanged: (value) => setState(() => _cycleLength = value),
            onPeriodChanged: (value) => setState(() => _periodLength = value),
            onReminderChanged: (value) =>
                setState(() => _remindersEnabled = value),
            onSave: _saveSettings,
          ),
          const SizedBox(height: 18),
          _EpisodeActionsCard(
            openEpisode: _openEpisode,
            episodes: _episodes,
            saving: _saving,
            onStart: _startPeriodToday,
            onFinish: _finishPeriodToday,
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.amber.shade100),
            ),
            child: const Text(
              'این زمان‌بندی فقط یک تخمین بر اساس اطلاعات ثبت‌شده شماست و برای تشخیص، پیشگیری یا تعیین باروری استفاده نمی‌شود. در صورت خون‌ریزی غیرعادی، درد شدید یا نگرانی پزشکی با پزشک تماس بگیرید.',
              style: TextStyle(height: 1.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.estimate});
  final WomenCalendarEstimate? estimate;

  @override
  Widget build(BuildContext context) {
    final value = estimate;
    final phaseLabel = switch (value?.phase) {
      WomenCalendarPhase.period => 'دوره احتمالی',
      WomenCalendarPhase.prePeriod => 'نزدیک دوره احتمالی',
      WomenCalendarPhase.postPeriod => 'پس از دوره',
      WomenCalendarPhase.cycle => 'میانه چرخه',
      null => 'اطلاعات ناکافی',
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFEEF6), Color(0xFFF3ECFF)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                value == null ? '—' : localizeDigits(context, value.cycleDay),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF8C4B7D),
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'امروز در تقویم بانوان',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(phaseLabel),
                if (value != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'تخمین شروع دوره بعدی: ${formatAppDate(context, value.nextPeriodStart)}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.estimate});
  final WomenCalendarEstimate? estimate;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return _SoftSection(
      title: 'خط زمانی ۱۴ روز آینده',
      child: SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 14,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final date = DateTime(today.year, today.month, today.day)
                .add(Duration(days: index));
            final estimatedPeriod = estimate?.isEstimatedPeriodDay(date) == true;
            return Container(
              width: 62,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: estimatedPeriod
                    ? const Color(0xFFFFDDEB)
                    : const Color(0xFFF4F7FA),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: index == 0
                      ? AppColors.primary
                      : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    localizeDigits(context, index == 0 ? 'امروز' : index),
                    style: TextStyle(
                      fontSize: index == 0 ? 11 : 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Icon(
                    estimatedPeriod
                        ? Icons.water_drop_rounded
                        : Icons.circle_outlined,
                    size: 18,
                    color: estimatedPeriod
                        ? const Color(0xFFD95B93)
                        : Colors.blueGrey.shade300,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    formatAppDate(context, date).substring(5),
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.lastPeriodStart,
    required this.cycleLength,
    required this.periodLength,
    required this.remindersEnabled,
    required this.saving,
    required this.onPickDate,
    required this.onCycleChanged,
    required this.onPeriodChanged,
    required this.onReminderChanged,
    required this.onSave,
  });

  final DateTime? lastPeriodStart;
  final int cycleLength;
  final int periodLength;
  final bool remindersEnabled;
  final bool saving;
  final VoidCallback onPickDate;
  final ValueChanged<int> onCycleChanged;
  final ValueChanged<int> onPeriodChanged;
  final ValueChanged<bool> onReminderChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _SoftSection(
      title: 'تنظیمات چرخه',
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_rounded),
            title: const Text('شروع آخرین دوره'),
            subtitle: Text(
              lastPeriodStart == null
                  ? 'انتخاب نشده'
                  : formatAppDate(context, lastPeriodStart!),
            ),
            trailing: const Icon(Icons.edit_calendar_rounded),
            onTap: onPickDate,
          ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: cycleLength,
                  decoration: const InputDecoration(labelText: 'طول معمول چرخه'),
                  items: [
                    for (var value = 21; value <= 45; value++)
                      DropdownMenuItem(
                        value: value,
                        child: Text('${localizeDigits(context, value)} روز'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) onCycleChanged(value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: periodLength,
                  decoration: const InputDecoration(labelText: 'طول معمول خون‌ریزی'),
                  items: [
                    for (var value = 1; value <= 10; value++)
                      DropdownMenuItem(
                        value: value,
                        child: Text('${localizeDigits(context, value)} روز'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) onPeriodChanged(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: remindersEnabled,
            onChanged: onReminderChanged,
            title: const Text('یادآوری نزدیک‌شدن دوره'),
            subtitle: const Text('متن اعلان بدون جزئیات حساس نمایش داده می‌شود.'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('ذخیره تنظیمات'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeActionsCard extends StatelessWidget {
  const _EpisodeActionsCard({
    required this.openEpisode,
    required this.episodes,
    required this.saving,
    required this.onStart,
    required this.onFinish,
  });

  final Map<String, dynamic>? openEpisode;
  final List<Map<String, dynamic>> episodes;
  final bool saving;
  final VoidCallback onStart;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return _SoftSection(
      title: 'ثبت واقعی دوره',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: saving ? null : (openEpisode == null ? onStart : onFinish),
              icon: Icon(
                openEpisode == null
                    ? Icons.play_circle_fill_rounded
                    : Icons.stop_circle_rounded,
              ),
              label: Text(
                openEpisode == null
                    ? 'شروع دوره امروز'
                    : 'پایان دوره امروز',
              ),
            ),
          ),
          if (episodes.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'آخرین ثبت‌ها',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...episodes.take(4).map(
                  (episode) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.water_drop_outlined),
                    title: Text(
                      formatAppDate(
                        context,
                        DateTime.parse(episode['startedOn'].toString()),
                      ),
                    ),
                    subtitle: Text(
                      episode['endedOn'] == null
                          ? 'در حال ثبت'
                          : 'تا ${formatAppDate(context, DateTime.parse(episode['endedOn'].toString()))}',
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _SoftSection extends StatelessWidget {
  const _SoftSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 18,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );
}

class _InactiveFeature extends StatelessWidget {
  const _InactiveFeature({required this.onOpenSubscription});
  final VoidCallback onOpenSubscription;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _SoftSection(
            title: 'تقویم بانوان فعال نیست',
            child: Column(
              children: [
                const Icon(Icons.calendar_month_rounded, size: 62),
                const SizedBox(height: 12),
                const Text(
                  'برای فعال‌سازی، وارد صفحه اشتراک شوید. در نسخه داخلی آزمایشی هیچ پرداختی انجام نمی‌شود.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.7),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onOpenSubscription,
                    child: const Text('رفتن به اشتراک'),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _LockedFeature extends _InactiveFeature {
  const _LockedFeature({required super.onOpenSubscription});
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 52),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('تلاش دوباره'),
              ),
            ],
          ),
        ),
      );
}
''',
)

write(
    'wellmate/lib/screens/profile/care_access_settings_screen.dart',
    r'''import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

class CareAccessSettingsScreen extends StatefulWidget {
  const CareAccessSettingsScreen({
    super.key,
    required this.relationship,
  });

  final Map<String, dynamic> relationship;

  @override
  State<CareAccessSettingsScreen> createState() =>
      _CareAccessSettingsScreenState();
}

class _CareAccessSettingsScreenState extends State<CareAccessSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _womenCalendarEnabled = false;
  bool _canViewWomenCalendar = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _canViewWomenCalendar =
        widget.relationship['canViewWomenCalendar'] == true;
    _load();
  }

  Future<void> _load() async {
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final profile =
          await context.read<LifeMateApiClient>().getWomenCalendarProfile();
      if (!mounted) return;
      setState(() => _womenCalendarEnabled = profile['enabled'] == true);
    } catch (error) {
      debugPrint('Care permission profile load failed: $error');
      if (mounted) setState(() => _error = 'وضعیت تقویم بانوان دریافت نشد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setWomenCalendarAccess(bool value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = await context
          .read<LifeMateApiClient>()
          .updateCareRelationshipPermissions(
            relationshipId: widget.relationship['id'].toString(),
            canViewWomenCalendar: value,
          );
      if (!mounted) return;
      setState(() {
        _canViewWomenCalendar = updated['canViewWomenCalendar'] == true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'دسترسی تقویم بانوان برای این مراقب فعال شد.'
                : 'دسترسی تقویم بانوان برای این مراقب غیرفعال شد.',
          ),
        ),
      );
    } catch (error) {
      debugPrint('Care permission update failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تغییر دسترسی انجام نشد.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.relationship['caregiverDisplayName']?.toString() ??
        'مراقب';
    return Scaffold(
      appBar: AppBar(title: Text('تنظیمات دسترسی $name')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'هر دسترسی مستقل است و فقط با تصمیم شما فعال می‌شود. قطع رابطه، همه دسترسی‌ها را فوراً متوقف می‌کند.',
              style: TextStyle(height: 1.7),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            elevation: 0,
            child: Column(
              children: [
                const SwitchListTile(
                  value: true,
                  onChanged: null,
                  secondary: Icon(Icons.medication_rounded),
                  title: Text('برنامه و مصرف دارو'),
                  subtitle: Text('دسترسی پایه رابطه مراقبتی'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _canViewWomenCalendar,
                  onChanged: _loading ||
                          _saving ||
                          !_womenCalendarEnabled ||
                          !LifeMateFeatureFlags.womenCalendarPilotEnabled
                      ? null
                      : _setWomenCalendarAccess,
                  secondary: _saving
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.calendar_month_rounded),
                  title: const Text('تقویم بانوان'),
                  subtitle: Text(
                    !LifeMateFeatureFlags.womenCalendarPilotEnabled
                        ? 'در این Build فعال نیست'
                        : !_womenCalendarEnabled
                            ? 'ابتدا تقویم بانوان را برای خودتان فعال کنید'
                            : 'نمایش خلاصه چرخه؛ یادداشت خصوصی اشتراک‌گذاری نمی‌شود',
                  ),
                ),
                const Divider(height: 1),
                const SwitchListTile(
                  value: false,
                  onChanged: null,
                  secondary: Icon(Icons.folder_shared_outlined),
                  title: Text('مشاهده پرونده سلامت'),
                  subtitle: Text('در نسخه بعدی و پس از قرارداد حریم خصوصی'),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
''',
)

write(
    'wellmate/lib/screens/home/home_screen.dart',
    r'''import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/widgets/wellmate_app_header.dart';
import '../../core/widgets/wellmate_bottom_nav.dart';
import '../calendar/calendar_screen.dart';
import '../profile/profile_destination_screens.dart';
import '../profile/profile_screen.dart';
import '../treatments/care_plan_hub_screen.dart';
import '../treatments/treatments_screen.dart';
import '../women_calendar/women_calendar_screen.dart';
import 'home_screen_content.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 4;
  int _refreshToken = 0;
  bool _womenCalendarEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadWomenCalendarState();
    });
  }

  Future<void> _loadWomenCalendarState() async {
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
      if (mounted) setState(() => _womenCalendarEnabled = false);
      return;
    }
    try {
      final profile =
          await context.read<LifeMateApiClient>().getWomenCalendarProfile();
      if (mounted) {
        setState(() => _womenCalendarEnabled = profile['enabled'] == true);
      }
    } catch (error) {
      debugPrint('Women calendar navigation state failed: $error');
    }
  }

  void _treatmentCreated() {
    setState(() {
      _refreshToken++;
      _currentIndex = 4;
    });
  }

  Future<void> _onItemTapped(int index) async {
    if (index == 3 && !_womenCalendarEnabled) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const SubscriptionScreen()),
      );
      await _loadWomenCalendarState();
      if (!_womenCalendarEnabled) return;
    }
    if (mounted) setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      CalendarScreen(refreshToken: _refreshToken),
      TreatmentsScreen(refreshToken: _refreshToken),
      CarePlanHubScreen(onCreated: _treatmentCreated),
      WomenCalendarScreen(onProfileChanged: _loadWomenCalendarState),
      HomeScreenContent(
        key: ValueKey(_refreshToken),
        onOpenTreatments: () => _onItemTapped(1),
        onAddTreatment: () => _onItemTapped(2),
      ),
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            WellMateAppHeader(
              onProfileTap: () async {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ProfileScreen(),
                  ),
                );
                await _loadWomenCalendarState();
              },
            ),
            Expanded(
              child: IndexedStack(index: _currentIndex, children: pages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: WellMateBottomNav(
        currentIndex: _currentIndex,
        womenCalendarEnabled: _womenCalendarEnabled,
        onTap: _onItemTapped,
      ),
    );
  }
}
''',
)

write(
    'wellmate/lib/core/widgets/wellmate_bottom_nav.dart',
    r'''import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../localization/app_localizations.dart';
import '../../localization/locale_provider.dart';
import '../theme/app_style.dart';

class WellMateBottomNav extends StatelessWidget {
  const WellMateBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.womenCalendarEnabled = false,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool womenCalendarEnabled;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isPersian =
        Provider.of<LocaleProvider>(context).locale.languageCode == 'fa';
    final fontFamily = isPersian ? 'Vazir' : 'Poppins';

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(35),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            _buildNavItem(
              icon: Icons.calendar_month_rounded,
              label: loc['nav_calendar'],
              index: 0,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              icon: Icons.medication_rounded,
              label: loc['nav_medications'],
              index: 1,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              icon: Icons.add_circle_outline_rounded,
              label: loc['nav_add_treatment'],
              index: 2,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              icon: womenCalendarEnabled
                  ? Icons.water_drop_rounded
                  : Icons.lock_outline_rounded,
              label: isPersian ? 'تقویم بانوان' : 'Women',
              index: 3,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              icon: Icons.home_rounded,
              label: loc['nav_home'],
              index: 4,
              fontFamily: fontFamily,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    required String fontFamily,
  }) {
    final isSelected = currentIndex == index;
    final color = isSelected ? AppColors.primary : Colors.grey.shade400;

    return Expanded(
      child: Semantics(
        key: ValueKey<String>('wellmate-nav-$index'),
        button: true,
        selected: isSelected,
        label: label,
        child: Tooltip(
          message: label,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTap(index),
              customBorder: const StadiumBorder(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 24, color: color),
                      const SizedBox(height: 4),
                      ExcludeSemantics(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: fontFamily,
                            fontSize: 9,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
''',
)

replace_once(
    'wellmate/lib/screens/profile/profile_destination_screens.dart',
    "import '../../core/theme/app_style.dart';\n",
    "import '../../core/theme/app_style.dart';\nimport '../../core/utils/persian_date_utils.dart';\n",
)

old_subscription = r'''class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _WellMateDestinationScaffold(
      title: 'اشتراک LifeMate',
      subtitle: 'امکانات پایه و آینده محصول',
      icon: Icons.emoji_events_rounded,
      accent: Colors.amber,
      child: Column(
        children: [
          _SubscriptionPlanCard(
            title: 'نسخه پایه',
            description:
                'ثبت درمان، برنامه روزانه، اعلان محلی و اتصال امن یک مراقب',
            current: true,
          ),
          SizedBox(height: 14),
          _SubscriptionPlanCard(
            title: 'نسخه خانواده',
            description:
                'گزارش‌های پیشرفته، چند مراقب، پرونده سلامت و پشتیبانی ویژه',
            current: false,
          ),
          SizedBox(height: 16),
          _DevelopmentNotice(
            message:
                'پرداخت و اشتراک هنوز Backend و درگاه فعال ندارند. هیچ خریدی در این نسخه انجام نمی‌شود.',
          ),
        ],
      ),
    );
  }
}
'''
new_subscription = r'''class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic> _profile = const {};

  bool get _enabled => _profile['enabled'] == true;
  int get _version => _profile['version'] is int ? _profile['version'] as int : 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final profile =
          await context.read<LifeMateApiClient>().getWomenCalendarProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (error) {
      debugPrint('Subscription women calendar load failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _activate() async {
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('این قابلیت در Build فعلی فعال نیست.')),
      );
      return;
    }
    final selected = await showAppDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
      title: 'شروع آخرین دوره',
    );
    if (selected == null || !mounted) return;
    await _save(enabled: true, lastPeriodStart: selected);
  }

  Future<void> _deactivate() async {
    final currentStart = DateTime.tryParse(
      _profile['lastPeriodStart']?.toString() ?? '',
    );
    await _save(enabled: false, lastPeriodStart: currentStart);
  }

  Future<void> _save({
    required bool enabled,
    required DateTime? lastPeriodStart,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final profile =
          await context.read<LifeMateApiClient>().updateWomenCalendarProfile(
                version: _version,
                enabled: enabled,
                lastPeriodStart: lastPeriodStart,
                cycleLength: _profile['cycleLength'] is int
                    ? _profile['cycleLength'] as int
                    : 28,
                periodLength: _profile['periodLength'] is int
                    ? _profile['periodLength'] as int
                    : 5,
                remindersEnabled: _profile['remindersEnabled'] != false,
              );
      if (!mounted) return;
      setState(() => _profile = profile);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'تقویم بانوان برای نسخه داخلی فعال شد.'
                : 'تقویم بانوان غیرفعال شد.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _WellMateDestinationScaffold(
      title: 'اشتراک LifeMate',
      subtitle: 'امکانات پایه و قابلیت‌های اختیاری',
      icon: Icons.emoji_events_rounded,
      accent: Colors.amber,
      child: Column(
        children: [
          const _SubscriptionPlanCard(
            title: 'نسخه پایه',
            description:
                'ثبت درمان، برنامه روزانه، اعلان محلی و اتصال امن یک مراقب',
            current: true,
            statusLabel: 'فعال',
            buttonLabel: 'نسخه فعلی',
          ),
          const SizedBox(height: 14),
          _SubscriptionPlanCard(
            title: 'تقویم بانوان',
            description:
                'تقویم شمسی، خط زمانی چرخه، ثبت شروع و پایان دوره و اشتراک‌گذاری اختیاری با مراقب',
            current: _enabled,
            statusLabel: _loading
                ? 'در حال بررسی'
                : _enabled
                    ? 'فعال'
                    : 'غیرفعال',
            buttonLabel: _enabled ? 'غیرفعال‌سازی' : 'فعال‌سازی آزمایشی',
            onPressed: _loading || _saving
                ? null
                : (_enabled ? _deactivate : _activate),
            accent: const Color(0xFFD95B93),
          ),
          const SizedBox(height: 14),
          const _SubscriptionPlanCard(
            title: 'نسخه خانواده',
            description:
                'گزارش‌های پیشرفته، چند مراقب، پرونده سلامت و پشتیبانی ویژه',
            current: false,
            statusLabel: 'در دست توسعه',
            buttonLabel: 'خرید — در دست توسعه',
          ),
          const SizedBox(height: 16),
          const _DevelopmentNotice(
            message:
                'در این نسخه داخلی، فعال‌سازی تقویم بانوان آزمایشی است و هیچ پرداخت یا ارتباطی با درگاه بانکی انجام نمی‌شود.',
          ),
        ],
      ),
    );
  }
}
'''
replace_once(
    'wellmate/lib/screens/profile/profile_destination_screens.dart',
    old_subscription,
    new_subscription,
)

old_plan = r'''class _SubscriptionPlanCard extends StatelessWidget {
  const _SubscriptionPlanCard({
    required this.title,
    required this.description,
    required this.current,
  });

  final String title;
  final String description;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Chip(
                label: Text(current ? 'فعال' : 'در دست توسعه'),
                side: BorderSide.none,
                backgroundColor: current
                    ? AppColors.primary.withOpacity(0.12)
                    : Colors.amber.withOpacity(0.15),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              height: 1.7,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: null,
              child: Text(current ? 'نسخه فعلی' : 'خرید — در دست توسعه'),
            ),
          ),
        ],
      ),
    );
  }
}
'''
new_plan = r'''class _SubscriptionPlanCard extends StatelessWidget {
  const _SubscriptionPlanCard({
    required this.title,
    required this.description,
    required this.current,
    required this.statusLabel,
    required this.buttonLabel,
    this.onPressed,
    this.accent = AppColors.primary,
  });

  final String title;
  final String description;
  final bool current;
  final String statusLabel;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  title == 'تقویم بانوان'
                      ? Icons.water_drop_rounded
                      : Icons.workspace_premium_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Chip(
                label: Text(statusLabel),
                side: BorderSide.none,
                backgroundColor: current
                    ? accent.withOpacity(0.12)
                    : Colors.amber.withOpacity(0.15),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              height: 1.7,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onPressed,
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}
'''
replace_once(
    'wellmate/lib/screens/profile/profile_destination_screens.dart',
    old_plan,
    new_plan,
)

replace_once(
    'wellmate/lib/screens/profile/care_access_screen.dart',
    "import '../../core/theme/app_style.dart';\nimport 'care_pairing_qr_dialog.dart';\n",
    "import '../../core/theme/app_style.dart';\nimport '../../core/utils/string_extensions.dart';\nimport 'care_access_settings_screen.dart';\nimport 'care_pairing_qr_dialog.dart';\n",
)
replace_once(
    'wellmate/lib/screens/profile/care_access_screen.dart',
    '''  Future<void> _revokeRelationship(Map<String, dynamic> relationship) async {\n''',
    r'''  Future<void> _openAccessSettings(
    Map<String, dynamic> relationship,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CareAccessSettingsScreen(relationship: relationship),
      ),
    );
    await _refresh();
  }

  Future<void> _revokeRelationship(Map<String, dynamic> relationship) async {
''',
)
replace_once(
    'wellmate/lib/screens/profile/care_access_screen.dart',
    '''  Widget build(BuildContext context) {\n    final active = _relationships\n''',
    '''  Widget build(BuildContext context) {\n    final isPersian = Localizations.localeOf(context).languageCode == 'fa';\n    final active = _relationships\n''',
)
replace_once(
    'wellmate/lib/screens/profile/care_access_screen.dart',
    "                'مراقبان فعال (${active.length})',\n",
    "                'مراقبان فعال (${active.length.toString().toPersianDigit(isPersian)})',\n",
)
replace_once(
    'wellmate/lib/screens/profile/care_access_screen.dart',
    "                'دعوت‌های در انتظار (${pending.length})',\n",
    "                'دعوت‌های در انتظار (${pending.length.toString().toPersianDigit(isPersian)})',\n",
)
replace_once(
    'wellmate/lib/screens/profile/care_access_screen.dart',
    r'''                      title: Text(
                        relationship['caregiverDisplayName']?.toString() ??
                            'مراقب',
                      ),
                      subtitle: const Text('دسترسی فعال به وضعیت مصرف دارو'),
                      trailing: IconButton(
                        tooltip: 'قطع دسترسی',
                        onPressed: () => _revokeRelationship(relationship),
                        icon: const Icon(Icons.link_off_rounded),
                      ),
''',
    r'''                      title: Text(
                        (relationship['caregiverDisplayName']?.toString() ??
                                'مراقب')
                            .toPersianDigit(isPersian),
                      ),
                      subtitle: Text(
                        relationship['canViewWomenCalendar'] == true
                            ? 'دارو و تقویم بانوان'
                            : 'دسترسی فعال به وضعیت مصرف دارو',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'تنظیمات دسترسی',
                            onPressed: () => _openAccessSettings(relationship),
                            icon: const Icon(Icons.tune_rounded),
                          ),
                          IconButton(
                            tooltip: 'قطع دسترسی',
                            onPressed: () => _revokeRelationship(relationship),
                            icon: const Icon(Icons.link_off_rounded),
                          ),
                        ],
                      ),
''',
)
replace_once(
    'wellmate/lib/screens/profile/care_access_screen.dart',
    "              Text('انقضا: $expiresAt'),\n",
    "              Text(\n                'انقضا: ${expiresAt.toPersianDigit(Localizations.localeOf(context).languageCode == 'fa')}',\n              ),\n",
)

write(
    'wellmate/test/women_calendar_navigation_test.dart',
    r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/core/widgets/wellmate_bottom_nav.dart';
import 'package:wellmate/localization/locale_provider.dart';
import 'package:wellmate/main.dart';
import 'package:wellmate/providers/settings_provider.dart';

void main() {
  testWidgets('women calendar navigation is present and Persian labelled',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: WellMateApp(
          home: Scaffold(
            bottomNavigationBar: WellMateBottomNav(
              currentIndex: 4,
              womenCalendarEnabled: true,
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('wellmate-nav-3')), findsOneWidget);
    expect(find.bySemanticsLabel('تقویم بانوان'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
''',
)
replace_once(
    'wellmate/test/bottom_navigation_accessibility_test.dart',
    'currentIndex: 3,',
    'currentIndex: 4,',
)
replace_once(
    'wellmate/test/bottom_navigation_accessibility_test.dart',
    'for (var index = 0; index < 4; index += 1)',
    'for (var index = 0; index < 5; index += 1)',
)

print('WellMate women calendar, subscription and caregiver access UI patch applied.')
