import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../profile/profile_destination_screens.dart';

class WomenCalendarScreen extends StatefulWidget {
  const WomenCalendarScreen({super.key, this.onProfileChanged});

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
  int get _version =>
      _profile['version'] is int ? _profile['version'] as int : 0;

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
      debugPrint('Women calendar load failed.');
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
      _profile = await context
          .read<LifeMateApiClient>()
          .updateWomenCalendarProfile(
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
              'تاریخ‌ها تخمینی هستند و جایگزین نظر پزشک نیستند. این زمان‌بندی فقط بر اساس اطلاعات ثبت‌شده شما محاسبه می‌شود و برای تشخیص، پیشگیری از بارداری یا تعیین باروری استفاده نمی‌شود. در صورت خون‌ریزی غیرعادی، درد شدید یا نگرانی پزشکی با پزشک تماس بگیرید.',
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
            final date = DateTime(
              today.year,
              today.month,
              today.day,
            ).add(Duration(days: index));
            final estimatedPeriod =
                estimate?.isEstimatedPeriodDay(date) == true;
            return Container(
              width: 62,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: estimatedPeriod
                    ? const Color(0xFFFFDDEB)
                    : const Color(0xFFF4F7FA),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: index == 0 ? AppColors.primary : Colors.transparent,
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
                  decoration: const InputDecoration(
                    labelText: 'طول معمول چرخه',
                  ),
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
                  decoration: const InputDecoration(
                    labelText: 'طول معمول خون‌ریزی',
                  ),
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
            subtitle: const Text(
              'متن اعلان بدون جزئیات حساس نمایش داده می‌شود.',
            ),
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
              onPressed: saving
                  ? null
                  : (openEpisode == null ? onStart : onFinish),
              icon: Icon(
                openEpisode == null
                    ? Icons.play_circle_fill_rounded
                    : Icons.stop_circle_rounded,
              ),
              label: Text(
                openEpisode == null ? 'شروع دوره امروز' : 'پایان دوره امروز',
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
            ...episodes
                .take(4)
                .map(
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
