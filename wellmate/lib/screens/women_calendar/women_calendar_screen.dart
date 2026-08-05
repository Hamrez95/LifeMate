import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../profile/profile_destination_screens.dart';
import 'women_calendar_month_card.dart';

const _periodPhaseColor = Color(0xFFF45B78);
const _follicularPhaseColor = Color(0xFF9B7BD4);
const _fertilePhaseColor = Color(0xFF39BDB3);
const _ovulationPhaseColor = Color(0xFF2A91D8);
const _lutealPhaseColor = Color(0xFFF3B24C);
const _pmsPhaseColor = Color(0xFFE48166);

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

  Future<void> _createEpisode() async {
    if (_saving) return;
    final draft = await _showEpisodeEditor();
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      await context.read<LifeMateApiClient>().createWomenCalendarEpisode(
        startedOn: draft.startedOn,
        endedOn: draft.endedOn,
        privateNotes: draft.privateNotes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('دوره و یادداشت خصوصی ثبت شد.')),
      );
      await _load();
      await widget.onProfileChanged?.call();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'women_calendar_episode_overlap'
                ? 'این بازه با یک ثبت قبلی هم‌پوشانی دارد.'
                : 'ثبت دوره انجام نشد.',
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
    final startedOn = DateTime.parse(episode['startedOn'].toString());
    setState(() => _saving = true);
    try {
      await context.read<LifeMateApiClient>().updateWomenCalendarEpisode(
        episodeId: episode['id'].toString(),
        version: episode['version'] is int ? episode['version'] as int : 1,
        startedOn: startedOn,
        endedOn: DateTime.now(),
        privateNotes: episode['privateNotes']?.toString(),
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

  Future<void> _editEpisode(Map<String, dynamic> episode) async {
    if (_saving) return;
    final draft = await _showEpisodeEditor(episode: episode);
    if (draft == null) return;
    if (draft.deleteRequested) {
      await _deleteEpisode(episode);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<LifeMateApiClient>().updateWomenCalendarEpisode(
        episodeId: episode['id'].toString(),
        version: episode['version'] is int ? episode['version'] as int : 1,
        startedOn: draft.startedOn,
        endedOn: draft.endedOn,
        privateNotes: draft.privateNotes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ثبت دوره اصلاح شد.')));
      await _load();
      await widget.onProfileChanged?.call();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'stale_women_calendar_episode'
                ? 'این ثبت تغییر کرده است؛ اطلاعات تازه‌سازی شد.'
                : error.code == 'women_calendar_episode_overlap'
                ? 'این بازه با یک ثبت قبلی هم‌پوشانی دارد.'
                : 'اصلاح ثبت انجام نشد.',
          ),
        ),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteEpisode(Map<String, dynamic> episode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف ثبت اشتباه'),
        content: const Text(
          'این ثبت و یادداشت خصوصی آن حذف می‌شود. این کار قابل بازگشت نیست.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await context.read<LifeMateApiClient>().deleteWomenCalendarEpisode(
        episodeId: episode['id'].toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ثبت اشتباه حذف شد.')));
      await _load();
      await widget.onProfileChanged?.call();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_EpisodeEditorResult?> _showEpisodeEditor({
    Map<String, dynamic>? episode,
  }) async {
    var startedOn = episode == null
        ? DateTime.now()
        : DateTime.parse(episode['startedOn'].toString());
    DateTime? endedOn = episode?['endedOn'] == null
        ? null
        : DateTime.parse(episode!['endedOn'].toString());
    final notesController = TextEditingController(
      text: episode?['privateNotes']?.toString() ?? '',
    );
    String? validationError;
    final result = await showDialog<_EpisodeEditorResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          title: Text(episode == null ? 'ثبت دوره' : 'اصلاح ثبت دوره'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EpisodeDateTile(
                  title: 'تاریخ شروع',
                  value: formatAppDate(context, startedOn),
                  icon: Icons.play_circle_outline_rounded,
                  onTap: () async {
                    final value = await showAppDatePicker(
                      context: context,
                      initialDate: startedOn,
                      firstDate: DateTime(2015),
                      lastDate: DateTime.now(),
                      title: 'تاریخ شروع دوره',
                    );
                    if (value != null) {
                      setDialogState(() {
                        startedOn = value;
                        validationError = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                _EpisodeDateTile(
                  title: 'تاریخ پایان',
                  value: endedOn == null
                      ? 'هنوز ادامه دارد'
                      : formatAppDate(context, endedOn!),
                  icon: Icons.stop_circle_outlined,
                  onClear: endedOn == null
                      ? null
                      : () => setDialogState(() => endedOn = null),
                  onTap: () async {
                    final value = await showAppDatePicker(
                      context: context,
                      initialDate: endedOn ?? startedOn,
                      firstDate: startedOn,
                      lastDate: DateTime.now(),
                      title: 'تاریخ پایان دوره',
                    );
                    if (value != null) {
                      setDialogState(() {
                        endedOn = value;
                        validationError = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notesController,
                  maxLength: 500,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'یادداشت خصوصی',
                    hintText: 'این متن فقط برای خود شما نمایش داده می‌شود.',
                    filled: true,
                    fillColor: const Color(0xFFF7F9FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                  ),
                ),
                if (validationError != null)
                  Text(
                    validationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (episode != null)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  _EpisodeEditorResult(
                    startedOn: startedOn,
                    endedOn: endedOn,
                    privateNotes: notesController.text.trim(),
                    deleteRequested: true,
                  ),
                ),
                child: const Text('حذف ثبت'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                if (endedOn != null && endedOn!.isBefore(startedOn)) {
                  setDialogState(() {
                    validationError = 'تاریخ پایان نمی‌تواند قبل از شروع باشد.';
                  });
                  return;
                }
                Navigator.of(dialogContext).pop(
                  _EpisodeEditorResult(
                    startedOn: startedOn,
                    endedOn: endedOn,
                    privateNotes: notesController.text.trim(),
                  ),
                );
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
    notesController.dispose();
    return result;
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
          WomenCalendarMonthCard(episodes: _episodes, estimate: estimate),
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
            onStart: _createEpisode,
            onFinish: _finishPeriodToday,
            onEdit: _editEpisode,
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.amber.shade100),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: Color(0xFF9A6A00)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تاریخ‌ها و فازها تخمینی هستند و جایگزین نظر پزشک نیستند. این زمان‌بندی برای تشخیص، پیشگیری از بارداری یا اثبات تخمک‌گذاری استفاده نمی‌شود. در صورت خون‌ریزی غیرعادی، درد شدید یا نگرانی پزشکی با پزشک تماس بگیرید.',
                    style: TextStyle(height: 1.7),
                  ),
                ),
              ],
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
    final visual = _phaseVisual(value?.detailedPhase);
    return Container(
      key: const ValueKey('women-calendar-summary-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            visual.color.withValues(alpha: 0.17),
            const Color(0xFFF5F2FF),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: visual.color.withValues(alpha: 0.18),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(visual.icon, color: visual.color, size: 22),
                const SizedBox(height: 3),
                Text(
                  value == null ? '—' : localizeDigits(context, value.cycleDay),
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    color: visual.color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'امروز در تقویم بانوان',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 7),
                Text(
                  visual.label,
                  style: TextStyle(
                    color: visual.color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    'شروع دوره بعدی حدود ${localizeDigits(context, value.daysUntilNextPeriod)} روز دیگر',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
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

class _TimelineCard extends StatefulWidget {
  const _TimelineCard({required this.estimate});

  final WomenCalendarEstimate? estimate;

  @override
  State<_TimelineCard> createState() => _TimelineCardState();
}

class _TimelineCardState extends State<_TimelineCard> {
  int _selectedIndex = 0;

  @override
  void didUpdateWidget(covariant _TimelineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.estimate != widget.estimate) _selectedIndex = 0;
  }

  @override
  Widget build(BuildContext context) {
    final estimate = widget.estimate;
    final today = DateTime.now();
    final selectedDate = DateTime(
      today.year,
      today.month,
      today.day,
    ).add(Duration(days: _selectedIndex));
    final selectedPhase = estimate?.phaseForDate(selectedDate);
    final selectedVisual = _phaseVisual(selectedPhase);

    return _SoftSection(
      key: const ValueKey('women-calendar-14-day-timeline'),
      title: 'خط زمانی ۱۴ روز آینده',
      subtitle: 'برای دیدن توضیح هر فاز، روز موردنظر را لمس کنید.',
      child: Column(
        children: [
          SizedBox(
            height: 132,
            child: ListView.separated(
              reverse: false,
              scrollDirection: Axis.horizontal,
              itemCount: 14,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final date = DateTime(
                  today.year,
                  today.month,
                  today.day,
                ).add(Duration(days: index));
                final phase = estimate?.phaseForDate(date);
                final visual = _phaseVisual(phase);
                final selected = index == _selectedIndex;
                final cycleDay = estimate?.cycleDayForDate(date);
                return Semantics(
                  button: true,
                  selected: selected,
                  label:
                      '${index == 0 ? 'امروز' : 'روز $index'}، ${visual.label}',
                  child: InkWell(
                    onTap: () => setState(() => _selectedIndex = index),
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 76,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? visual.color.withValues(alpha: 0.16)
                            : visual.color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? visual.color : Colors.transparent,
                          width: selected ? 1.7 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            index == 0
                                ? 'امروز'
                                : localizeDigits(context, index),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: index == 0 ? 10.5 : 15,
                              fontWeight: FontWeight.w900,
                              color: selected
                                  ? visual.foreground
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.82),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              visual.icon,
                              size: 19,
                              color: visual.color,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _shortDate(context, date),
                            style: const TextStyle(fontSize: 9.5),
                          ),
                          if (cycleDay != null)
                            Text(
                              'روز ${localizeDigits(context, cycleDay)}',
                              style: TextStyle(
                                fontSize: 8.5,
                                color: visual.foreground,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selectedVisual.color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selectedVisual.color.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    selectedVisual.icon,
                    color: selectedVisual.color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedVisual.label,
                        style: TextStyle(
                          color: selectedVisual.foreground,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _phaseDescription(selectedPhase),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.5,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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
    return Container(
      key: const ValueKey('women-calendar-settings-card'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFF0F2F5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x121A334A),
            blurRadius: 22,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFFFFEDF5), Color(0xFFF1EDFF)],
              ),
            ),
            child: const Row(
              children: [
                _SettingsHeaderIcon(),
                SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تنظیمات چرخه',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'اطلاعات پایه برای تخمین چرخه و یادآوری خصوصی',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Material(
                  color: const Color(0xFFF8FAFB),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    key: const ValueKey('women-calendar-last-period-picker'),
                    onTap: onPickDate,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE9F1),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Icon(
                              Icons.edit_calendar_rounded,
                              color: _periodPhaseColor,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'شروع آخرین دوره',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  lastPeriodStart == null
                                      ? 'برای انتخاب تاریخ لمس کنید'
                                      : formatAppDate(
                                          context,
                                          lastPeriodStart!,
                                          includeWeekday: true,
                                        ),
                                  style: TextStyle(
                                    color: lastPeriodStart == null
                                        ? AppColors.textSecondary
                                        : const Color(0xFFB33B61),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_left_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 340;
                    final fields = [
                      _CycleMetricSelector(
                        label: 'طول معمول چرخه',
                        helper: 'از شروع یک دوره تا دوره بعدی',
                        icon: Icons.sync_rounded,
                        color: _fertilePhaseColor,
                        value: cycleLength,
                        values: List<int>.generate(25, (index) => index + 21),
                        onChanged: onCycleChanged,
                      ),
                      _CycleMetricSelector(
                        label: 'طول خون‌ریزی',
                        helper: 'تعداد روزهای معمول دوره',
                        icon: Icons.water_drop_outlined,
                        color: _periodPhaseColor,
                        value: periodLength,
                        values: List<int>.generate(10, (index) => index + 1),
                        onChanged: onPeriodChanged,
                      ),
                    ];
                    if (compact) {
                      return Column(
                        children: [
                          fields.first,
                          const SizedBox(height: 10),
                          fields.last,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: fields.first),
                        const SizedBox(width: 10),
                        Expanded(child: fields.last),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2FAF7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFDDF3EB)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 43,
                        height: 43,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.notifications_active_outlined,
                          color: Color(0xFF148463),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'یادآوری نزدیک‌شدن دوره',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'اعلان بدون جزئیات حساس روی صفحه قفل نمایش داده می‌شود.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10.5,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: remindersEnabled,
                        onChanged: onReminderChanged,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed:
                        saving || lastPeriodStart == null ? null : onSave,
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      lastPeriodStart == null
                          ? 'ابتدا تاریخ شروع را انتخاب کنید'
                          : 'ذخیره تنظیمات چرخه',
                    ),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsHeaderIcon extends StatelessWidget {
  const _SettingsHeaderIcon();

  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.tune_rounded, color: Color(0xFF8A5BB2)),
      );
}

class _CycleMetricSelector extends StatelessWidget {
  const _CycleMetricSelector({
    required this.label,
    required this.helper,
    required this.icon,
    required this.color,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String helper;
  final IconData icon;
  final Color color;
  final int value;
  final List<int> values;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            helper,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 7),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              borderRadius: BorderRadius.circular(18),
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: color),
              items: [
                for (final item in values)
                  DropdownMenuItem<int>(
                    value: item,
                    child: Text(
                      '${localizeDigits(context, item)} روز',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
              onChanged: (next) {
                if (next != null) onChanged(next);
              },
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
    required this.onEdit,
  });

  final Map<String, dynamic>? openEpisode;
  final List<Map<String, dynamic>> episodes;
  final bool saving;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final ValueChanged<Map<String, dynamic>> onEdit;

  @override
  Widget build(BuildContext context) {
    return _SoftSection(
      title: 'ثبت واقعی دوره',
      subtitle: 'ثبت واقعی شما همیشه بر تخمین‌های تقویم اولویت دارد.',
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
                openEpisode == null ? 'ثبت شروع و یادداشت' : 'پایان دوره امروز',
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'آخرین ثبت‌ها',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (episodes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('هنوز دوره‌ای ثبت نشده است.'),
            )
          else
            ...episodes.take(4).map((episode) {
              final notes = episode['privateNotes']?.toString().trim() ?? '';
              final endedOn = episode['endedOn'];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.water_drop_outlined),
                title: Text(
                  formatAppDate(
                    context,
                    DateTime.parse(episode['startedOn'].toString()),
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      endedOn == null
                          ? 'در حال ثبت'
                          : 'تا ${formatAppDate(context, DateTime.parse(endedOn.toString()))}',
                    ),
                    if (notes.isNotEmpty)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lock_outline_rounded, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              notes,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                trailing: IconButton(
                  tooltip: 'اصلاح ثبت',
                  onPressed: saving ? null : () => onEdit(episode),
                  icon: const Icon(Icons.edit_rounded),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _EpisodeDateTile extends StatelessWidget {
  const _EpisodeDateTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.onTap,
    this.onClear,
  });

  final String title;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFF7F9FA),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        value,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onClear != null)
                  IconButton(
                    tooltip: 'پاک‌کردن تاریخ',
                    onPressed: onClear,
                    icon: const Icon(Icons.clear_rounded),
                  )
                else
                  const Icon(Icons.chevron_left_rounded),
              ],
            ),
          ),
        ),
      );
}

class _EpisodeEditorResult {
  const _EpisodeEditorResult({
    required this.startedOn,
    required this.endedOn,
    required this.privateNotes,
    this.deleteRequested = false,
  });

  final DateTime startedOn;
  final DateTime? endedOn;
  final String privateNotes;
  final bool deleteRequested;
}

class _SoftSection extends StatelessWidget {
  const _SoftSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
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
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
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

class _PhaseVisual {
  const _PhaseVisual({
    required this.label,
    required this.color,
    required this.foreground,
    required this.icon,
  });

  final String label;
  final Color color;
  final Color foreground;
  final IconData icon;
}

_PhaseVisual _phaseVisual(WomenCyclePhase? phase) => switch (phase) {
      WomenCyclePhase.period => const _PhaseVisual(
          label: 'قاعدگی تخمینی',
          color: _periodPhaseColor,
          foreground: Color(0xFFB52E55),
          icon: Icons.water_drop_rounded,
        ),
      WomenCyclePhase.follicular => const _PhaseVisual(
          label: 'فاز فولیکولار',
          color: _follicularPhaseColor,
          foreground: Color(0xFF7352A5),
          icon: Icons.auto_awesome_rounded,
        ),
      WomenCyclePhase.fertile => const _PhaseVisual(
          label: 'پنجره باروری تخمینی',
          color: _fertilePhaseColor,
          foreground: Color(0xFF1C827B),
          icon: Icons.spa_rounded,
        ),
      WomenCyclePhase.ovulation => const _PhaseVisual(
          label: 'روز تخمک‌گذاری تخمینی',
          color: _ovulationPhaseColor,
          foreground: Color(0xFF17699E),
          icon: Icons.blur_circular_rounded,
        ),
      WomenCyclePhase.luteal => const _PhaseVisual(
          label: 'فاز لوتئال',
          color: _lutealPhaseColor,
          foreground: Color(0xFF9B6D19),
          icon: Icons.wb_sunny_outlined,
        ),
      WomenCyclePhase.pms => const _PhaseVisual(
          label: 'PMS تخمینی',
          color: _pmsPhaseColor,
          foreground: Color(0xFFA74D39),
          icon: Icons.favorite_border_rounded,
        ),
      null => const _PhaseVisual(
          label: 'اطلاعات ناکافی',
          color: Color(0xFF9AA5B0),
          foreground: Color(0xFF5F6974),
          icon: Icons.help_outline_rounded,
        ),
    };

String _phaseDescription(WomenCyclePhase? phase) => switch (phase) {
      WomenCyclePhase.period =>
        'بازه تخمینی قاعدگی است. تاریخ ثبت‌شده واقعی شما بر این تخمین اولویت دارد.',
      WomenCyclePhase.follicular =>
        'فاز فولیکولار پس از قاعدگی و پیش از پنجره باروری تخمین زده می‌شود.',
      WomenCyclePhase.fertile =>
        'پنجره باروری فقط با طول چرخه تخمین زده شده و روش پیشگیری از بارداری نیست.',
      WomenCyclePhase.ovulation =>
        'روز تخمک‌گذاری تخمینی است و بدون داده یا آزمایش پزشکی قطعی نیست.',
      WomenCyclePhase.luteal =>
        'فاز لوتئال پس از پنجره باروری تا روزهای نزدیک دوره بعدی تخمین زده می‌شود.',
      WomenCyclePhase.pms =>
        'روزهای نزدیک دوره بعدی است؛ علائم PMS برای هر فرد متفاوت است.',
      null => 'برای نمایش فازهای چرخه، اطلاعات پایه را در تنظیمات ثبت کنید.',
    };

String _shortDate(BuildContext context, DateTime date) {
  final formatted = formatAppDate(context, date);
  final parts = formatted.split('/');
  if (parts.length == 3) return '${parts[1]}/${parts[2]}';
  return formatted;
}
