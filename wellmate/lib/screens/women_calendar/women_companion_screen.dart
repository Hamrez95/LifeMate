import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import 'women_calendar_month_card.dart';
import 'women_calendar_screen.dart';

class WomenCompanionScreen extends StatefulWidget {
  const WomenCompanionScreen({
    super.key,
    this.onProfileChanged,
    this.companionApi,
  });

  final Future<void> Function()? onProfileChanged;
  final WomenCompanionApi? companionApi;

  @override
  State<WomenCompanionScreen> createState() => _WomenCompanionScreenState();
}

class _WomenCompanionScreenState extends State<WomenCompanionScreen> {
  late final WomenCompanionApi _companionApi =
      widget.companionApi ?? WomenCompanionApi.fromEnvironment();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _profile = const {};
  Map<String, dynamic> _currentProfile = const {};
  List<Map<String, dynamic>> _episodes = const [];
  List<Map<String, dynamic>> _dailyLogs = const [];
  List<Map<String, dynamic>> _relationships = const [];

  bool get _enabled => _profile['enabled'] == true;

  WomenCalendarEstimate? get _estimate {
    final start = DateTime.tryParse(
      _profile['lastPeriodStart']?.toString() ?? '',
    );
    if (!_enabled || start == null) return null;
    return WomenCalendarEstimate.calculate(
      lastPeriodStart: start,
      cycleLength: _profile['cycleLength'] is int
          ? _profile['cycleLength'] as int
          : 28,
      periodLength: _profile['periodLength'] is int
          ? _profile['periodLength'] as int
          : 5,
    );
  }

  Map<String, dynamic>? get _todayLog {
    final today = _dateKey(DateTime.now());
    for (final log in _dailyLogs) {
      if (log['loggedOn']?.toString() == today) return log;
    }
    return null;
  }

  Map<String, dynamic>? get _companionRelationship {
    final active = _relationships.where(
      (item) => item['status']?.toString() == 'active',
    );
    return active.isEmpty ? null : active.first;
  }

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<LifeMateApiClient>();
      final now = DateTime.now();
      final results = await Future.wait<dynamic>([
        api.getWomenCalendarProfile(),
        api.getWomenCalendarEpisodes(),
        api.getCurrentProfile(),
        api.getCareRelationships(),
        _companionApi.getDailyLogs(
          fromDate: now.subtract(const Duration(days: 89)),
          toDate: now,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as Map<String, dynamic>;
        _episodes = results[1] as List<Map<String, dynamic>>;
        _currentProfile = results[2] as Map<String, dynamic>;
        _relationships = results[3] as List<Map<String, dynamic>>;
        _dailyLogs = results[4] as List<Map<String, dynamic>>;
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == 'women_calendar_feature_disabled'
            ? 'تقویم بانوان در این نسخه فعال نیست.'
            : 'اطلاعات چرخه دریافت نشد. دوباره تلاش کنید.';
      });
    } catch (error) {
      debugPrint('Women companion dashboard load failed: $error');
      if (mounted) {
        setState(() => _error = 'اطلاعات چرخه دریافت نشد. دوباره تلاش کنید.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAdvancedManagement() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFFFFF8FC),
          appBar: AppBar(
            title: const Text('تقویم و تنظیمات چرخه'),
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

  Future<void> _editTodayLog() async {
    final current = _todayLog;
    final draft = await showModalBottomSheet<WomenDailyLogDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DailyCheckInSheet(existing: current),
    );
    if (draft == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _companionApi.saveDailyLog(
        version: current?['version'] is int ? current!['version'] as int : 0,
        loggedOn: DateTime.now(),
        mood: draft.mood,
        energyLevel: draft.energyLevel,
        painLevel: draft.painLevel,
        symptoms: draft.symptoms,
        privateNotes: draft.privateNotes,
        shareSummaryWithCompanion: draft.shareWithCompanion,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            draft.shareWithCompanion
                ? 'حال امروز ثبت شد؛ فقط خلاصه انتخاب‌شده با همدمت به اشتراک گذاشته می‌شود.'
                : 'حال امروز به‌صورت خصوصی ثبت شد.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'stale_women_calendar_daily_log'
                ? 'ثبت امروز تغییر کرده بود؛ اطلاعات تازه شد.'
                : 'ثبت حال امروز انجام نشد.',
          ),
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
            _CompanionHero(
              currentProfile: _currentProfile,
              relationship: _companionRelationship,
            ),
            const SizedBox(height: 14),
            _CycleOverviewCard(
              estimate: estimate,
              onOpenCalendar: _openAdvancedManagement,
            ),
            const SizedBox(height: 14),
            _DailyCheckInCard(
              log: _todayLog,
              saving: _saving,
              onEdit: _editTodayLog,
            ),
            const SizedBox(height: 14),
            _DailyTipCard(estimate: estimate, log: _todayLog),
            const SizedBox(height: 14),
            WomenCalendarMonthCard(episodes: _episodes, estimate: estimate),
            const SizedBox(height: 14),
            _FourteenDayStrip(estimate: estimate),
            const SizedBox(height: 14),
            _ReportsCard(episodes: _episodes, logs: _dailyLogs),
            const SizedBox(height: 14),
            _ReminderAndSettingsCard(
              profile: _profile,
              onOpenSettings: _openAdvancedManagement,
            ),
            const SizedBox(height: 14),
            const _MedicalSafetyCard(),
          ],
        ),
      ),
    );
  }
}

class _CompanionHero extends StatelessWidget {
  const _CompanionHero({
    required this.currentProfile,
    required this.relationship,
  });

  final Map<String, dynamic> currentProfile;
  final Map<String, dynamic>? relationship;

  @override
  Widget build(BuildContext context) {
    final api = context.read<LifeMateApiClient>();
    final name = relationship?['caregiverDisplayName']?.toString().trim();
    final companionName = name == null || name.isEmpty ? 'همدم من' : name;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFF7E8FF), Color(0xFFFFEAF2), Color(0xFFFFF7EE)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x159D65C5),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.favorite_rounded, color: Color(0xFFE7598B), size: 19),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'سلام عزیزِ من',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                'امروز چطوری؟',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    LifeMateCurrentUserAvatar(apiClient: api, radius: 34),
                    const SizedBox(height: 6),
                    Text(
                      currentProfile['displayName']?.toString() ?? 'من',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 58,
                  height: 32,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 2,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFE69AC6), Color(0xFFAB8BE7)],
                          ),
                        ),
                      ),
                      const CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.white,
                        child: Icon(
                          Icons.favorite_rounded,
                          size: 15,
                          color: Color(0xFFD66AA1),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    const LifeMateProfileAvatar(
                      avatarKey: 'caregiver_teal',
                      radius: 34,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      companionName,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            relationship == null
                ? 'هر زمان آماده بودی، می‌توانی یک همدم قابل اعتماد را با رضایت خودت متصل کنی.'
                : '$companionName فقط خلاصه‌هایی را می‌بیند که خودت برای اشتراک انتخاب کرده‌ای.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              height: 1.55,
              color: Color(0xFF735C77),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CycleOverviewCard extends StatelessWidget {
  const _CycleOverviewCard({
    required this.estimate,
    required this.onOpenCalendar,
  });

  final WomenCalendarEstimate? estimate;
  final VoidCallback onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final value = estimate;
    final visual = phaseVisual(value?.detailedPhase);
    return _PastelCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 330;
          final ring = _CycleRing(estimate: value, size: narrow ? 142 : 164);
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                visual.label,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: visual.foreground,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                value == null
                    ? 'برای نمایش چرخه، اطلاعات پایه را کامل کن.'
                    : 'روز ${localizeDigits(context, value.cycleDay)} از چرخه ${localizeDigits(context, value.cycleLength)} روزه',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              if (value != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${localizeDigits(context, value.daysUntilNextPeriod)} روز تا شروع تخمینی دوره بعدی',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF866A80),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onOpenCalendar,
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: const Text('تقویم و ثبت دوره'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD85586),
                  side: const BorderSide(color: Color(0xFFF3AFC6)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          );
          if (narrow) {
            return Column(
              children: [
                ring,
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerRight, child: details),
              ],
            );
          }
          return Row(
            children: [
              ring,
              const SizedBox(width: 18),
              Expanded(child: details),
            ],
          );
        },
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
                      : 'روز ${localizeDigits(context, value.cycleDay)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value == null
                      ? 'چرخه'
                      : 'از ${localizeDigits(context, value.cycleLength)} روز',
                  style: const TextStyle(
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

    final sections = <(int, Color)>[
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
            title: 'حال و احساس امروز',
            subtitle: log == null
                ? 'امروز چه احساسی داری؟'
                : 'ثبت امروزت محفوظ است.',
            action: TextButton(
              onPressed: saving ? null : onEdit,
              child: Text(log == null ? 'ثبت حال' : 'ویرایش'),
            ),
          ),
          const SizedBox(height: 12),
          if (log == null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _MoodPreview(emoji: '😊', label: 'عالی'),
                _MoodPreview(emoji: '🙂', label: 'خوب'),
                _MoodPreview(emoji: '😐', label: 'معمولی'),
                _MoodPreview(emoji: '😔', label: 'کم‌انرژی'),
                _MoodPreview(emoji: '😣', label: 'تحت فشار'),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: mood.color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Text(mood.emoji, style: const TextStyle(fontSize: 30)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mood.label,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'انرژی ${localizeDigits(context, log!['energyLevel'] ?? '—')} از ۵ • درد ${localizeDigits(context, log!['painLevel'] ?? '—')} از ۵',
                          style: const TextStyle(
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
                        ? const Color(0xFFE55A8B)
                        : const Color(0xFF8A8791),
                  ),
                ],
              ),
            ),
          if (saving) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 2),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            visual.color.withValues(alpha: 0.15),
            const Color(0xFFFFF3F7),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.spa_rounded, color: visual.color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'نکته امروز',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: const TextStyle(height: 1.7, color: Color(0xFF685B69)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
          const _SectionTitle(
            title: '۱۴ روز پیش رو',
            subtitle: 'یک نگاه آرام به ریتم تخمینی چرخه',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 108,
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
                final phase = estimate?.phaseForDate(date);
                final visual = phaseVisual(phase);
                return Container(
                  width: 68,
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 6,
                  ),
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
                        index == 0 ? 'امروز' : localizeDigits(context, index),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Icon(visual.icon, color: visual.color, size: 21),
                      const SizedBox(height: 6),
                      Text(
                        visual.shortLabel,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 8.5, height: 1.2),
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
          const _SectionTitle(
            title: 'گزارش‌های من',
            subtitle: 'خلاصه ساده از ثبت‌های خودت، بدون تشخیص پزشکی',
          ),
          const SizedBox(height: 12),
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
                    color: const Color(0xFFE65F8C),
                  ),
                  _ReportTile(
                    width: width,
                    icon: Icons.bubble_chart_rounded,
                    label: 'نشانه پرتکرار',
                    value: commonSymptom == null
                        ? 'ثبت ناکافی'
                        : symptomLabel(commonSymptom),
                    color: const Color(0xFF9C71D2),
                  ),
                  _ReportTile(
                    width: width,
                    icon: Icons.bolt_rounded,
                    label: 'انرژی',
                    value: averageEnergy == null
                        ? 'ثبت ناکافی'
                        : '${localizeDigits(context, averageEnergy.toStringAsFixed(1))} از ۵',
                    color: const Color(0xFFF0A643),
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
          const _SectionTitle(
            title: 'یادآوری‌ها و تنظیمات',
            subtitle: 'کنترل چرخه همیشه دست خودت است.',
          ),
          const SizedBox(height: 10),
          _InfoLine(
            icon: Icons.notifications_active_rounded,
            title: 'یادآوری نزدیک‌شدن دوره',
            value: profile['remindersEnabled'] == false
                ? 'خاموش'
                : 'فعال و خصوصی',
          ),
          _InfoLine(
            icon: Icons.edit_calendar_rounded,
            title: 'آخرین شروع ثبت‌شده',
            value: lastStart == null
                ? 'ثبت نشده'
                : formatAppDate(context, lastStart),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('تنظیمات و مدیریت ثبت‌ها'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD75C8D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
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
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E8),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFFFE1A5)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.health_and_safety_outlined, color: Color(0xFFB97818)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'چرخه و فازها تخمینی‌اند و برای تشخیص، اثبات تخمک‌گذاری یا پیشگیری از بارداری طراحی نشده‌اند. در درد شدید، خون‌ریزی غیرعادی یا نگرانی پزشکی با پزشک تماس بگیر.',
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
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      decoration: const BoxDecoration(
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
                  color: const Color(0xFFE3DCE5),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'حال امروز من',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'هر چیزی که ثبت می‌کنی ابتدا خصوصی است.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
            ),
            const SizedBox(height: 18),
            const Text(
              'حال روحی',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const ['great', 'good', 'neutral', 'low', 'overwhelmed']
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
            const SizedBox(height: 18),
            _LevelSlider(
              title: 'انرژی امروز',
              value: _energy,
              min: 1,
              max: 5,
              color: const Color(0xFFF0A643),
              onChanged: (value) => setState(() => _energy = value),
            ),
            _LevelSlider(
              title: 'شدت درد',
              value: _pain,
              min: 0,
              max: 5,
              color: const Color(0xFFE46378),
              onChanged: (value) => setState(() => _pain = value),
            ),
            const SizedBox(height: 8),
            const Text(
              'نشانه‌ها',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 15),
            TextField(
              controller: _notes,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'یادداشت خصوصی',
                hintText: 'حس، خواب یا اتفاق امروز را برای خودت بنویس...',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _share,
                onChanged: (value) => setState(() => _share = value),
                title: const Text(
                  'اشتراک خلاصه با همدم',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: const Text(
                  'فقط حال، انرژی، شدت درد و نشانه‌های انتخابی دیده می‌شود؛ یادداشت خصوصی هرگز به اشتراک گذاشته نمی‌شود.',
                  style: TextStyle(fontSize: 10.5, height: 1.5),
                ),
                activeThumbColor: const Color(0xFFD75C8D),
              ),
            ),
            const SizedBox(height: 14),
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
                icon: const Icon(Icons.favorite_rounded),
                label: const Text('ثبت حال امروز'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD75C8D),
                  padding: const EdgeInsets.symmetric(vertical: 15),
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
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            '${localizeDigits(context, value)} از ${localizeDigits(context, max)}',
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
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFFFFF4F9), Color(0xFFF5F0FF)]),
    ),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: _PastelCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.favorite_rounded,
                size: 56,
                color: Color(0xFFD85B8C),
              ),
              const SizedBox(height: 14),
              const Text(
                'فضای شخصی چرخه تو',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'برای دیدن ریتم چرخه، حال روزانه و گزارش‌های خصوصی، اطلاعات پایه را کامل کن.',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.6, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onOpenSettings,
                child: const Text('راه‌اندازی تقویم بانوان'),
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
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 52,
            color: Color(0xFFD75C8D),
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton(onPressed: onRetry, child: const Text('تلاش دوباره')),
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
  WomenCyclePhase.period => const PhaseVisual(
    label: 'فاز قاعدگی',
    shortLabel: 'قاعدگی',
    icon: Icons.water_drop_rounded,
    color: Color(0xFFF15D7B),
    foreground: Color(0xFF9F2847),
  ),
  WomenCyclePhase.follicular => const PhaseVisual(
    label: 'فاز فولیکولار',
    shortLabel: 'فولیکولار',
    icon: Icons.spa_rounded,
    color: Color(0xFFB48BE1),
    foreground: Color(0xFF6F439F),
  ),
  WomenCyclePhase.fertile => const PhaseVisual(
    label: 'پنجره باروری تخمینی',
    shortLabel: 'باروری',
    icon: Icons.local_florist_rounded,
    color: Color(0xFF57C5B5),
    foreground: Color(0xFF247D72),
  ),
  WomenCyclePhase.ovulation => const PhaseVisual(
    label: 'روز تخمک‌گذاری تخمینی',
    shortLabel: 'تخمک‌گذاری',
    icon: Icons.brightness_5_rounded,
    color: Color(0xFF55A8E8),
    foreground: Color(0xFF286A9D),
  ),
  WomenCyclePhase.luteal => const PhaseVisual(
    label: 'فاز لوتئال',
    shortLabel: 'لوتئال',
    icon: Icons.wb_twilight_rounded,
    color: Color(0xFFF3B651),
    foreground: Color(0xFF946517),
  ),
  WomenCyclePhase.pms => const PhaseVisual(
    label: 'روزهای پیش از دوره',
    shortLabel: 'PMS',
    icon: Icons.nightlight_round,
    color: Color(0xFFE88973),
    foreground: Color(0xFF9D4938),
  ),
  _ => const PhaseVisual(
    label: 'ریتم چرخه',
    shortLabel: 'چرخه',
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
  'great' => const MoodVisual('great', 'عالی', '😊', Color(0xFF55B889)),
  'good' => const MoodVisual('good', 'خوب', '🙂', Color(0xFF8D78D5)),
  'neutral' => const MoodVisual('neutral', 'معمولی', '😐', Color(0xFFE7B650)),
  'low' => const MoodVisual('low', 'کم‌انرژی', '😔', Color(0xFFE78D69)),
  'overwhelmed' => const MoodVisual(
    'overwhelmed',
    'تحت فشار',
    '😣',
    Color(0xFFE46178),
  ),
  _ => const MoodVisual('good', 'ثبت نشده', '🌸', Color(0xFFB68DD9)),
};

class SymptomOption {
  const SymptomOption(this.code, this.label, this.icon, this.color);
  final String code;
  final String label;
  final IconData icon;
  final Color color;
}

const symptomOptions = <SymptomOption>[
  SymptomOption('cramps', 'درد شکم', Icons.bolt_rounded, Color(0xFFE76479)),
  SymptomOption(
    'headache',
    'سردرد',
    Icons.psychology_alt_rounded,
    Color(0xFF9A78D3),
  ),
  SymptomOption(
    'bloating',
    'نفخ',
    Icons.bubble_chart_rounded,
    Color(0xFFE3AA4E),
  ),
  SymptomOption('fatigue', 'خستگی', Icons.bedtime_rounded, Color(0xFF8674C8)),
  SymptomOption(
    'breast_tenderness',
    'حساسیت سینه',
    Icons.favorite_outline_rounded,
    Color(0xFFE87B9D),
  ),
  SymptomOption(
    'back_pain',
    'کمردرد',
    Icons.accessibility_new_rounded,
    Color(0xFF6D9BCF),
  ),
  SymptomOption(
    'sleep_change',
    'تغییر خواب',
    Icons.nights_stay_rounded,
    Color(0xFF746CC1),
  ),
  SymptomOption(
    'appetite_change',
    'تغییر اشتها',
    Icons.restaurant_rounded,
    Color(0xFFE2975D),
  ),
  SymptomOption(
    'no_symptom',
    'بدون نشانه',
    Icons.check_circle_outline_rounded,
    Color(0xFF54A980),
  ),
];

String symptomLabel(String code) => symptomOptions
    .firstWhere(
      (item) => item.code == code,
      orElse: () => const SymptomOption(
        'unknown',
        'سایر',
        Icons.circle_outlined,
        Color(0xFF999999),
      ),
    )
    .label;

String phaseTip(WomenCyclePhase? phase, Map<String, dynamic>? log) {
  final lowEnergy = (log?['energyLevel'] as int? ?? 5) <= 2;
  if (lowEnergy) {
    return 'امروز انرژی کمتری ثبت کردی. لازم نیست با سرعت همیشگی پیش بروی؛ کمی استراحت، آب کافی و مهربانی با خودت انتخاب خوبی است.';
  }
  return switch (phase) {
    WomenCyclePhase.period =>
      'ممکن است بدنت استراحت و گرمای بیشتری بخواهد. فعالیت سبک، آب کافی و توجه به دردهای غیرعادی را در اولویت بگذار.',
    WomenCyclePhase.follicular =>
      'ممکن است انرژی به‌تدریج بیشتر شود. یک برنامه سبک و انعطاف‌پذیر برای روزت انتخاب کن.',
    WomenCyclePhase.fertile || WomenCyclePhase.ovulation =>
      'این روزها فقط یک برآورد تقویمی‌اند. برای حال بهتر، خواب منظم، آب کافی و حرکت سبک را فراموش نکن.',
    WomenCyclePhase.luteal =>
      'ریتم آرام‌تر و وعده‌های منظم می‌تواند کمک‌کننده باشد. احساساتت را بدون قضاوت ثبت کن.',
    WomenCyclePhase.pms =>
      'ممکن است حساس‌تر یا خسته‌تر باشی. امروز کمی فضای بیشتر، خواب کافی و گفت‌وگوی آرام با همدمت ارزشمند است.',
    _ =>
      'بدنت ریتم خودش را دارد. چند لحظه مکث کن و ببین امروز واقعاً به چه چیزی نیاز داری.',
  };
}

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
