import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import 'women_calendar_month_card.dart';
import 'women_calendar_screen.dart';
import 'women_companion_daily_log_offline_policy.dart';
import 'women_companion_dashboard_loader.dart';
import 'women_companion_people_hero.dart';
import 'women_daily_log_offline_bridge.dart';

class WomenCompanionScreen extends StatefulWidget {
  const WomenCompanionScreen({
    super.key,
    this.onProfileChanged,
    this.companionApi,
    this.refreshToken = 0,
  });

  final Future<void> Function()? onProfileChanged;
  final WomenCompanionApi? companionApi;
  final int refreshToken;

  @override
  State<WomenCompanionScreen> createState() => _WomenCompanionScreenState();
}

class _WomenCompanionScreenState extends State<WomenCompanionScreen> {
  late final WomenCompanionApi _companionApi =
      widget.companionApi ?? WomenCompanionApi.fromEnvironment();

  bool _loading = true;
  bool _saving = false;
  bool _offlineCached = false;
  String? _error;
  Map<String, dynamic> _profile = const {};
  Map<String, dynamic> _currentProfile = const {};
  String? _currentUserId;
  List<Map<String, dynamic>> _episodes = const [];
  List<Map<String, dynamic>> _dailyLogs = const [];
  List<Map<String, dynamic>> _relationships = const [];
  DateTime _selectedDate = DateTime.now();

  bool get _enabled => _profile['enabled'] == true;

  WomenCalendarEstimate? get _estimate {
    final start = DateTime.tryParse(
      _profile['lastPeriodStart']?.toString() ?? '',
    );
    if (!_enabled || start == null) return null;
    final periodStarts = _episodes
        .map(
          (episode) =>
              DateTime.tryParse(episode['startedOn']?.toString() ?? ''),
        )
        .whereType<DateTime>()
        .toList(growable: false);
    return WomenCalendarEstimate.calculateFromEpisodes(
      lastPeriodStart: start,
      configuredCycleLength: _profile['cycleLength'] is int
          ? _profile['cycleLength'] as int
          : 28,
      periodLength: _profile['periodLength'] is int
          ? _profile['periodLength'] as int
          : 5,
      periodStarts: periodStarts,
    );
  }

  Map<String, dynamic>? get _todayLog => _logForDate(DateTime.now());

  Map<String, dynamic>? _logForDate(DateTime date) {
    final key = _dateKey(date);
    for (final log in _dailyLogs) {
      if (log['loggedOn']?.toString() == key) return log;
    }
    return null;
  }

  bool _isRecordedBleedingDay(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    for (final episode in _episodes) {
      final start = DateTime.tryParse(episode['startedOn']?.toString() ?? '');
      if (start == null) continue;
      final parsedEnd = DateTime.tryParse(episode['endedOn']?.toString() ?? '');
      final startOnly = DateTime(start.year, start.month, start.day);
      final endValue = parsedEnd ?? todayOnly;
      final endOnly = DateTime(endValue.year, endValue.month, endValue.day);
      if (!day.isBefore(startOnly) && !day.isAfter(endOnly)) return true;
    }
    return false;
  }

  List<Map<String, dynamic>> get _companionRelationships {
    final currentUserId = _currentUserId;
    return _relationships
        .where((item) {
          if (item['status']?.toString().toLowerCase() != 'active')
            return false;
          if (item['canViewWomenCalendar'] != true) return false;
          if (currentUserId == null || currentUserId.isEmpty) return true;
          return item['patientUserId']?.toString() == currentUserId;
        })
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WomenCompanionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load(background: true);
    }
  }

  Future<void> _load({bool background = false}) async {
    if (background && _profile.isEmpty) {
      background = false;
    }
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      if (_profile.isEmpty) {
        _loading = true;
      }
      _error = null;
    });
    try {
      final api = context.read<LifeMateApiClient>();
      final now = DateTime.now();
      final fromDate = now.subtract(const Duration(days: 89));
      final loader = WomenCompanionDashboardLoader.forApi(api);
      final loaded = await loader.load(fromDate: fromDate, toDate: now);
      final dashboard = loaded.dashboard;
      if (!mounted) return;
      final currentUser =
          dashboard['currentUser'] as Map<String, dynamic>? ?? const {};
      final user = currentUser['user'] as Map<String, dynamic>? ?? const {};
      setState(() {
        _profile = dashboard['profile'] as Map<String, dynamic>? ?? const {};
        _episodes = (dashboard['episodes'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        _dailyLogs = (dashboard['dailyLogs'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        _offlineCached = loaded.offlineCached;
        if (loaded.offlineCached) {
          _currentUserId = null;
          _currentProfile = const {};
          _relationships = const [];
        } else {
          _currentUserId = user['id']?.toString();
          _currentProfile =
              dashboard['currentProfile'] as Map<String, dynamic>? ?? const {};
          _relationships =
              (dashboard['relationships'] as List<dynamic>? ?? const [])
                  .cast<Map<String, dynamic>>();
        }
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == 'women_calendar_feature_disabled'
            ? LifeMateRuntimeLocale.select(
                fa: 'تقویم بانوان در این نسخه فعال نیست.',
                en: "The women's calendar is not active in this version.",
              )
            : LifeMateRuntimeLocale.select(
                fa: 'اطلاعات چرخه دریافت نشد. دوباره تلاش کنید.',
                en: 'Cycle information not received. Try again.',
              );
      });
    } catch (error) {
      debugPrint('Women companion dashboard load failed: $error');
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: 'اطلاعات چرخه دریافت نشد. دوباره تلاش کنید.',
            en: 'Cycle information not received. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAdvancedManagement() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Color(0xFFFFF8FC),
          appBar: AppBar(
            title: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تنظیمات و مدیریت ثبت‌ها',
                  en: "Settings and registration management",
                ),
                en: "Settings and registration management",
              ),
            ),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
          body: SafeArea(
            top: false,
            child: WomenCalendarScreen(
              onProfileChanged: widget.onProfileChanged,
            ),
          ),
        ),
      ),
    );
    await _load();
    await widget.onProfileChanged?.call();
  }

  Future<void> _editDailyLog(DateTime date) async {
    final current = _logForDate(date);
    final draft = await showModalBottomSheet<WomenDailyLogDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DailyCheckInSheet(existing: current),
    );
    if (draft == null || _saving) return;
    setState(() => _saving = true);
    final clientRequestId = LifeMateApiClient.createClientRequestId();
    final currentShare = current?['shareSummaryWithCompanion'] == true;
    final shareTransition = currentShare == draft.shareWithCompanion
        ? null
        : draft.shareWithCompanion;
    final canonicalSymptoms =
        draft.symptoms
            .map((value) => value.trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    try {
      await _companionApi.saveDailyLog(
        version: current?['version'] is int ? current!['version'] as int : 0,
        loggedOn: date,
        mood: draft.mood,
        energyLevel: draft.energyLevel,
        painLevel: draft.painLevel,
        symptoms: canonicalSymptoms,
        privateNotes: draft.privateNotes,
        shareSummaryWithCompanion: shareTransition,
        clientRequestId: clientRequestId,
      );
      if (!mounted) return;
      final isToday = _dateKey(date) == _dateKey(DateTime.now());
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: isToday
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'حال امروز ثبت شد',
                  en: "It was registered today",
                ),
                en: "It was registered today",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'ثبت روز ذخیره شد',
                  en: "The record of the day was saved",
                ),
                en: "The record of the day was saved",
              ),
        message: draft.shareWithCompanion
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'فقط خلاصه‌ای که اجازه داده‌ای با همدمت به اشتراک گذاشته می‌شود.',
                  en: "Only the summary you have given permission will be shared with your partner.",
                ),
                en: "Only the summary you have given permission will be shared with your partner.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'این ثبت به‌صورت خصوصی ذخیره شد.',
                  en: "This recording was saved privately.",
                ),
                en: "This recording was saved privately.",
              ),
      );
      await _load();
    } on LifeMateApiException catch (error) {
      if (WomenCompanionDailyLogOfflinePolicy.canQueueAfter(error) &&
          WomenCompanionDailyLogOfflinePolicy.canQueuePrivateMutation(
            current: current,
            requestedShareWithCompanion: draft.shareWithCompanion,
          )) {
        WomenDailyLogOfflineBridge? offline;
        try {
          offline = await WomenDailyLogOfflineBridge.open(
            apiClient: context.read<LifeMateApiClient>(),
          );
          await offline.enqueueUpsert(
            mutationId: clientRequestId,
            loggedOn: date,
            version: current?['version'] is int
                ? current!['version'] as int
                : 0,
            mood: draft.mood,
            energyLevel: draft.energyLevel,
            painLevel: draft.painLevel,
            symptoms: canonicalSymptoms.toSet(),
            privateNotes: draft.privateNotes,
          );
          if (!mounted) return;
          final pending = <String, dynamic>{
            ...?current,
            'loggedOn': _dateKey(date),
            'mood': draft.mood.trim().toLowerCase(),
            'energyLevel': draft.energyLevel,
            'painLevel': draft.painLevel,
            'symptoms': canonicalSymptoms,
            'privateNotes': draft.privateNotes,
            'shareSummaryWithCompanion': false,
            'version': current?['version'] is int
                ? current!['version'] as int
                : 0,
            'pendingSync': true,
            'serverConfirmed': false,
          };
          setState(() {
            _dailyLogs = <Map<String, dynamic>>[
              ..._dailyLogs.where(
                (log) => log['loggedOn']?.toString() != _dateKey(date),
              ),
              pending,
            ];
          });
          LifeMateNotice.show(
            context,
            type: LifeMateNoticeType.success,
            title: LifeMateRuntimeLocale.select(
              fa: 'روی این دستگاه ذخیره شد',
              en: 'Saved on this device',
            ),
            message: LifeMateRuntimeLocale.select(
              fa: 'این ثبت خصوصی است و بعد از اتصال دوباره همگام می‌شود.',
              en: 'This private check-in will sync after reconnection.',
            ),
          );
          return;
        } on UnsupportedError {
          // Web deliberately has no protected PHI persistence.
        } on LifeMateApiException {
          // Protected runtime unavailable: preserve the original API failure.
        } on StateError {
          // Protected runtime unavailable: preserve the original API failure.
        } finally {
          offline?.close();
        }
      }
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'ثبت انجام نشد',
            en: "Registration failed",
          ),
          en: "Registration failed",
        ),
        message: error.code == 'stale_women_calendar_daily_log'
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'این روز تغییر کرده بود؛ اطلاعات تازه شد و می‌توانی دوباره ویرایش کنی.',
                  en: "This day had changed; The information is updated and you can edit again.",
                ),
                en: "This day had changed; The information is updated and you can edit again.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'اطلاعات این روز ذخیره نشد. دوباره تلاش کن.',
                  en: "This day's information was not saved. try again",
                ),
                en: "This day's information was not saved. try again",
              ),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled || !_enabled) {
      return _InactiveWomenExperience(onOpenSettings: _openAdvancedManagement);
    }
    if (_error != null) {
      return _WomenError(message: _error!, onRetry: _load);
    }

    final estimate = _estimate;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF8FC), Color(0xFFF8F3FF), Color(0xFFFFFBF7)],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const ValueKey('women-companion-mobile-dashboard'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            if (_offlineCached) ...[
              Container(
                key: const ValueKey('women-companion-offline-owner-banner'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F6),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      color: Color(0xFFD75C8D),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        LifeMateRuntimeLocale.select(
                          fa: 'اطلاعات خصوصی ذخیره‌شده روی این دستگاه نمایش داده می‌شود. اشتراک‌گذاری و همدم تا اتصال دوباره آنلاین می‌مانند.',
                          en: 'Showing private data saved on this device. Sharing and companion access stay online-only until reconnection.',
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ] else ...[
              WomenCompanionPeopleHero(
                currentProfile: _currentProfile,
                relationships: _companionRelationships,
              ),
              const SizedBox(height: 14),
            ],
            WomenCalendarMonthCard(
              episodes: _episodes,
              estimate: estimate,
              selectedDate: _selectedDate,
              onDateSelected: (date) => setState(() => _selectedDate = date),
            ),
            const SizedBox(height: 10),
            _SelectedDaySummaryCard(
              date: _selectedDate,
              log: _logForDate(_selectedDate),
              estimate: estimate,
              recordedBleeding: _isRecordedBleedingDay(_selectedDate),
              saving: _saving,
              onEdit: () => _editDailyLog(_selectedDate),
            ),
            const SizedBox(height: 14),
            _DailyCheckInCard(
              log: _todayLog,
              saving: _saving,
              onEdit: () => _editDailyLog(DateTime.now()),
            ),
            const SizedBox(height: 14),
            _DailyTipCard(estimate: estimate, log: _todayLog),
            const SizedBox(height: 14),
            _FourteenDayStrip(estimate: estimate),
            const SizedBox(height: 14),
            _ReportsCard(episodes: _episodes, logs: _dailyLogs),
            const SizedBox(height: 14),
            const _MedicalSafetyCard(),
            const SizedBox(height: 14),
            _ReminderAndSettingsCard(
              profile: _profile,
              onOpenSettings: _openAdvancedManagement,
            ),
          ],
        ),
      ),
    );
  }
}

class _CycleRing extends StatelessWidget {
  const _CycleRing({required this.estimate, required this.size});

  final WomenCalendarEstimate? estimate;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = estimate;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _CycleRingPainter(estimate: value)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value == null
                      ? '—'
                      : LifeMateRuntimeLocale.select(
                          fa: 'روز ${localizeDigits(context, value.cycleDay)}',
                          en: "Day ${localizeDigits(context, value.cycleDay)}",
                        ),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 3),
                Text(
                  value == null
                      ? LifeMateRuntimeLocale.select(fa: 'چرخه', en: "Cycle")
                      : LifeMateRuntimeLocale.select(
                          fa: 'از ${localizeDigits(context, value.cycleLength)} روز',
                          en: "of ${localizeDigits(context, value.cycleLength)} days",
                        ),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
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

class _CycleRingPainter extends CustomPainter {
  const _CycleRingPainter({required this.estimate});

  final WomenCalendarEstimate? estimate;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 11;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF2EDF5);
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    final value = estimate;
    if (value == null) return;

    final sections = value.fertilityEstimateReliable
        ? <(int, Color)>[
            (value.periodLength, const Color(0xFFF15D7B)),
            (
              (value.fertileWindowStartDay - value.periodLength - 1)
                  .clamp(0, value.cycleLength)
                  .toInt(),
              const Color(0xFFBA8CE2),
            ),
            (
              (value.fertileWindowEndDay - value.fertileWindowStartDay + 1)
                  .clamp(0, value.cycleLength)
                  .toInt(),
              const Color(0xFF58C8B8),
            ),
            (
              (value.pmsStartDay - value.fertileWindowEndDay - 1)
                  .clamp(0, value.cycleLength)
                  .toInt(),
              const Color(0xFFF5BE58),
            ),
            (
              (value.cycleLength - value.pmsStartDay + 1)
                  .clamp(0, value.cycleLength)
                  .toInt(),
              const Color(0xFFE98A75),
            ),
          ]
        : <(int, Color)>[
            (value.periodLength, const Color(0xFFF15D7B)),
            (
              (value.pmsStartDay - value.periodLength - 1)
                  .clamp(0, value.cycleLength)
                  .toInt(),
              const Color(0xFFBA8CE2),
            ),
            (
              (value.cycleLength - value.pmsStartDay + 1)
                  .clamp(0, value.cycleLength)
                  .toInt(),
              const Color(0xFFE98A75),
            ),
          ];
    var start = -math.pi / 2;
    const gap = 0.035;
    for (final section in sections) {
      if (section.$1 <= 0) continue;
      final sweep = math.pi * 2 * section.$1 / value.cycleLength;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..color = section.$2;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(0, sweep - gap),
        false,
        paint,
      );
      start += sweep;
    }

    final angle =
        -math.pi / 2 + math.pi * 2 * (value.cycleDay - 0.5) / value.cycleLength;
    final marker = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    canvas.drawCircle(marker, 9, Paint()..color = Colors.white);
    canvas.drawCircle(
      marker,
      6,
      Paint()..color = phaseVisual(value.detailedPhase).color,
    );
  }

  @override
  bool shouldRepaint(covariant _CycleRingPainter oldDelegate) =>
      oldDelegate.estimate != estimate;
}

class _DailyCheckInCard extends StatelessWidget {
  const _DailyCheckInCard({
    required this.log,
    required this.saving,
    required this.onEdit,
  });

  final Map<String, dynamic>? log;
  final bool saving;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final mood = moodVisual(log?['mood']?.toString());
    return _PastelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'حال و احساس امروز',
                en: "Feeling today",
              ),
              en: "Feeling today",
            ),
            subtitle: log == null
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'امروز چه احساسی داری؟',
                      en: "how are you feeling today",
                    ),
                    en: "how are you feeling today",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ثبت امروزت محفوظ است.',
                      en: "Your registration today is reserved.",
                    ),
                    en: "Your registration today is reserved.",
                  ),
            action: TextButton(
              onPressed: saving ? null : onEdit,
              child: Text(
                log == null
                    ? LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'ثبت حال',
                          en: "Register now",
                        ),
                        en: "Register now",
                      )
                    : LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'ویرایش',
                          en: "Edit",
                        ),
                        en: "Edit",
                      ),
              ),
            ),
          ),
          SizedBox(height: 12),
          if (log == null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MoodPreview(
                  emoji: '😊',
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(fa: 'عالی', en: "great"),
                    en: "great",
                  ),
                ),
                _MoodPreview(
                  emoji: '🙂',
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(fa: 'خوب', en: "good"),
                    en: "good",
                  ),
                ),
                _MoodPreview(
                  emoji: '😐',
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'معمولی',
                      en: "normal",
                    ),
                    en: "normal",
                  ),
                ),
                _MoodPreview(
                  emoji: '😔',
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'کم‌انرژی',
                      en: "low energy",
                    ),
                    en: "low energy",
                  ),
                ),
                _MoodPreview(
                  emoji: '😣',
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'تحت فشار',
                      en: "under pressure",
                    ),
                    en: "under pressure",
                  ),
                ),
              ],
            )
          else
            Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: mood.color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Text(mood.emoji, style: TextStyle(fontSize: 30)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mood.label,
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 4),
                        Text(
                          LifeMateRuntimeLocale.select(
                            fa: 'انرژی ${localizeDigits(context, log!['energyLevel'] ?? '—')} از ۵ • درد ${localizeDigits(context, log!['painLevel'] ?? '—')} از ۵',
                            en: "Energy ${localizeDigits(context, log!['energyLevel'] ?? '—')} out of 5 • Pain ${localizeDigits(context, log!['painLevel'] ?? '—')} out of 5",
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    log!['shareSummaryWithCompanion'] == true
                        ? Icons.favorite_rounded
                        : Icons.lock_rounded,
                    color: log!['shareSummaryWithCompanion'] == true
                        ? Color(0xFFE55A8B)
                        : Color(0xFF8A8791),
                  ),
                ],
              ),
            ),
          if (saving) ...[
            SizedBox(height: 10),
            LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }
}

class _MoodPreview extends StatelessWidget {
  const _MoodPreview({required this.emoji, required this.label});
  final String emoji;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: 58,
    padding: const EdgeInsets.symmetric(vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4F8),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 9.5)),
      ],
    ),
  );
}

class _DailyTipCard extends StatelessWidget {
  const _DailyTipCard({required this.estimate, required this.log});
  final WomenCalendarEstimate? estimate;
  final Map<String, dynamic>? log;

  @override
  Widget build(BuildContext context) {
    final visual = phaseVisual(estimate?.detailedPhase);
    final text = phaseTip(estimate?.detailedPhase, log);
    return Container(
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [visual.color.withValues(alpha: 0.15), Color(0xFFFFF3F7)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.spa_rounded, color: visual.color),
          ),
          SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'نکته امروز',
                      en: "Today's tip",
                    ),
                    en: "Today's tip",
                  ),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 6),
                Text(
                  text,
                  style: TextStyle(height: 1.7, color: Color(0xFF685B69)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedDaySummaryCard extends StatelessWidget {
  const _SelectedDaySummaryCard({
    required this.date,
    required this.log,
    required this.estimate,
    required this.recordedBleeding,
    required this.saving,
    required this.onEdit,
  });

  final DateTime date;
  final Map<String, dynamic>? log;
  final WomenCalendarEstimate? estimate;
  final bool recordedBleeding;
  final bool saving;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final phase = estimate?.phaseForDate(date);
    final phaseValue = phaseVisual(phase);
    final mood = moodVisual(log?['mood']?.toString());
    final symptoms = (log?['symptoms'] as List<dynamic>? ?? const [])
        .map((item) => _selectedDaySymptomLabel(item.toString()))
        .toList(growable: false);
    return _PastelCard(
      child: Column(
        key: ValueKey('women-calendar-selected-day-summary'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatAppDate(context, date, includeWeekday: true),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      recordedBleeding
                          ? LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'پریود ثبت‌شده',
                                en: "Recorded period",
                              ),
                              en: "Recorded period",
                            )
                          : LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: '${phaseValue.label} • تخمینی',
                                en: "${phaseValue.label} • Est",
                              ),
                              en: "${phaseValue.label} • Est",
                            ),
                      style: TextStyle(
                        color: recordedBleeding
                            ? Color(0xFFD64A70)
                            : phaseValue.foreground,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                recordedBleeding ? Icons.water_drop_rounded : phaseValue.icon,
                color: recordedBleeding ? Color(0xFFF15D7B) : phaseValue.color,
              ),
            ],
          ),
          SizedBox(height: 12),
          if (log == null) ...[
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'برای این روز چیزی ثبت نشده',
                  en: "Nothing registered for this day",
                ),
                en: "Nothing registered for this day",
              ),
              style: TextStyle(color: AppColors.textSecondary),
            ),
            SizedBox(height: 10),
            OutlinedButton.icon(
              key: ValueKey('women-calendar-selected-day-create'),
              onPressed: saving ? null : onEdit,
              icon: Icon(Icons.add_rounded),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'ثبت حال این روز',
                    en: "Record the current state of this day",
                  ),
                  en: "Record the current state of this day",
                ),
              ),
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DayFact(
                  icon: Icons.mood_rounded,
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(fa: 'حال', en: "now"),
                    en: "now",
                  ),
                  value: '${mood.emoji} ${mood.label}',
                ),
                _DayFact(
                  icon: Icons.bolt_rounded,
                  label: 'انرژی',
                  value:
                      '${localizeDigits(context, log!['energyLevel'] ?? '—')}/۵',
                ),
                _DayFact(
                  icon: Icons.monitor_heart_outlined,
                  label: 'درد',
                  value:
                      '${localizeDigits(context, log!['painLevel'] ?? '—')}/۵',
                ),
                _DayFact(
                  icon: Icons.water_drop_outlined,
                  label: 'خونریزی',
                  value: recordedBleeding
                      ? LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'ثبت‌شده',
                            en: "registered",
                          ),
                          en: "registered",
                        )
                      : LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'ثبت نشده',
                            en: "Not recorded",
                          ),
                          en: "not registered",
                        ),
                ),
              ],
            ),
            if (symptoms.isNotEmpty) ...[
              SizedBox(height: 10),
              Text(
                LifeMateRuntimeLocale.select(
                  fa: 'نشانه‌ها: ${symptoms.join('، ')}',
                  en: "Tokens: ${symptoms.join('، ')}",
                ),
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
            ],
            SizedBox(height: 10),
            TextButton.icon(
              key: ValueKey('women-calendar-selected-day-edit'),
              onPressed: saving ? null : onEdit,
              icon: Icon(Icons.edit_rounded, size: 18),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'ویرایش ثبت روز',
                    en: "Edit the day log",
                  ),
                  en: "Edit the day log",
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayFact extends StatelessWidget {
  const _DayFact({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF8A66A6)),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 10.5,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

String _selectedDaySymptomLabel(String raw) {
  return switch (raw.trim().toLowerCase()) {
    'cramps' => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'گرفتگی', en: "cramps"),
      en: "cramps",
    ),
    'headache' => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سردرد', en: "headache"),
      en: "headache",
    ),
    'bloating' => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'نفخ', en: "flatulence"),
      en: "flatulence",
    ),
    'fatigue' => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خستگی', en: "tiredness"),
      en: "tiredness",
    ),
    'breast_tenderness' || 'breasttenderness' => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'حساسیت سینه',
        en: "Breast tenderness",
      ),
      en: "Breast tenderness",
    ),
    'back_pain' || 'backpain' => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'کمردرد', en: "back pain"),
      en: "back pain",
    ),
    'sleep_change' || 'sleepchange' => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغییر خواب', en: "sleep change"),
      en: "sleep change",
    ),
    'appetite_change' || 'appetitechange' => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'تغییر اشتها',
        en: "Change in appetite",
      ),
      en: "Change in appetite",
    ),
    'no_symptom' || 'nosymptom' => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'بدون نشانه', en: "no sign"),
      en: "no sign",
    ),
    _ => raw,
  };
}

class _FourteenDayStrip extends StatelessWidget {
  const _FourteenDayStrip({required this.estimate});
  final WomenCalendarEstimate? estimate;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return _PastelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: '۱۴ روز پیش رو',
                en: "14 days ahead",
              ),
              en: "14 days ahead",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'یک نگاه آرام به ریتم تخمینی چرخه',
                en: "A relaxed look at the approximate rhythm of the cycle",
              ),
              en: "A relaxed look at the approximate rhythm of the cycle",
            ),
          ),
          SizedBox(height: 12),
          SizedBox(
            height: 142,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 14,
              separatorBuilder: (_, __) => SizedBox(width: 8),
              itemBuilder: (context, index) {
                final date = DateTime(
                  today.year,
                  today.month,
                  today.day,
                ).add(Duration(days: index));
                final phase = estimate?.phaseForDate(date);
                final visual = phaseVisual(phase);
                return Container(
                  width: 68,
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  decoration: BoxDecoration(
                    color: visual.color.withValues(
                      alpha: index == 0 ? 0.18 : 0.09,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: index == 0 ? visual.color : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        index == 0
                            ? LifeMateRuntimeLocale.select(
                                fa: 'امروز',
                                en: "Today",
                              )
                            : localizeDigits(context, index),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 7),
                      Icon(visual.icon, color: visual.color, size: 21),
                      SizedBox(height: 6),
                      Text(
                        visual.shortLabel,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(fontSize: 8.5, height: 1.2),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportsCard extends StatelessWidget {
  const _ReportsCard({required this.episodes, required this.logs});
  final List<Map<String, dynamic>> episodes;
  final List<Map<String, dynamic>> logs;

  @override
  Widget build(BuildContext context) {
    final completed = episodes
        .where((item) => item['endedOn'] != null)
        .toList(growable: false);
    final averagePeriod = completed.isEmpty
        ? null
        : completed
                  .map((item) {
                    final start = DateTime.tryParse(
                      item['startedOn']?.toString() ?? '',
                    );
                    final end = DateTime.tryParse(
                      item['endedOn']?.toString() ?? '',
                    );
                    return start == null || end == null
                        ? 0
                        : end.difference(start).inDays + 1;
                  })
                  .where((value) => value > 0)
                  .fold<int>(0, (sum, value) => sum + value) /
              completed.length;
    final symptomCounts = <String, int>{};
    var energySum = 0;
    for (final log in logs) {
      energySum += log['energyLevel'] is int ? log['energyLevel'] as int : 0;
      for (final symptom in (log['symptoms'] as List<dynamic>? ?? const [])) {
        symptomCounts.update(
          symptom.toString(),
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final commonSymptom = symptomCounts.entries.isEmpty
        ? null
        : (symptomCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;
    final averageEnergy = logs.isEmpty ? null : energySum / logs.length;

    return _PastelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'گزارش‌های من',
                en: "My reports",
              ),
              en: "My reports",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'خلاصه ساده از ثبت‌های خودت، بدون تشخیص پزشکی',
                en: "Simple summary of your records, without medical diagnosis",
              ),
              en: "Simple summary of your records, without medical diagnosis",
            ),
          ),
          SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth < 330
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 16) / 3;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ReportTile(
                    width: width,
                    icon: Icons.calendar_view_month_rounded,
                    label: 'دوره‌ها',
                    value: averagePeriod == null
                        ? 'ثبت ناکافی'
                        : 'میانگین ${localizeDigits(context, averagePeriod.round())} روز',
                    color: Color(0xFFE65F8C),
                  ),
                  _ReportTile(
                    width: width,
                    icon: Icons.bubble_chart_rounded,
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'نشانه پرتکرار',
                        en: "Frequent symptom",
                      ),
                      en: "Frequent symptom",
                    ),
                    value: commonSymptom == null
                        ? LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'ثبت ناکافی',
                              en: "Insufficient registration",
                            ),
                            en: "Insufficient registration",
                          )
                        : symptomLabel(commonSymptom),
                    color: Color(0xFF9C71D2),
                  ),
                  _ReportTile(
                    width: width,
                    icon: Icons.bolt_rounded,
                    label: LifeMateRuntimeLocale.select(
                      fa: 'انرژی',
                      en: "energy",
                    ),
                    value: averageEnergy == null
                        ? LifeMateRuntimeLocale.select(
                            fa: 'ثبت ناکافی',
                            en: "Insufficient registration",
                          )
                        : LifeMateRuntimeLocale.select(
                            fa: '${localizeDigits(context, averageEnergy.toStringAsFixed(1))} از ۵',
                            en: "${localizeDigits(context, averageEnergy.toStringAsFixed(1))} of 5",
                          ),
                    color: Color(0xFFF0A643),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    constraints: const BoxConstraints(minHeight: 116),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 18),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _ReminderAndSettingsCard extends StatelessWidget {
  const _ReminderAndSettingsCard({
    required this.profile,
    required this.onOpenSettings,
  });
  final Map<String, dynamic> profile;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final lastStart = DateTime.tryParse(
      profile['lastPeriodStart']?.toString() ?? '',
    );
    return _PastelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'یادآوری‌ها و تنظیمات',
                en: "Reminders and settings",
              ),
              en: "Reminders and settings",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'کنترل چرخه همیشه دست خودت است.',
                en: "The control of the cycle is always in your hands.",
              ),
              en: "The control of the cycle is always in your hands.",
            ),
          ),
          SizedBox(height: 10),
          _InfoLine(
            icon: Icons.notifications_active_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'یادآوری نزدیک‌شدن دوره',
                en: "Reminder of approaching period",
              ),
              en: "Reminder of approaching period",
            ),
            value: profile['remindersEnabled'] == false
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(fa: 'خاموش', en: "off"),
                    en: "off",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'فعال و خصوصی',
                      en: "Active and private",
                    ),
                    en: "Active and private",
                  ),
          ),
          _InfoLine(
            icon: Icons.edit_calendar_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'آخرین شروع ثبت‌شده',
                en: "Last recorded start",
              ),
              en: "Last recorded start",
            ),
            value: lastStart == null
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ثبت نشده',
                      en: "Not recorded",
                    ),
                    en: "not registered",
                  )
                : formatAppDate(context, lastStart),
          ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpenSettings,
              icon: Icon(Icons.tune_rounded),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'تنظیمات و مدیریت ثبت‌ها',
                    en: "Settings and registration management",
                  ),
                  en: "Settings and registration management",
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Color(0xFFD75C8D),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.title,
    required this.value,
  });
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEFF5),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFFD75C8D)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _MedicalSafetyCard extends StatelessWidget {
  const _MedicalSafetyCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Color(0xFFFFF7E8),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Color(0xFFFFE1A5)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.health_and_safety_outlined, color: Color(0xFFB97818)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'چرخه و فازها تخمینی‌اند و برای تشخیص، اثبات تخمک‌گذاری یا پیشگیری از بارداری طراحی نشده‌اند. در درد شدید، خون‌ریزی غیرعادی یا نگرانی پزشکی با پزشک تماس بگیر.',
                en: "Cycles and phases are estimates and are not designed to diagnose, prove ovulation or prevent pregnancy. Call your doctor if you have severe pain, unusual bleeding, or a medical concern.",
              ),
              en: "Cycles and phases are estimates and are not designed to diagnose, prove ovulation or prevent pregnancy. Call your doctor if you have severe pain, unusual bleeding, or a medical concern.",
            ),
            style: TextStyle(
              height: 1.65,
              fontSize: 11.5,
              color: Color(0xFF765A34),
            ),
          ),
        ),
      ],
    ),
  );
}

class _DailyCheckInSheet extends StatefulWidget {
  const _DailyCheckInSheet({required this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_DailyCheckInSheet> createState() => _DailyCheckInSheetState();
}

class _DailyCheckInSheetState extends State<_DailyCheckInSheet> {
  late String _mood;
  late int _energy;
  late int _pain;
  late Set<String> _symptoms;
  late bool _share;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _mood = existing?['mood']?.toString() ?? 'good';
    _energy = existing?['energyLevel'] is int
        ? existing!['energyLevel'] as int
        : 3;
    _pain = existing?['painLevel'] is int ? existing!['painLevel'] as int : 0;
    _symptoms = Set<String>.from(
      (existing?['symptoms'] as List<dynamic>? ?? const []).map(
        (item) => item.toString(),
      ),
    );
    _share = existing?['shareSummaryWithCompanion'] == true;
    _notes = TextEditingController(
      text: existing?['privateNotes']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom = math.max(media.viewInsets.bottom, media.viewPadding.bottom);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: Color(0xFFFFFBFD),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 46,
                height: 4,
                decoration: BoxDecoration(
                  color: Color(0xFFE3DCE5),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            SizedBox(height: 14),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'حال امروز من',
                  en: "How am I today?",
                ),
                en: "How am I today?",
              ),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 4),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'هر چیزی که ثبت می‌کنی ابتدا خصوصی است.',
                  en: "Everything you record is private at first.",
                ),
                en: "Everything you record is private at first.",
              ),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
            ),
            SizedBox(height: 18),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'حال روحی',
                  en: "state of mind",
                ),
                en: "state of mind",
              ),
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['great', 'good', 'neutral', 'low', 'overwhelmed']
                  .map((value) => moodVisual(value))
                  .map(
                    (visual) => ChoiceChip(
                      selected: _mood == visual.code,
                      onSelected: (_) => setState(() => _mood = visual.code),
                      avatar: Text(visual.emoji),
                      label: Text(visual.label),
                      selectedColor: visual.color.withValues(alpha: 0.18),
                      side: BorderSide.none,
                    ),
                  )
                  .toList(growable: false),
            ),
            SizedBox(height: 18),
            _LevelSlider(
              title: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'انرژی امروز',
                  en: "Energy today",
                ),
                en: "Energy today",
              ),
              value: _energy,
              min: 1,
              max: 5,
              color: Color(0xFFF0A643),
              onChanged: (value) => setState(() => _energy = value),
            ),
            _LevelSlider(
              title: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'شدت درد',
                  en: "intensity of pain",
                ),
                en: "intensity of pain",
              ),
              value: _pain,
              min: 0,
              max: 5,
              color: Color(0xFFE46378),
              onChanged: (value) => setState(() => _pain = value),
            ),
            SizedBox(height: 8),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'نشانه‌ها', en: "signs"),
                en: "signs",
              ),
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: symptomOptions
                  .map((option) {
                    final selected = _symptoms.contains(option.code);
                    return FilterChip(
                      selected: selected,
                      onSelected: (value) {
                        setState(() {
                          if (option.code == 'no_symptom') {
                            _symptoms = value ? {'no_symptom'} : {};
                          } else {
                            _symptoms.remove('no_symptom');
                            value
                                ? _symptoms.add(option.code)
                                : _symptoms.remove(option.code);
                          }
                        });
                      },
                      avatar: Icon(option.icon, size: 17, color: option.color),
                      label: Text(option.label),
                      selectedColor: option.color.withValues(alpha: 0.14),
                      side: BorderSide.none,
                    );
                  })
                  .toList(growable: false),
            ),
            SizedBox(height: 15),
            TextField(
              controller: _notes,
              maxLength: 500,
              maxLines: 3,
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
                    fa: 'حس، خواب یا اتفاق امروز را برای خودت بنویس...',
                    en: "Write the feeling, dream or today's event for yourself...",
                  ),
                  en: "Write the feeling, dream or today's event for yourself...",
                ),
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _share,
                onChanged: (value) => setState(() => _share = value),
                title: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'اشتراک خلاصه با همدم',
                      en: "Share the summary with the companion",
                    ),
                    en: "Share the summary with the companion",
                  ),
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'فقط حال، انرژی، شدت درد و نشانه‌های انتخابی دیده می‌شود؛ یادداشت خصوصی هرگز به اشتراک گذاشته نمی‌شود.',
                      en: "Only current, energy, pain intensity and selected symptoms are seen; A private note is never shared.",
                    ),
                    en: "Only current, energy, pain intensity and selected symptoms are seen; A private note is never shared.",
                  ),
                  style: TextStyle(fontSize: 10.5, height: 1.5),
                ),
                activeThumbColor: Color(0xFFD75C8D),
              ),
            ),
            SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(
                  WomenDailyLogDraft(
                    mood: _mood,
                    energyLevel: _energy,
                    painLevel: _pain,
                    symptoms: _symptoms.toList(growable: false),
                    privateNotes: _notes.text.trim(),
                    shareWithCompanion: _share,
                  ),
                ),
                icon: Icon(Icons.favorite_rounded),
                label: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ثبت حال امروز',
                      en: "Register today",
                    ),
                    en: "Register today",
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Color(0xFFD75C8D),
                  padding: EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WomenDailyLogDraft {
  const WomenDailyLogDraft({
    required this.mood,
    required this.energyLevel,
    required this.painLevel,
    required this.symptoms,
    required this.privateNotes,
    required this.shareWithCompanion,
  });
  final String mood;
  final int energyLevel;
  final int painLevel;
  final List<String> symptoms;
  final String privateNotes;
  final bool shareWithCompanion;
}

class _LevelSlider extends StatelessWidget {
  const _LevelSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
  });
  final String title;
  final int value;
  final int min;
  final int max;
  final Color color;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(title, style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: '${localizeDigits(context, value)} از ${localizeDigits(context, max)}',
                en: "${localizeDigits(context, value)} from ${localizeDigits(context, max)}",
              ),
              en: "${localizeDigits(context, value)} from ${localizeDigits(context, max)}",
            ),
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
      Slider(
        value: value.toDouble(),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: max - min,
        activeColor: color,
        onChanged: (next) => onChanged(next.round()),
      ),
    ],
  );
}

class _PastelCard extends StatelessWidget {
  const _PastelCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white),
      boxShadow: const [
        BoxShadow(
          color: Color(0x109A6D94),
          blurRadius: 22,
          offset: Offset(0, 9),
        ),
      ],
    ),
    child: child,
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    this.action,
  });
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      if (action != null) action!,
    ],
  );
}

class _InactiveWomenExperience extends StatelessWidget {
  const _InactiveWomenExperience({required this.onOpenSettings});
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFFFFF4F9), Color(0xFFF5F0FF)]),
    ),
    child: Center(
      child: Padding(
        padding: EdgeInsets.all(26),
        child: _PastelCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_rounded, size: 56, color: Color(0xFFD85B8C)),
              SizedBox(height: 14),
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'فضای شخصی چرخه تو',
                    en: "Personal space of your cycle",
                  ),
                  en: "Personal space of your cycle",
                ),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 8),
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'برای دیدن ریتم چرخه، حال روزانه و گزارش‌های خصوصی، اطلاعات پایه را کامل کن.',
                    en: "Complete basic information to see cycle rhythm, daily status and private reports.",
                  ),
                  en: "Complete basic information to see cycle rhythm, daily status and private reports.",
                ),
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.6, color: AppColors.textSecondary),
              ),
              SizedBox(height: 18),
              FilledButton(
                onPressed: onOpenSettings,
                child: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'راه‌اندازی تقویم بانوان',
                      en: "Launching a women's calendar",
                    ),
                    en: "Launching a women's calendar",
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _WomenError extends StatelessWidget {
  const _WomenError({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 52, color: Color(0xFFD75C8D)),
          SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          SizedBox(height: 14),
          FilledButton(
            onPressed: onRetry,
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تلاش دوباره',
                  en: "Try again",
                ),
                en: "Try again",
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class PhaseVisual {
  const PhaseVisual({
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.color,
    required this.foreground,
  });
  final String label;
  final String shortLabel;
  final IconData icon;
  final Color color;
  final Color foreground;
}

PhaseVisual phaseVisual(WomenCyclePhase? phase) => switch (phase) {
  WomenCyclePhase.period => PhaseVisual(
    label: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'فاز قاعدگی', en: "Menstrual phase"),
      en: "Menstrual phase",
    ),
    shortLabel: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'قاعدگی', en: "Menstruation"),
      en: "Menstruation",
    ),
    icon: Icons.water_drop_rounded,
    color: Color(0xFFF15D7B),
    foreground: Color(0xFF9F2847),
  ),
  WomenCyclePhase.follicular => PhaseVisual(
    label: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'فاز فولیکولار',
        en: "Follicular phase",
      ),
      en: "Follicular phase",
    ),
    shortLabel: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'فولیکولار', en: "follicular"),
      en: "follicular",
    ),
    icon: Icons.spa_rounded,
    color: Color(0xFFB48BE1),
    foreground: Color(0xFF6F439F),
  ),
  WomenCyclePhase.fertile => PhaseVisual(
    label: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'پنجره باروری تخمینی',
        en: "Estimated fertility window",
      ),
      en: "Estimated fertility window",
    ),
    shortLabel: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'باروری', en: "fertility"),
      en: "fertility",
    ),
    icon: Icons.local_florist_rounded,
    color: Color(0xFF57C5B5),
    foreground: Color(0xFF247D72),
  ),
  WomenCyclePhase.ovulation => PhaseVisual(
    label: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'روز تخمک‌گذاری تخمینی',
        en: "Estimated day of ovulation",
      ),
      en: "Estimated day of ovulation",
    ),
    shortLabel: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تخمک‌گذاری', en: "Ovulation"),
      en: "Ovulation",
    ),
    icon: Icons.brightness_5_rounded,
    color: Color(0xFF55A8E8),
    foreground: Color(0xFF286A9D),
  ),
  WomenCyclePhase.luteal => PhaseVisual(
    label: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'فاز لوتئال', en: "Luteal phase"),
      en: "Luteal phase",
    ),
    shortLabel: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'لوتئال', en: "Luteal"),
      en: "Luteal",
    ),
    icon: Icons.wb_twilight_rounded,
    color: Color(0xFFF3B651),
    foreground: Color(0xFF946517),
  ),
  WomenCyclePhase.pms => PhaseVisual(
    label: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'روزهای پیش از دوره',
        en: "Days before the period",
      ),
      en: "Days before the period",
    ),
    shortLabel: 'PMS',
    icon: Icons.nightlight_round,
    color: Color(0xFFE88973),
    foreground: Color(0xFF9D4938),
  ),
  _ => PhaseVisual(
    label: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ریتم چرخه', en: "Cycle rhythm"),
      en: "Cycle rhythm",
    ),
    shortLabel: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'چرخه', en: "Cycle"),
      en: "cycle",
    ),
    icon: Icons.favorite_outline_rounded,
    color: Color(0xFFB68DD9),
    foreground: Color(0xFF75519A),
  ),
};

class MoodVisual {
  const MoodVisual(this.code, this.label, this.emoji, this.color);
  final String code;
  final String label;
  final String emoji;
  final Color color;
}

MoodVisual moodVisual(String? code) => switch (code) {
  'great' => MoodVisual(
    'great',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'عالی', en: "great"),
      en: "great",
    ),
    '😊',
    Color(0xFF55B889),
  ),
  'good' => MoodVisual(
    'good',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خوب', en: "good"),
      en: "good",
    ),
    '🙂',
    Color(0xFF8D78D5),
  ),
  'neutral' => MoodVisual(
    'neutral',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'معمولی', en: "normal"),
      en: "normal",
    ),
    '😐',
    Color(0xFFE7B650),
  ),
  'low' => MoodVisual(
    'low',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'کم‌انرژی', en: "low energy"),
      en: "low energy",
    ),
    '😔',
    Color(0xFFE78D69),
  ),
  'overwhelmed' => MoodVisual(
    'overwhelmed',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تحت فشار', en: "under pressure"),
      en: "under pressure",
    ),
    '😣',
    Color(0xFFE46178),
  ),
  _ => MoodVisual(
    'good',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ثبت نشده', en: "Not recorded"),
      en: "not registered",
    ),
    '🌸',
    Color(0xFFB68DD9),
  ),
};

class SymptomOption {
  const SymptomOption(this.code, this.label, this.icon, this.color);
  final String code;
  final String label;
  final IconData icon;
  final Color color;
}

final symptomOptions = <SymptomOption>[
  SymptomOption(
    'cramps',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'درد شکم', en: "Abdominal pain"),
      en: "Abdominal pain",
    ),
    Icons.bolt_rounded,
    Color(0xFFE76479),
  ),
  SymptomOption(
    'headache',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سردرد', en: "headache"),
      en: "headache",
    ),
    Icons.psychology_alt_rounded,
    Color(0xFF9A78D3),
  ),
  SymptomOption(
    'bloating',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'نفخ', en: "flatulence"),
      en: "flatulence",
    ),
    Icons.bubble_chart_rounded,
    Color(0xFFE3AA4E),
  ),
  SymptomOption(
    'fatigue',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خستگی', en: "tiredness"),
      en: "tiredness",
    ),
    Icons.bedtime_rounded,
    Color(0xFF8674C8),
  ),
  SymptomOption(
    'breast_tenderness',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'حساسیت سینه',
        en: "Breast tenderness",
      ),
      en: "Breast tenderness",
    ),
    Icons.favorite_outline_rounded,
    Color(0xFFE87B9D),
  ),
  SymptomOption(
    'back_pain',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'کمردرد', en: "back pain"),
      en: "back pain",
    ),
    Icons.accessibility_new_rounded,
    Color(0xFF6D9BCF),
  ),
  SymptomOption(
    'sleep_change',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغییر خواب', en: "sleep change"),
      en: "sleep change",
    ),
    Icons.nights_stay_rounded,
    Color(0xFF746CC1),
  ),
  SymptomOption(
    'appetite_change',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'تغییر اشتها',
        en: "Change in appetite",
      ),
      en: "Change in appetite",
    ),
    Icons.restaurant_rounded,
    Color(0xFFE2975D),
  ),
  SymptomOption(
    'no_symptom',
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'بدون نشانه', en: "no sign"),
      en: "no sign",
    ),
    Icons.check_circle_outline_rounded,
    Color(0xFF54A980),
  ),
];

String symptomLabel(String code) => symptomOptions
    .firstWhere(
      (item) => item.code == code,
      orElse: () => SymptomOption(
        'unknown',
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'سایر', en: "other"),
          en: "other",
        ),
        Icons.circle_outlined,
        Color(0xFF999999),
      ),
    )
    .label;

String phaseTip(WomenCyclePhase? phase, Map<String, dynamic>? log) {
  final lowEnergy = (log?['energyLevel'] as int? ?? 5) <= 2;
  if (lowEnergy) {
    return LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'امروز انرژی کمتری ثبت کردی. لازم نیست با سرعت همیشگی پیش بروی؛ کمی استراحت، آب کافی و مهربانی با خودت انتخاب خوبی است.',
        en: "You registered less energy today. You don't have to go at the usual speed; A little rest, plenty of water and being kind to yourself is a good choice.",
      ),
      en: "You registered less energy today. You don't have to go at the usual speed; A little rest, plenty of water and being kind to yourself is a good choice.",
    );
  }
  return switch (phase) {
    WomenCyclePhase.period => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ممکن است بدنت استراحت و گرمای بیشتری بخواهد. فعالیت سبک، آب کافی و توجه به دردهای غیرعادی را در اولویت بگذار.',
        en: "Your body may need more rest and warmth. Prioritize light activity, enough water and paying attention to unusual pains.",
      ),
      en: "Your body may need more rest and warmth. Prioritize light activity, enough water and paying attention to unusual pains.",
    ),
    WomenCyclePhase.follicular => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ممکن است انرژی به‌تدریج بیشتر شود. یک برنامه سبک و انعطاف‌پذیر برای روزت انتخاب کن.',
        en: "The energy may increase gradually. Choose a light and flexible schedule for your day.",
      ),
      en: "The energy may increase gradually. Choose a light and flexible schedule for your day.",
    ),
    WomenCyclePhase.fertile ||
    WomenCyclePhase.ovulation => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'این روزها فقط یک برآورد تقویمی‌اند. برای حال بهتر، خواب منظم، آب کافی و حرکت سبک را فراموش نکن.',
        en: "These days are just a calendar estimate. For a better mood, do not forget regular sleep, enough water and light movement.",
      ),
      en: "These days are just a calendar estimate. For a better mood, do not forget regular sleep, enough water and light movement.",
    ),
    WomenCyclePhase.luteal => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ریتم آرام‌تر و وعده‌های منظم می‌تواند کمک‌کننده باشد. احساساتت را بدون قضاوت ثبت کن.',
        en: "A calmer rhythm and regular meals can help. Record your feelings without judgment.",
      ),
      en: "A calmer rhythm and regular meals can help. Record your feelings without judgment.",
    ),
    WomenCyclePhase.pms => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ممکن است حساس‌تر یا خسته‌تر باشی. امروز کمی فضای بیشتر، خواب کافی و گفت‌وگوی آرام با همدمت ارزشمند است.',
        en: "You may be more sensitive or tired. Today, a little more space, enough sleep and a quiet conversation with your companion are valuable.",
      ),
      en: "You may be more sensitive or tired. Today, a little more space, enough sleep and a quiet conversation with your companion are valuable.",
    ),
    _ => LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'بدنت ریتم خودش را دارد. چند لحظه مکث کن و ببین امروز واقعاً به چه چیزی نیاز داری.',
        en: "Your body has its own rhythm. Take a moment and see what you really need today.",
      ),
      en: "Your body has its own rhythm. Take a moment and see what you really need today.",
    ),
  };
}

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
