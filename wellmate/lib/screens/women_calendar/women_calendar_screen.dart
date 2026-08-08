import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../profile/profile_destination_screens.dart';
import 'women_calendar_experience_widgets.dart';
import 'women_calendar_management_widgets.dart';
import 'women_calendar_month_card.dart';

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
  Map<String, dynamic> _currentUser = const {};
  List<Map<String, dynamic>> _relationships = const [];
  List<Map<String, dynamic>> _treatmentPlans = const [];
  List<Map<String, dynamic>> _episodes = const [];

  DateTime? _lastPeriodStart;
  int _cycleLength = 28;
  int _periodLength = 5;
  bool _remindersEnabled = true;

  bool get _enabled => _profile['enabled'] == true;
  int get _version =>
      _profile['version'] is int ? _profile['version'] as int : 0;

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

  String get _ownerName {
    final profile =
        _currentUser['profile'] as Map<String, dynamic>? ?? const {};
    return profile['displayName']?.toString().trim() ?? '';
  }

  String? get _companionName {
    final user = _currentUser['user'] as Map<String, dynamic>? ?? const {};
    final userId = user['id']?.toString();
    for (final relationship in _relationships) {
      if (relationship['status']?.toString().toLowerCase() == 'active' &&
          relationship['patientUserId']?.toString() == userId) {
        final value = relationship['caregiverDisplayName']?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  int get _activeTreatmentCount => _treatmentPlans
      .where((plan) => plan['status']?.toString().toLowerCase() == 'active')
      .length;

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
      final now = DateTime.now();
      final dashboard = await api.getWomenCalendarDashboard(
        fromDate: now.subtract(const Duration(days: 89)),
        toDate: now,
      );
      if (!mounted) return;
      final profile = dashboard['profile'] as Map<String, dynamic>? ?? const {};
      setState(() {
        _profile = profile;
        _episodes = (dashboard['episodes'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        _currentUser =
            dashboard['currentUser'] as Map<String, dynamic>? ?? const {};
        _relationships =
            (dashboard['relationships'] as List<dynamic>? ?? const [])
                .cast<Map<String, dynamic>>();
        _treatmentPlans =
            (dashboard['treatmentPlans'] as List<dynamic>? ?? const [])
                .cast<Map<String, dynamic>>();
        _applyProfile(profile);
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == 'women_calendar_feature_disabled'
            ? 'تقویم بانوان در این نسخه داخلی فعال نشده است.'
            : 'اطلاعات تقویم بانوان دریافت نشد.';
      });
    } catch (error) {
      debugPrint('Women calendar experience load failed: $error');
      if (mounted) setState(() => _error = 'اطلاعات تقویم بانوان دریافت نشد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyProfile(Map<String, dynamic> profile) {
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
      final profile = await context
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
      setState(() {
        _profile = profile;
        _applyProfile(profile);
      });
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: 'تنظیمات ذخیره شد',
        message: 'تنظیمات چرخه به‌روزرسانی شد.',
      );
      await widget.onProfileChanged?.call();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: 'ذخیره انجام نشد',
        message: error.code == 'stale_women_calendar_profile'
            ? 'اطلاعات تغییر کرده بود؛ صفحه تازه‌سازی شد.'
            : 'تنظیمات ذخیره نشد.',
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
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: 'دوره ثبت شد',
        message: 'بازه دوره و یادداشت خصوصی ذخیره شد.',
      );
      await _load();
      await widget.onProfileChanged?.call();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: 'ثبت دوره انجام نشد',
        message: error.code == 'women_calendar_episode_overlap'
            ? 'این بازه با یک ثبت قبلی هم‌پوشانی دارد.'
            : 'تغییرات ثبت دوره ذخیره نشد.',
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
      await context.read<LifeMateApiClient>().updateWomenCalendarEpisode(
        episodeId: episode['id'].toString(),
        version: episode['version'] is int ? episode['version'] as int : 1,
        startedOn: DateTime.parse(episode['startedOn'].toString()),
        endedOn: DateTime.now(),
        privateNotes: episode['privateNotes']?.toString(),
      );
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: 'پایان دوره ثبت شد',
        message: 'پایان دوره برای امروز ذخیره شد.',
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
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: 'ثبت دوره اصلاح شد',
        message: 'تغییرات تاریخچه دوره ذخیره شد.',
      );
      await _load();
      await widget.onProfileChanged?.call();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: 'ثبت دوره انجام نشد',
        message: error.code == 'women_calendar_episode_overlap'
            ? 'این بازه با یک ثبت قبلی هم‌پوشانی دارد.'
            : 'تغییرات ثبت دوره ذخیره نشد.',
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('حذف ثبت دوره؟'),
        content: const Text(
          'این ثبت و یادداشت خصوصی آن حذف می‌شود و قابل بازگشت نیست.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
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
      await _load();
      await widget.onProfileChanged?.call();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_EpisodeDraft?> _showEpisodeEditor({
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
    final result = await showModalBottomSheet<_EpisodeDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFFFFFBFD),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    episode == null ? 'ثبت دوره جدید' : 'ویرایش دوره',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: womenInk,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _EpisodeDateField(
                    label: 'تاریخ شروع',
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
                        setSheetState(() {
                          startedOn = value;
                          if (endedOn != null && endedOn!.isBefore(value)) {
                            endedOn = null;
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _EpisodeDateField(
                    label: 'تاریخ پایان',
                    value: endedOn == null
                        ? 'هنوز ادامه دارد'
                        : formatAppDate(context, endedOn!),
                    icon: Icons.stop_circle_outlined,
                    onTap: () async {
                      final value = await showAppDatePicker(
                        context: context,
                        initialDate: endedOn ?? startedOn,
                        firstDate: startedOn,
                        lastDate: DateTime.now(),
                        title: 'تاریخ پایان دوره',
                      );
                      if (value != null) setSheetState(() => endedOn = value);
                    },
                    onClear: endedOn == null
                        ? null
                        : () => setSheetState(() => endedOn = null),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    maxLength: 500,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'یادداشت خصوصی',
                      hintText: 'این متن فقط برای خودت نمایش داده می‌شود.',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF8F3F8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (episode != null)
                        TextButton.icon(
                          onPressed: () => Navigator.pop(
                            sheetContext,
                            _EpisodeDraft(
                              startedOn: startedOn,
                              endedOn: endedOn,
                              privateNotes: notesController.text.trim(),
                              deleteRequested: true,
                            ),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('حذف'),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('انصراف'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(
                          sheetContext,
                          _EpisodeDraft(
                            startedOn: startedOn,
                            endedOn: endedOn,
                            privateNotes: notesController.text.trim(),
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: womenRose,
                        ),
                        child: const Text('ذخیره'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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
      return _FeatureGate(
        icon: Icons.lock_outline_rounded,
        title: 'تقویم بانوان در این Build فعال نیست',
        description:
            'این قابلیت فقط در نسخه داخلی دارای Feature Flag نمایش داده می‌شود.',
        actionLabel: 'مشاهده اشتراک‌ها',
        onAction: _openSubscription,
      );
    }
    if (_error != null) {
      return _FeatureGate(
        icon: Icons.cloud_off_rounded,
        title: 'اطلاعات چرخه دریافت نشد',
        description: _error!,
        actionLabel: 'تلاش دوباره',
        onAction: _load,
      );
    }
    if (!_enabled) {
      return _FeatureGate(
        icon: Icons.local_florist_outlined,
        title: 'فضای شخصی چرخه آماده است',
        description:
            'با فعال‌سازی تقویم بانوان، تنظیمات چرخه و مدیریت ثبت‌های دوره در دسترس قرار می‌گیرد.',
        actionLabel: 'فعال‌سازی',
        onAction: _openSubscription,
      );
    }

    final estimate = _estimate;
    return WomenCycleBackground(
      child: RefreshIndicator(
        onRefresh: _load,
        color: womenRose,
        child: ListView(
          key: const ValueKey('women-calendar-settings-only'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
          children: [
            const WomenSoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تنظیمات و مدیریت ثبت‌ها',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: womenInk,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'اینجا فقط تنظیمات ماندگار چرخه، یادآوری‌ها و تاریخچه دوره‌ها مدیریت می‌شود. حال روزانه از خود تقویم ثبت می‌شود.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.65,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            WomenCycleSettingsCard(
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
            const SizedBox(height: 14),
            WomenRemindersCard(
              estimate: estimate,
              remindersEnabled: _remindersEnabled,
              activeTreatmentCount: _activeTreatmentCount,
            ),
            const SizedBox(height: 14),
            WomenPeriodHistoryCard(
              episodes: _episodes,
              hasOpenEpisode: _openEpisode != null,
              saving: _saving,
              onStart: _createEpisode,
              onFinish: _finishPeriodToday,
              onEdit: _editEpisode,
            ),
            const SizedBox(height: 14),
            const WomenPrivacyNotice(),
          ],
        ),
      ),
    );
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class _EpisodeDraft {
  const _EpisodeDraft({
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

class _EpisodeDateField extends StatelessWidget {
  const _EpisodeDateField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF8F3F8),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Icon(icon, color: womenRose),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              )
            else
              const Icon(Icons.chevron_left_rounded),
          ],
        ),
      ),
    ),
  );
}

class _FeatureGate extends StatelessWidget {
  const _FeatureGate({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => WomenCycleBackground(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 30),
      children: [
        WomenSoftCard(
          child: Column(
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: const BoxDecoration(
                  color: womenBlush,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: womenRose, size: 34),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: womenInk,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: womenRose),
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
