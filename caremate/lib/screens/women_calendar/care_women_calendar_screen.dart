import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/persian_date_utils.dart';

const _rose = Color(0xFFF06494);
const _lilac = Color(0xFF9564D5);
const _lavender = Color(0xFFF0E7FF);
const _peach = Color(0xFFF4AF78);
const _ink = Color(0xFF2A2540);

class CareWomenCalendarScreen extends StatefulWidget {
  const CareWomenCalendarScreen({
    super.key,
    required this.patientUserId,
    required this.patientName,
  });

  final String patientUserId;
  final String patientName;

  @override
  State<CareWomenCalendarScreen> createState() =>
      _CareWomenCalendarScreenState();
}

class _CareWomenCalendarScreenState extends State<CareWomenCalendarScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _summary = const {};
  Map<String, dynamic> _currentProfile = const {};
  List<Map<String, dynamic>> _doses = const [];
  List<Map<String, dynamic>> _careEvents = const [];

  WomenCalendarEstimate? get _estimate {
    final profile = _summary['profile'] as Map<String, dynamic>? ?? const {};
    final start = DateTime.tryParse(
      profile['lastPeriodStart']?.toString() ?? '',
    );
    final cycleLength = profile['cycleLength'] as int?;
    final periodLength = profile['periodLength'] as int?;
    if (start == null || cycleLength == null || periodLength == null) {
      return null;
    }
    return WomenCalendarEstimate.calculate(
      lastPeriodStart: start,
      cycleLength: cycleLength,
      periodLength: periodLength,
    );
  }

  Map<String, dynamic>? get _sharedDailySummary =>
      _summary['sharedDailySummary'] as Map<String, dynamic>?;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day);
      final to = from.add(const Duration(days: 7));
      final api = context.read<LifeMateApiClient>();
      final results = await Future.wait<dynamic>([
        api.getCareRecipientWomenCalendar(
          patientUserId: widget.patientUserId,
        ),
        api.getCurrentProfile(),
        api.getCareRecipientDoseOccurrences(
          patientUserId: widget.patientUserId,
          fromDate: from,
          toDate: to,
        ),
        api.getCareRecipientCareEvents(
          patientUserId: widget.patientUserId,
          fromDate: from,
          toDate: to,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _currentProfile = results[1] as Map<String, dynamic>;
        _doses = results[2] as List<Map<String, dynamic>>;
        _careEvents = results[3] as List<Map<String, dynamic>>;
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          'women_calendar_access_denied' =>
            'دسترسی چرخه برای شما فعال نیست. فقط صاحب حساب می‌تواند این دسترسی را روشن کند.',
          'women_calendar_not_active' =>
            'تقویم بانوان برای ${widget.patientName} فعال نیست.',
          'women_calendar_feature_disabled' =>
            'این قابلیت در Build فعلی فعال نیست.',
          _ => 'وضعیت چرخه دریافت نشد.',
        };
      });
    } catch (error) {
      debugPrint('Care companion cycle load failed: $error');
      if (mounted) setState(() => _error = 'وضعیت چرخه دریافت نشد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recordAction(_SupportAction action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context
          .read<LifeMateApiClient>()
          .recordCareRecipientWomenSupportAction(
            patientUserId: widget.patientUserId,
            actionType: action.type,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${action.confirmation} ثبت شد 💜'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'women_calendar_access_denied'
                ? 'دسترسی این بخش تغییر کرده است.'
                : 'ثبت حمایت انجام نشد؛ دوباره تلاش کنید.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF8FF),
      appBar: AppBar(
        toolbarHeight: 66,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'همدل من 💜',
              style: TextStyle(
                color: _ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'کنار ${widget.patientName}، با احترام به حریم خصوصی',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _lilac))
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _load)
          : _CompanionBackground(
              child: RefreshIndicator(
                onRefresh: _load,
                color: _lilac,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                  children: [
                    _PairHero(
                      apiClient: context.read<LifeMateApiClient>(),
                      caregiverName:
                          _currentProfile['displayName']?.toString() ?? 'همدل',
                      patientName: widget.patientName,
                    ),
                    const SizedBox(height: 14),
                    _CycleAndMoodCard(
                      patientName: widget.patientName,
                      estimate: _estimate,
                      sharedDailySummary: _sharedDailySummary,
                    ),
                    const SizedBox(height: 14),
                    _TodayStatusCard(
                      patientName: widget.patientName,
                      doses: _doses,
                      careEvents: _careEvents,
                      summary: _summary,
                    ),
                    const SizedBox(height: 14),
                    _ImportantRemindersCard(
                      doses: _doses,
                      careEvents: _careEvents,
                    ),
                    const SizedBox(height: 14),
                    _SupportActionsCard(
                      saving: _saving,
                      onAction: _recordAction,
                    ),
                    const SizedBox(height: 14),
                    _CompanionMessageCard(
                      patientName: widget.patientName,
                      estimate: _estimate,
                      sharedDailySummary: _sharedDailySummary,
                    ),
                    const SizedBox(height: 14),
                    _RecentSupportCard(summary: _summary),
                    const SizedBox(height: 14),
                    const _PrivacyNotice(),
                  ],
                ),
              ),
            ),
    );
  }
}

class _CompanionBackground extends StatelessWidget {
  const _CompanionBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Color(0xFFFFF8FC),
                Color(0xFFF6EFFF),
                Color(0xFFFFF9F5),
              ],
            ),
          ),
        ),
      ),
      Positioned(
        top: -60,
        left: -80,
        child: _Glow(color: _lilac.withValues(alpha: 0.12), size: 240),
      ),
      Positioned(
        top: 300,
        right: -100,
        child: _Glow(color: _rose.withValues(alpha: 0.10), size: 270),
      ),
      child,
    ],
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.child, this.gradient, this.color});

  final Widget child;
  final Gradient? gradient;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: gradient == null ? (color ?? Colors.white).withValues(alpha: 0.95) : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withValues(alpha: 0.82)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x112E1C47),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: child,
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle, required this.icon});

  final String title;
  final String? subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _lavender,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(icon, color: _lilac, size: 21),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 10.5,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _PairHero extends StatelessWidget {
  const _PairHero({
    required this.apiClient,
    required this.caregiverName,
    required this.patientName,
  });

  final LifeMateApiClient apiClient;
  final String caregiverName;
  final String patientName;

  @override
  Widget build(BuildContext context) => _SoftCard(
    gradient: const LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [Color(0xFFF2E5FF), Color(0xFFFFEAF3)],
    ),
    child: Column(
      children: [
        Text(
          '$caregiverName، همدل $patientName هستی 💜',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'فهمیدن حال همسر یعنی مراقبت بدون کنترل؛ فقط اطلاعاتی را می‌بینی که خودش اجازه داده.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF725D82),
            fontSize: 10.5,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LifeMateCurrentUserAvatar(apiClient: apiClient, radius: 36),
            Transform.translate(
              offset: const Offset(-7, 0),
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: _rose,
                  size: 21,
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(-14, 0),
              child: const LifeMateProfileAvatar(
                avatarKey: 'person_purple',
                radius: 36,
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sync_rounded, size: 16, color: _lilac),
            SizedBox(width: 6),
            Text(
              'اطلاعات مجاز با WellMate همگام است',
              style: TextStyle(
                color: Color(0xFF78658A),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PhaseVisual {
  const _PhaseVisual(this.label, this.color, this.icon, this.tip);
  final String label;
  final Color color;
  final IconData icon;
  final String tip;
}

_PhaseVisual _phaseVisual(WomenCyclePhase? phase) => switch (phase) {
  WomenCyclePhase.period => const _PhaseVisual(
    'فاز قاعدگی',
    Color(0xFFF05F78),
    Icons.water_drop_rounded,
    'ممکنه امروز استراحت، گرما و فشار کمتر کمک‌کننده باشد.',
  ),
  WomenCyclePhase.follicular => const _PhaseVisual(
    'فاز فولیکولار',
    Color(0xFFB889E8),
    Icons.auto_awesome_rounded,
    'ممکنه انرژی و تمرکز به‌تدریج بیشتر شود.',
  ),
  WomenCyclePhase.fertile => const _PhaseVisual(
    'پنجره باروری تخمینی',
    Color(0xFF6F8DEB),
    Icons.spa_rounded,
    'این فقط تخمین تقویمی است و تجربه هر بدن متفاوت است.',
  ),
  WomenCyclePhase.ovulation => const _PhaseVisual(
    'تخمک‌گذاری تخمینی',
    Color(0xFF8B62D5),
    Icons.local_florist_rounded,
    'این روز تخمینی است و اثبات پزشکی تخمک‌گذاری نیست.',
  ),
  WomenCyclePhase.luteal => const _PhaseVisual(
    'فاز لوتئال',
    Color(0xFFF3B35C),
    Icons.wb_sunny_rounded,
    'در روزهای آینده شاید فشار کمتر و خواب منظم مفید باشد.',
  ),
  WomenCyclePhase.pms => const _PhaseVisual(
    'PMS تخمینی',
    Color(0xFFE78374),
    Icons.favorite_rounded,
    'ممکنه حساسیت یا خستگی بیشتر شود؛ با مهربانی و بدون قضاوت کنارش باش.',
  ),
  null => const _PhaseVisual(
    'اطلاعات ناکافی',
    _lilac,
    Icons.calendar_month_rounded,
    'صاحب حساب هنوز اطلاعات پایه چرخه را کامل نکرده است.',
  ),
};

List<WomenCycleRingSegment> _ringSegments(WomenCalendarEstimate? estimate) {
  if (estimate == null) {
    return const [
      WomenCycleRingSegment(color: _rose, weight: 5),
      WomenCycleRingSegment(color: _lilac, weight: 8),
      WomenCycleRingSegment(color: Color(0xFF6F8DEB), weight: 5),
      WomenCycleRingSegment(color: _peach, weight: 10),
    ];
  }
  final follicular = math.max(
    1,
    estimate.fertileWindowStartDay - estimate.periodLength - 1,
  );
  final fertile = math.max(
    1,
    estimate.fertileWindowEndDay - estimate.fertileWindowStartDay,
  );
  final luteal = math.max(
    1,
    estimate.pmsStartDay - estimate.fertileWindowEndDay - 1,
  );
  final pms = math.max(1, estimate.cycleLength - estimate.pmsStartDay + 1);
  return [
    WomenCycleRingSegment(
      color: const Color(0xFFF05F78),
      weight: estimate.periodLength.toDouble(),
    ),
    WomenCycleRingSegment(
      color: const Color(0xFFB889E8),
      weight: follicular.toDouble(),
    ),
    WomenCycleRingSegment(
      color: const Color(0xFF6F8DEB),
      weight: fertile.toDouble(),
    ),
    const WomenCycleRingSegment(color: Color(0xFF8B62D5), weight: 1),
    WomenCycleRingSegment(
      color: const Color(0xFFF3B35C),
      weight: luteal.toDouble(),
    ),
    WomenCycleRingSegment(
      color: const Color(0xFFE78374),
      weight: pms.toDouble(),
    ),
  ];
}

class _CycleAndMoodCard extends StatelessWidget {
  const _CycleAndMoodCard({
    required this.patientName,
    required this.estimate,
    required this.sharedDailySummary,
  });

  final String patientName;
  final WomenCalendarEstimate? estimate;
  final Map<String, dynamic>? sharedDailySummary;

  @override
  Widget build(BuildContext context) {
    final visual = _phaseVisual(estimate?.detailedPhase);
    final progress = estimate == null
        ? 0.2
        : ((estimate!.cycleDay - 1) / estimate!.cycleLength)
              .clamp(0.0, 1.0)
              .toDouble();
    final mood = sharedDailySummary?['mood']?.toString().toLowerCase();
    final energy = (sharedDailySummary?['energy'] as num?)?.round();
    final support = sharedDailySummary?['supportNeed']?.toString().toLowerCase();
    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: patientName,
            subtitle: 'خلاصه‌ای که با رضایت خودش به اشتراک گذاشته شده',
            icon: Icons.favorite_outline_rounded,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 330;
              final ring = WomenCycleRing(
                segments: _ringSegments(estimate),
                progress: progress,
                size: compact ? 144 : 158,
                strokeWidth: 12,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      estimate == null
                          ? '—'
                          : localizeDigits(context, estimate!.cycleDay),
                      style: TextStyle(
                        color: visual.color,
                        fontSize: 29,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      estimate == null
                          ? 'روز چرخه'
                          : 'از ${localizeDigits(context, estimate!.cycleLength)} روز',
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              );
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(visual.icon, color: visual.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          visual.label,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    visual.tip,
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 10.5,
                      height: 1.55,
                    ),
                  ),
                  if (estimate != null) ...[
                    const SizedBox(height: 9),
                    Text(
                      '${localizeDigits(context, estimate!.daysUntilNextPeriod)} روز تا دوره بعدی',
                      style: TextStyle(
                        color: visual.color,
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              );
              return compact
                  ? Column(children: [ring, const SizedBox(height: 16), details])
                  : Row(
                      children: [
                        ring,
                        const SizedBox(width: 16),
                        Expanded(child: details),
                      ],
                    );
            },
          ),
          const SizedBox(height: 16),
          if (sharedDailySummary == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F5FA),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: _lilac),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'حال روزانه خصوصی است یا امروز هنوز ثبت نشده. نیازی به پرس‌وجوی مداوم نیست.',
                      style: TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 10.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < 330
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 16) / 3;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SharedMetric(
                      width: width,
                      label: 'خلق‌وخو',
                      value: _moodLabel(mood),
                      icon: Icons.emoji_emotions_outlined,
                      color: _rose,
                    ),
                    _SharedMetric(
                      width: width,
                      label: 'انرژی',
                      value: _energyLabel(energy),
                      icon: Icons.bolt_rounded,
                      color: _peach,
                    ),
                    _SharedMetric(
                      width: width,
                      label: 'نیاز امروز',
                      value: _supportLabel(support),
                      icon: Icons.volunteer_activism_outlined,
                      color: _lilac,
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

class _SharedMetric extends StatelessWidget {
  const _SharedMetric({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 8.5,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TodayStatusCard extends StatelessWidget {
  const _TodayStatusCard({
    required this.patientName,
    required this.doses,
    required this.careEvents,
    required this.summary,
  });

  final String patientName;
  final List<Map<String, dynamic>> doses;
  final List<Map<String, dynamic>> careEvents;
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayDoses = doses.where((dose) {
      final date = DateTime.tryParse(dose['scheduledLocalDate']?.toString() ?? '');
      return date != null && _sameDay(date, today);
    }).toList();
    final missed = todayDoses
        .where((dose) => {'missed', 'skipped'}.contains(dose['status']?.toString()))
        .length;
    final taken = todayDoses
        .where((dose) => dose['status']?.toString() == 'taken')
        .length;
    final todayEvents = careEvents.where((event) {
      final date = DateTime.tryParse(event['scheduledLocalDate']?.toString() ?? '');
      return date != null && _sameDay(date, today);
    }).length;
    final supportActions =
        (_summaryList(summary, 'supportActions')).where((action) {
          final date = DateTime.tryParse(action['performedAtUtc']?.toString() ?? '')
              ?.toLocal();
          return date != null && _sameDay(date, today);
        }).length;

    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'وضعیت امروز',
            subtitle: 'اطلاعات واقعی برنامه و حمایت‌های ثبت‌شده برای $patientName',
            icon: Icons.today_rounded,
          ),
          const SizedBox(height: 14),
          _StatusRow(
            icon: Icons.medication_outlined,
            color: missed > 0 ? Colors.red.shade500 : const Color(0xFF5BAA7B),
            title: 'داروها',
            value: missed > 0
                ? '${localizeDigits(context, missed)} مورد انجام‌نشده'
                : '${localizeDigits(context, taken)} مصرف ثبت‌شده',
          ),
          const SizedBox(height: 8),
          _StatusRow(
            icon: Icons.event_available_outlined,
            color: const Color(0xFF6F8DEB),
            title: 'ویزیت و تزریق',
            value: '${localizeDigits(context, todayEvents)} برنامه امروز',
          ),
          const SizedBox(height: 8),
          _StatusRow(
            icon: Icons.favorite_outline_rounded,
            color: _rose,
            title: 'حمایت تو',
            value: '${localizeDigits(context, supportActions)} مورد ثبت‌شده امروز',
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(17),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ImportantRemindersCard extends StatelessWidget {
  const _ImportantRemindersCard({
    required this.doses,
    required this.careEvents,
  });

  final List<Map<String, dynamic>> doses;
  final List<Map<String, dynamic>> careEvents;

  @override
  Widget build(BuildContext context) {
    final reminders = <_ReminderItem>[
      ...doses
          .where((dose) => dose['status']?.toString() == 'scheduled')
          .map(
            (dose) => _ReminderItem(
              title: dose['medicationName']?.toString() ?? 'دارو',
              subtitle: dose['doseText']?.toString() ?? '',
              scheduled: _scheduledDateTime(dose),
              icon: Icons.medication_rounded,
              color: _rose,
            ),
          ),
      ...careEvents
          .where((event) => event['status']?.toString() == 'scheduled')
          .map((event) {
            final injection =
                event['eventType']?.toString().toLowerCase() == 'injection';
            return _ReminderItem(
              title:
                  event['title']?.toString() ??
                  (injection ? 'تزریق' : 'ویزیت'),
              subtitle: event['centerName']?.toString() ?? '',
              scheduled: _scheduledDateTime(event),
              icon: injection
                  ? Icons.vaccines_rounded
                  : Icons.medical_services_rounded,
              color: injection ? _peach : const Color(0xFF6F8DEB),
            );
          }),
    ]..sort((a, b) => a.scheduled.compareTo(b.scheduled));

    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'یادآوری‌های مهم',
            subtitle: 'برنامه‌های واقعی هفت روز آینده',
            icon: Icons.notifications_active_outlined,
          ),
          const SizedBox(height: 13),
          if (reminders.isEmpty)
            const _EmptyInline(
              icon: Icons.event_available_rounded,
              text: 'برنامه نزدیکِ انجام‌نشده‌ای وجود ندارد.',
            )
          else
            ...reminders.take(4).map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 39,
                        height: 39,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(item.icon, color: item.color, size: 21),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            if (item.subtitle.trim().isNotEmpty)
                              Text(
                                item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.secondaryText,
                                  fontSize: 9.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${formatAppDate(context, item.scheduled, includeWeekday: false)}\n${_timeLabel(context, item.scheduled)}',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: item.color,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReminderItem {
  const _ReminderItem({
    required this.title,
    required this.subtitle,
    required this.scheduled,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final DateTime scheduled;
  final IconData icon;
  final Color color;
}

class _SupportAction {
  const _SupportAction({
    required this.type,
    required this.label,
    required this.confirmation,
    required this.icon,
    required this.color,
  });

  final String type;
  final String label;
  final String confirmation;
  final IconData icon;
  final Color color;
}

const _supportActions = <_SupportAction>[
  _SupportAction(
    type: 'message',
    label: 'یک پیام مهربان',
    confirmation: 'تصمیم برای پیام مهربان',
    icon: Icons.chat_bubble_outline_rounded,
    color: _lilac,
  ),
  _SupportAction(
    type: 'hug',
    label: 'فقط کنارش باش',
    confirmation: 'کنارش‌بودن',
    icon: Icons.favorite_border_rounded,
    color: _rose,
  ),
  _SupportAction(
    type: 'walk',
    label: 'پیاده‌روی کوتاه',
    confirmation: 'پیشنهاد پیاده‌روی',
    icon: Icons.directions_walk_rounded,
    color: Color(0xFF55A77A),
  ),
  _SupportAction(
    type: 'tea',
    label: 'چای یا نوشیدنی گرم',
    confirmation: 'آماده‌کردن نوشیدنی گرم',
    icon: Icons.local_cafe_outlined,
    color: _peach,
  ),
  _SupportAction(
    type: 'rest',
    label: 'زمان استراحت',
    confirmation: 'فراهم‌کردن استراحت',
    icon: Icons.bedtime_outlined,
    color: Color(0xFF7772D7),
  ),
  _SupportAction(
    type: 'warmth',
    label: 'کیسه آب گرم',
    confirmation: 'آماده‌کردن گرما',
    icon: Icons.device_thermostat_rounded,
    color: Color(0xFFE58970),
  ),
  _SupportAction(
    type: 'chores',
    label: 'کمک در کارهای خانه',
    confirmation: 'کمک در کارهای خانه',
    icon: Icons.home_work_outlined,
    color: Color(0xFF5BAA7B),
  ),
  _SupportAction(
    type: 'hydration',
    label: 'آب و نوشیدنی',
    confirmation: 'آماده‌کردن آب و نوشیدنی',
    icon: Icons.local_drink_outlined,
    color: Color(0xFF4C9BE8),
  ),
];

class _SupportActionsCard extends StatelessWidget {
  const _SupportActionsCard({required this.saving, required this.onAction});

  final bool saving;
  final Future<void> Function(_SupportAction action) onAction;

  @override
  Widget build(BuildContext context) => _SoftCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'امروز چطور همدل باشم؟',
          subtitle: 'فقط کاری را ثبت کن که واقعاً انجام می‌دهی؛ حمایت جای درمان را نمی‌گیرد.',
          icon: Icons.volunteer_activism_rounded,
        ),
        const SizedBox(height: 13),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < 330
                ? constraints.maxWidth
                : (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _supportActions
                  .map(
                    (action) => SizedBox(
                      width: width,
                      child: Material(
                        color: action.color.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          onTap: saving ? null : () => onAction(action),
                          borderRadius: BorderRadius.circular(18),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(action.icon, color: action.color, size: 21),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    action.label,
                                    maxLines: 2,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: action.color,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
        if (saving) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 2, color: _lilac),
        ],
      ],
    ),
  );
}

class _CompanionMessageCard extends StatelessWidget {
  const _CompanionMessageCard({
    required this.patientName,
    required this.estimate,
    required this.sharedDailySummary,
  });

  final String patientName;
  final WomenCalendarEstimate? estimate;
  final Map<String, dynamic>? sharedDailySummary;

  @override
  Widget build(BuildContext context) {
    final phase = _phaseVisual(estimate?.detailedPhase);
    final support = sharedDailySummary?['supportNeed']?.toString().toLowerCase();
    final message = switch (support) {
      'rest' => 'امروز شاید بهترین کمک، سبک‌کردن برنامه و فراهم‌کردن کمی استراحت باشد.',
      'talk' => 'یک گفت‌وگوی آرام و شنیدن بدون عجله، از هر توصیه‌ای باارزش‌تر است.',
      'space' => 'کمی خلوت خواستن به معنی فاصله عاطفی نیست؛ به مرزش احترام بگذار.',
      'warmth' => 'یک نوشیدنی گرم یا کیسه آب گرم می‌تواند یک توجه کوچک و دوست‌داشتنی باشد.',
      'walk' => 'یک پیاده‌روی کوتاه و بدون فشار پیشنهاد بده؛ حق انتخاب با خودش است.',
      'hug' => 'قبل از آغوش، با یک سؤال ساده مطمئن شو که الان همین را می‌خواهد.',
      _ => phase.tip,
    };
    return _SoftCard(
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFFF1E6FF), Color(0xFFFFEDF5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'سخن امروز برای همدل ❞',
            style: TextStyle(
              color: _lilac,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            '$patientName بیشتر از راه‌حل آماده، به فهمیده‌شدن نیاز دارد. $message',
            style: const TextStyle(
              color: Color(0xFF604E70),
              fontSize: 11.5,
              height: 1.75,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSupportCard extends StatelessWidget {
  const _RecentSupportCard({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final actions = _summaryList(summary, 'supportActions');
    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'حمایت‌های اخیر',
            subtitle: 'یادآوری کوچک از کارهایی که برای همراهی ثبت کرده‌ای',
            icon: Icons.history_rounded,
          ),
          const SizedBox(height: 12),
          if (actions.isEmpty)
            const _EmptyInline(
              icon: Icons.favorite_outline_rounded,
              text: 'هنوز حمایتی ثبت نشده است.',
            )
          else
            ...actions.take(5).map((action) {
              final definition = _supportActions.firstWhere(
                (item) => item.type == action['actionType']?.toString(),
                orElse: () => const _SupportAction(
                  type: 'support',
                  label: 'حمایت',
                  confirmation: 'حمایت',
                  icon: Icons.favorite_outline_rounded,
                  color: _lilac,
                ),
              );
              final date = DateTime.tryParse(
                action['performedAtUtc']?.toString() ?? '',
              )?.toLocal();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: definition.color.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Row(
                    children: [
                      Icon(definition.icon, color: definition.color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          definition.confirmation,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (date != null)
                        Text(
                          formatAppDate(context, date, includeWeekday: false),
                          style: const TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 9.5,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) => _SoftCard(
    color: const Color(0xFFFFF8E9),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, color: Color(0xFF9B6D1A)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'این صفحه فقط خلاصه مجاز چرخه و حال کلی را نشان می‌دهد. یادداشت خصوصی و فهرست علائم در WellMate باقی می‌مانند. تخمین چرخه، توصیه پزشکی یا ابزار پیشگیری از بارداری نیست.',
            style: TextStyle(
              color: Color(0xFF745A25),
              fontSize: 10.5,
              height: 1.7,
            ),
          ),
        ),
      ],
    ),
  );
}

class _EmptyInline extends StatelessWidget {
  const _EmptyInline({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F5FA),
      borderRadius: BorderRadius.circular(17),
    ),
    child: Row(
      children: [
        Icon(icon, color: _lilac),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 10.5,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: _SoftCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 52, color: _lilac),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.7, color: _ink),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: _lilac),
              child: const Text('تلاش دوباره'),
            ),
          ],
        ),
      ),
    ),
  );
}

List<Map<String, dynamic>> _summaryList(
  Map<String, dynamic> summary,
  String key,
) => (summary[key] as List<dynamic>? ?? const [])
    .whereType<Map<String, dynamic>>()
    .toList(growable: false);

String _moodLabel(String? value) => switch (value) {
  'great' => 'عالی',
  'good' => 'خوب',
  'neutral' => 'معمولی',
  'low' => 'کم‌حوصله',
  'overwhelmed' => 'تحت فشار',
  _ => 'ثبت نشده',
};

String _energyLabel(int? value) => switch (value) {
  1 => 'خیلی کم',
  2 => 'کم',
  3 => 'متوسط',
  4 => 'خوب',
  5 => 'بالا',
  _ => 'ثبت نشده',
};

String _supportLabel(String? value) => switch (value) {
  'rest' => 'استراحت',
  'talk' => 'گفت‌وگو',
  'space' => 'کمی خلوت',
  'warmth' => 'نوشیدنی گرم',
  'walk' => 'پیاده‌روی',
  'hug' => 'آغوش',
  'none' => 'فعلاً خوب است',
  _ => 'ثبت نشده',
};

DateTime _scheduledDateTime(Map<String, dynamic> value) {
  final utc = DateTime.tryParse(value['scheduledAtUtc']?.toString() ?? '');
  if (utc != null) return utc.toLocal();
  final date = DateTime.tryParse(value['scheduledLocalDate']?.toString() ?? '');
  final time = value['scheduledLocalTime']?.toString().split(':') ?? const [];
  if (date == null) return DateTime(9999);
  return DateTime(
    date.year,
    date.month,
    date.day,
    time.isEmpty ? 0 : int.tryParse(time[0]) ?? 0,
    time.length < 2 ? 0 : int.tryParse(time[1]) ?? 0,
  );
}

String _timeLabel(BuildContext context, DateTime value) {
  final raw =
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  return localizeDigits(context, raw);
}

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;
