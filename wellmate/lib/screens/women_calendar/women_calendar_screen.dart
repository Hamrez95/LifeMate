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
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تقویم بانوان در این نسخه داخلی فعال نشده است.',
                  en: "Ladies calendar is not enabled in this internal version.",
                ),
                en: "Ladies calendar is not enabled in this internal version.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'اطلاعات تقویم بانوان دریافت نشد.',
                  en: "Women's calendar information was not received.",
                ),
                en: "Women's calendar information was not received.",
              );
      });
    } catch (error) {
      debugPrint('Women calendar experience load failed: $error');
      if (mounted)
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'اطلاعات تقویم بانوان دریافت نشد.',
              en: "Women's calendar information was not received.",
            ),
            en: "Women's calendar information was not received.",
          ),
        );
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
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'تاریخ شروع آخرین دوره',
          en: "Last term start date",
        ),
        en: "Last term start date",
      ),
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
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تنظیمات ذخیره شد',
            en: "Settings saved",
          ),
          en: "Settings saved",
        ),
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تنظیمات چرخه به‌روزرسانی شد.',
            en: "Updated cycle settings.",
          ),
          en: "Updated cycle settings.",
        ),
      );
      await widget.onProfileChanged?.call();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'ذخیره انجام نشد',
            en: "Failed to save",
          ),
          en: "Failed to save",
        ),
        message: error.code == 'stale_women_calendar_profile'
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'اطلاعات تغییر کرده بود؛ صفحه تازه‌سازی شد.',
                  en: "The information had changed; The page has been updated.",
                ),
                en: "The information had changed; The page has been updated.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تنظیمات ذخیره نشد.',
                  en: "Settings could not be saved.",
                ),
                en: "Settings could not be saved.",
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
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'دوره ثبت شد',
            en: "The course was registered",
          ),
          en: "The course was registered",
        ),
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'بازه دوره و یادداشت خصوصی ذخیره شد.',
            en: "Course interval and private note saved.",
          ),
          en: "Course interval and private note saved.",
        ),
      );
      await _load();
      await widget.onProfileChanged?.call();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'ثبت دوره انجام نشد',
            en: "Course registration failed",
          ),
          en: "Course registration failed",
        ),
        message: error.code == 'women_calendar_episode_overlap'
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'این بازه با یک ثبت قبلی هم‌پوشانی دارد.',
                  en: "This interval overlaps with a previous record.",
                ),
                en: "This interval overlaps with a previous record.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تغییرات ثبت دوره ذخیره نشد.',
                  en: "Course registration changes were not saved.",
                ),
                en: "Course registration changes were not saved.",
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
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'پایان دوره ثبت شد',
            en: "The end of the course was recorded",
          ),
          en: "The end of the course was recorded",
        ),
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'پایان دوره برای امروز ذخیره شد.',
            en: "End of course saved for today.",
          ),
          en: "End of course saved for today.",
        ),
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
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'ثبت دوره اصلاح شد',
            en: "Course registration was modified",
          ),
          en: "Course registration was modified",
        ),
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تغییرات تاریخچه دوره ذخیره شد.',
            en: "Course history changes saved.",
          ),
          en: "Course history changes saved.",
        ),
      );
      await _load();
      await widget.onProfileChanged?.call();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'ثبت دوره انجام نشد',
            en: "Course registration failed",
          ),
          en: "Course registration failed",
        ),
        message: error.code == 'women_calendar_episode_overlap'
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'این بازه با یک ثبت قبلی هم‌پوشانی دارد.',
                  en: "This interval overlaps with a previous record.",
                ),
                en: "This interval overlaps with a previous record.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تغییرات ثبت دوره ذخیره نشد.',
                  en: "Course registration changes were not saved.",
                ),
                en: "Course registration changes were not saved.",
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'حذف ثبت دوره؟',
              en: "Remove course registration?",
            ),
            en: "Remove course registration?",
          ),
        ),
        content: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'این ثبت و یادداشت خصوصی آن حذف می‌شود و قابل بازگشت نیست.',
              en: "This registration and its private note will be deleted and cannot be returned.",
            ),
            en: "This registration and its private note will be deleted and cannot be returned.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'انصراف', en: "opt out"),
                en: "opt out",
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'حذف', en: "Delete"),
                en: "remove",
              ),
            ),
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
          decoration: BoxDecoration(
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
                  SizedBox(height: 18),
                  Text(
                    episode == null
                        ? LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'ثبت دوره جدید',
                              en: "New course registration",
                            ),
                            en: "New course registration",
                          )
                        : LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'ویرایش دوره',
                              en: "Course editing",
                            ),
                            en: "Course editing",
                          ),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: womenInk,
                    ),
                  ),
                  SizedBox(height: 16),
                  _EpisodeDateField(
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'تاریخ شروع',
                        en: "start date",
                      ),
                      en: "start date",
                    ),
                    value: formatAppDate(context, startedOn),
                    icon: Icons.play_circle_outline_rounded,
                    onTap: () async {
                      final value = await showAppDatePicker(
                        context: context,
                        initialDate: startedOn,
                        firstDate: DateTime(2015),
                        lastDate: DateTime.now(),
                        title: LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'تاریخ شروع دوره',
                            en: "Course start date",
                          ),
                          en: "Course start date",
                        ),
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
                  SizedBox(height: 10),
                  _EpisodeDateField(
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'تاریخ پایان',
                        en: "end date",
                      ),
                      en: "end date",
                    ),
                    value: endedOn == null
                        ? LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'هنوز ادامه دارد',
                              en: "It is still going on",
                            ),
                            en: "It is still going on",
                          )
                        : formatAppDate(context, endedOn!),
                    icon: Icons.stop_circle_outlined,
                    onTap: () async {
                      final value = await showAppDatePicker(
                        context: context,
                        initialDate: endedOn ?? startedOn,
                        firstDate: startedOn,
                        lastDate: DateTime.now(),
                        title: LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'تاریخ پایان دوره',
                            en: "Course end date",
                          ),
                          en: "Course end date",
                        ),
                      );
                      if (value != null) setSheetState(() => endedOn = value);
                    },
                    onClear: endedOn == null
                        ? null
                        : () => setSheetState(() => endedOn = null),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    maxLength: 500,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'یادداشت خصوصی',
                          en: "Private note",
                        ),
                        en: "Private note",
                      ),
                      hintText: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'این متن فقط برای خودت نمایش داده می‌شود.',
                          en: "This text is displayed only for you.",
                        ),
                        en: "This text is displayed only for you.",
                      ),
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                      filled: true,
                      fillColor: Color(0xFFF8F3F8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
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
                          icon: Icon(Icons.delete_outline_rounded),
                          label: Text(
                            LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'حذف',
                                en: "Delete",
                              ),
                              en: "remove",
                            ),
                          ),
                        ),
                      Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'انصراف',
                              en: "opt out",
                            ),
                            en: "opt out",
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
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
                        child: Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'ذخیره',
                              en: "Save",
                            ),
                            en: "save",
                          ),
                        ),
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
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تقویم بانوان در این Build فعال نیست',
            en: "Ladies calendar is not active in this build",
          ),
          en: "Ladies calendar is not active in this build",
        ),
        description: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'این قابلیت فقط در نسخه داخلی دارای Feature Flag نمایش داده می‌شود.',
            en: "This feature is displayed only in the built-in version with Feature Flag.",
          ),
          en: "This feature is displayed only in the built-in version with Feature Flag.",
        ),
        actionLabel: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'مشاهده اشتراک‌ها',
            en: "View subscriptions",
          ),
          en: "View subscriptions",
        ),
        onAction: _openSubscription,
      );
    }
    if (_error != null) {
      return _FeatureGate(
        icon: Icons.cloud_off_rounded,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'اطلاعات چرخه دریافت نشد',
            en: "Cycle information not received",
          ),
          en: "Cycle information not received",
        ),
        description: _error!,
        actionLabel: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'تلاش دوباره', en: "Try again"),
          en: "Try again",
        ),
        onAction: _load,
      );
    }
    if (!_enabled) {
      return _FeatureGate(
        icon: Icons.local_florist_outlined,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'فضای شخصی چرخه آماده است',
            en: "The personal space of the cycle is ready",
          ),
          en: "The personal space of the cycle is ready",
        ),
        description: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'با فعال‌سازی تقویم بانوان، تنظیمات چرخه و مدیریت ثبت‌های دوره در دسترس قرار می‌گیرد.',
            en: "By activating the women's calendar, cycle settings and period registration management are available.",
          ),
          en: "By activating the women's calendar, cycle settings and period registration management are available.",
        ),
        actionLabel: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'فعال‌سازی', en: "Activation"),
          en: "Activation",
        ),
        onAction: _openSubscription,
      );
    }

    final estimate = _estimate;
    return WomenCycleBackground(
      child: RefreshIndicator(
        onRefresh: _load,
        color: womenRose,
        child: ListView(
          key: ValueKey('women-calendar-settings-only'),
          physics: AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(18, 18, 18, 32),
          children: [
            WomenSoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'تنظیمات و مدیریت ثبت‌ها',
                        en: "Settings and registration management",
                      ),
                      en: "Settings and registration management",
                    ),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: womenInk,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'اینجا فقط تنظیمات ماندگار چرخه، یادآوری‌ها و تاریخچه دوره‌ها مدیریت می‌شود. حال روزانه از خود تقویم ثبت می‌شود.',
                        en: "Only persistent cycle settings, reminders and course history are managed here. It is recorded daily from the calendar itself.",
                      ),
                      en: "Only persistent cycle settings, reminders and course history are managed here. It is recorded daily from the calendar itself.",
                    ),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.65,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14),
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
            SizedBox(height: 14),
            WomenRemindersCard(
              estimate: estimate,
              remindersEnabled: _remindersEnabled,
              activeTreatmentCount: _activeTreatmentCount,
            ),
            SizedBox(height: 14),
            WomenPeriodHistoryCard(
              episodes: _episodes,
              hasOpenEpisode: _openEpisode != null,
              saving: _saving,
              onStart: _createEpisode,
              onFinish: _finishPeriodToday,
              onEdit: _editEpisode,
            ),
            SizedBox(height: 14),
            WomenPrivacyNotice(),
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
