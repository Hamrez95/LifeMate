import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/persian_date_utils.dart';

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
  List<Map<String, dynamic>> _todayDoses = const [];
  List<Map<String, dynamic>> _todayCareEvents = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<LifeMateApiClient>();
      final today = DateTime.now();
      final results = await Future.wait<dynamic>([
        api.getCareRecipientWomenCalendar(patientUserId: widget.patientUserId),
        api.getCareRecipientDoseOccurrences(
          patientUserId: widget.patientUserId,
          fromDate: today,
          toDate: today,
        ),
        api.getCareRecipientCareEvents(
          patientUserId: widget.patientUserId,
          fromDate: today,
          toDate: today,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _todayDoses = results[1] as List<Map<String, dynamic>>;
        _todayCareEvents = results[2] as List<Map<String, dynamic>>;
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          'women_calendar_access_denied' =>
            'دسترسی همدم به چرخه فعال نیست یا توسط همسرت متوقف شده است.',
          'women_calendar_not_active' =>
            'تقویم بانوان برای ${widget.patientName} فعال نیست.',
          'women_calendar_feature_disabled' =>
            'این قابلیت در نسخه فعلی فعال نیست.',
          _ => 'خلاصه همدم دریافت نشد. دوباره تلاش کنید.',
        };
      });
    } catch (error) {
      debugPrint('Care companion dashboard load failed: $error');
      if (mounted) {
        setState(() => _error = 'خلاصه همدم دریافت نشد. دوباره تلاش کنید.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recordAction(String actionType, String label) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context
          .read<LifeMateApiClient>()
          .recordCareRecipientWomenSupportAction(
            patientUserId: widget.patientUserId,
            actionType: actionType,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label ثبت شد؛ یک همراهی کوچک می‌تواند خیلی ارزشمند باشد.'),
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
                ? 'دسترسی همدم دیگر فعال نیست.'
                : 'ثبت همراهی انجام نشد.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7FF),
      appBar: AppBar(
        toolbarHeight: 66,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'همدم من',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF452D62),
              ),
            ),
            Text(
              'همراهی محترمانه، با رضایت و بدون قضاوت',
              style: TextStyle(fontSize: 10, color: Color(0xFF8B789D)),
            ),
          ],
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFCF7FF), Color(0xFFF7F0FF), Color(0xFFFFF9FB)],
          ),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      key: const ValueKey('care-companion-mobile-dashboard'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                      children: [
                        _ConnectedPartnerHero(
                          patientName: _patientName,
                          patientAvatarKey: _patientAvatarKey,
                        ),
                        const SizedBox(height: 14),
                        _PartnerCycleSummary(summary: _summary),
                        const SizedBox(height: 14),
                        _SharedWellbeingCard(summary: _summary),
                        const SizedBox(height: 14),
                        _TodayCareStatus(
                          patientName: _patientName,
                          doses: _todayDoses,
                          events: _todayCareEvents,
                        ),
                        const SizedBox(height: 14),
                        _SupportActions(
                          saving: _saving,
                          onAction: _recordAction,
                        ),
                        const SizedBox(height: 14),
                        _ImportantReminders(
                          doses: _todayDoses,
                          events: _todayCareEvents,
                        ),
                        const SizedBox(height: 14),
                        _CompassionMessage(summary: _summary),
                        const SizedBox(height: 14),
                        _RecentActions(summary: _summary),
                        const SizedBox(height: 14),
                        const _PrivacyNotice(),
                      ],
                    ),
                  ),
      ),
    );
  }

  String get _patientName {
    final patient = _summary['patient'] as Map<String, dynamic>?;
    final value = patient?['displayName']?.toString().trim();
    return value == null || value.isEmpty ? widget.patientName : value;
  }

  String get _patientAvatarKey {
    final patient = _summary['patient'] as Map<String, dynamic>?;
    return patient?['avatarKey']?.toString() ?? 'person_purple';
  }
}

class _ConnectedPartnerHero extends StatelessWidget {
  const _ConnectedPartnerHero({
    required this.patientName,
    required this.patientAvatarKey,
  });

  final String patientName;
  final String patientAvatarKey;

  @override
  Widget build(BuildContext context) {
    final api = context.read<LifeMateApiClient>();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFF0E2FF), Color(0xFFFFEAF4), Color(0xFFFFF8EE)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x159569C3),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 210,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(70),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LifeMateProfileAvatar(
                    avatarKey: patientAvatarKey,
                    radius: 38,
                  ),
                  Transform.translate(
                    offset: const Offset(5, 0),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFD98AD0),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: Color(0xFFD966A4),
                        size: 20,
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(-5, 0),
                    child: LifeMateCurrentUserAvatar(
                      apiClient: api,
                      radius: 38,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'ما کنار هم مراقبت می‌کنیم',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xFF4E3568),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'وضعیت $patientName فقط در محدوده‌ای نمایش داده می‌شود که خودش انتخاب کرده است.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10.5,
              height: 1.55,
              color: Color(0xFF7D6A8D),
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerCycleSummary extends StatelessWidget {
  const _PartnerCycleSummary({required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final estimate = summary['estimate'] as Map<String, dynamic>? ?? const {};
    final phase = estimate['detailedPhase']?.toString() ??
        estimate['phase']?.toString();
    final visual = _phaseVisual(phase);
    final cycleDay = estimate['cycleDay'] is int
        ? estimate['cycleDay'] as int
        : null;
    final cycleLength = estimate['cycleLength'] is int
        ? estimate['cycleLength'] as int
        : 28;
    final daysLeft = estimate['daysUntilNextPeriod'] is int
        ? estimate['daysUntilNextPeriod'] as int
        : null;

    return _SoftCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 330;
          final ring = _MiniCycleRing(
            day: cycleDay,
            length: cycleLength,
            color: visual.color,
          );
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'خلاصه چرخه',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                visual.label,
                style: TextStyle(
                  color: visual.foreground,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                daysLeft == null
                    ? 'اطلاعات کافی برای برآورد وجود ندارد.'
                    : 'حدود ${localizeDigits(context, daysLeft)} روز تا شروع تخمینی دوره بعدی',
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          );
          if (narrow) {
            return Column(
              children: [
                ring,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: copy),
              ],
            );
          }
          return Row(
            children: [ring, const SizedBox(width: 16), Expanded(child: copy)],
          );
        },
      ),
    );
  }
}

class _MiniCycleRing extends StatelessWidget {
  const _MiniCycleRing({
    required this.day,
    required this.length,
    required this.color,
  });

  final int? day;
  final int length;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 112,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _ProgressRingPainter(
                progress: day == null ? 0 : day! / length,
                color: color,
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    day == null ? '—' : localizeDigits(context, day!),
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'از ${localizeDigits(context, length)} روز',
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: math.min(size.width, size.height) / 2 - 8,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF0E9F5);
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      active,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _SharedWellbeingCard extends StatelessWidget {
  const _SharedWellbeingCard({required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final log = summary['latestSharedDailyLog'] as Map<String, dynamic>?;
    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.favorite_border_rounded,
            title: 'حال ثبت‌شده همسرم',
            subtitle: 'فقط خلاصه‌ای که خودش برای اشتراک انتخاب کرده',
          ),
          const SizedBox(height: 13),
          if (log == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F3FC),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'امروز خلاصه‌ای به اشتراک گذاشته نشده است. همین که بدون اصرار کنارش باشی، حمایت ارزشمندی است.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.65,
                  color: Color(0xFF73647E),
                ),
              ),
            )
          else
            _SharedSummary(log: log),
        ],
      ),
    );
  }
}

class _SharedSummary extends StatelessWidget {
  const _SharedSummary({required this.log});
  final Map<String, dynamic> log;

  @override
  Widget build(BuildContext context) {
    final mood = _moodVisual(log['mood']?.toString());
    final symptoms = (log['symptoms'] as List<dynamic>? ?? const [])
        .map((item) => _symptomLabel(item.toString()))
        .toList(growable: false);
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: mood.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Text(mood.emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mood.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'انرژی ${localizeDigits(context, log['energyLevel'] ?? '—')} از ۵ • درد ${localizeDigits(context, log['painLevel'] ?? '—')} از ۵',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (symptoms.isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: symptoms
                  .map(
                    (label) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEFF5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(label, style: const TextStyle(fontSize: 10)),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ],
    );
  }
}

class _TodayCareStatus extends StatelessWidget {
  const _TodayCareStatus({
    required this.patientName,
    required this.doses,
    required this.events,
  });

  final String patientName;
  final List<Map<String, dynamic>> doses;
  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    final missed = doses.where((item) {
      final status = item['status']?.toString().toLowerCase();
      return status == 'missed' || status == 'skipped';
    }).length;
    final taken = doses
        .where((item) => item['status']?.toString().toLowerCase() == 'taken')
        .length;
    final upcoming = events
        .where((item) =>
            item['status']?.toString().toLowerCase() == 'scheduled')
        .length;

    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.today_rounded,
            title: 'وضعیت امروز',
            subtitle: 'سلامت و برنامه‌های روزانه، جدا از اطلاعات خصوصی چرخه',
          ),
          const SizedBox(height: 12),
          _StatusLine(
            icon: Icons.medication_rounded,
            color: missed > 0
                ? const Color(0xFFE15C72)
                : const Color(0xFF5AA781),
            title: 'داروها',
            value: missed > 0
                ? '${localizeDigits(context, missed)} مورد انجام‌نشده'
                : '${localizeDigits(context, taken)} مورد ثبت‌شده',
          ),
          _StatusLine(
            icon: Icons.calendar_month_rounded,
            color: const Color(0xFF8E70CE),
            title: 'ویزیت و تزریق',
            value: upcoming == 0
                ? 'برنامه‌ای برای امروز نیست'
                : '${localizeDigits(context, upcoming)} برنامه پیش رو',
          ),
          _StatusLine(
            icon: Icons.favorite_rounded,
            color: const Color(0xFFD8679C),
            title: 'نوع همراهی',
            value: 'پرسیدن، شنیدن و احترام به نیاز $patientName',
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _SupportActions extends StatelessWidget {
  const _SupportActions({required this.saving, required this.onAction});

  final bool saving;
  final Future<void> Function(String, String) onAction;

  static const actions = <_SupportDefinition>[
    _SupportDefinition(
      type: 'hydration',
      label: 'نوشیدنی آماده کردم',
      icon: Icons.local_drink_rounded,
      color: Color(0xFF4C9BE8),
    ),
    _SupportDefinition(
      type: 'rest',
      label: 'فضای استراحت دادم',
      icon: Icons.bedtime_rounded,
      color: Color(0xFF7772D7),
    ),
    _SupportDefinition(
      type: 'warmth',
      label: 'گرمای ملایم آماده کردم',
      icon: Icons.device_thermostat_rounded,
      color: Color(0xFFE58970),
    ),
    _SupportDefinition(
      type: 'chores',
      label: 'در کارها کمک کردم',
      icon: Icons.home_work_rounded,
      color: Color(0xFF55A77A),
    ),
    _SupportDefinition(
      type: 'walk',
      label: 'پیاده‌روی پیشنهاد دادم',
      icon: Icons.directions_walk_rounded,
      color: Color(0xFFB57A4E),
    ),
    _SupportDefinition(
      type: 'check_in',
      label: 'با آرامش حالش را پرسیدم',
      icon: Icons.forum_rounded,
      color: Color(0xFFD7659B),
    ),
  ];

  @override
  Widget build(BuildContext context) => _SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.volunteer_activism_rounded,
              title: 'امروز چطور همراه باشم؟',
              subtitle: 'فقط کاری را ثبت کن که واقعاً انجام داده‌ای.',
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < 330
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: actions
                      .map(
                        (action) => SizedBox(
                          width: width,
                          child: Material(
                            color: action.color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(17),
                            child: InkWell(
                              onTap: saving
                                  ? null
                                  : () => onAction(action.type, action.label),
                              borderRadius: BorderRadius.circular(17),
                              child: Padding(
                                padding: const EdgeInsets.all(11),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        action.icon,
                                        size: 19,
                                        color: action.color,
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        action.label,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
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
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      );
}

class _SupportDefinition {
  const _SupportDefinition({
    required this.type,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String type;
  final String label;
  final IconData icon;
  final Color color;
}

class _ImportantReminders extends StatelessWidget {
  const _ImportantReminders({required this.doses, required this.events});

  final List<Map<String, dynamic>> doses;
  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    final items = <_ReminderItem>[];
    for (final dose in doses) {
      final status = dose['status']?.toString().toLowerCase();
      if (status == 'taken' || status == 'cancelled') continue;
      items.add(
        _ReminderItem(
          title: dose['medicationName']?.toString() ?? 'دارو',
          time: _time(dose['scheduledLocalTime']),
          detail: status == 'missed' ? 'انجام‌نشده' : 'در انتظار',
          icon: Icons.medication_rounded,
          urgent: status == 'missed',
        ),
      );
    }
    for (final event in events) {
      if (event['status']?.toString().toLowerCase() != 'scheduled') continue;
      final injection =
          event['eventType']?.toString().toLowerCase() == 'injection';
      items.add(
        _ReminderItem(
          title: event['title']?.toString() ?? (injection ? 'تزریق' : 'ویزیت'),
          time: _time(event['scheduledLocalTime']),
          detail: injection ? 'تزریق' : 'ویزیت',
          icon: injection
              ? Icons.vaccines_rounded
              : Icons.medical_services_rounded,
          urgent: false,
        ),
      );
    }

    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.notifications_active_outlined,
            title: 'یادآوری‌های مهم',
            subtitle: 'برنامه‌های مراقبتی امروز، بدون اطلاعات خصوصی چرخه',
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'یادآوری فعالی برای امروز وجود ندارد.',
                style: TextStyle(color: AppColors.secondaryText),
              ),
            )
          else
            ...items.take(4).map((item) => _ReminderTile(item: item)),
        ],
      ),
    );
  }

  static String _time(dynamic value) {
    final text = value?.toString() ?? '--:--';
    return text.length >= 5 ? text.substring(0, 5) : text;
  }
}

class _ReminderItem {
  const _ReminderItem({
    required this.title,
    required this.time,
    required this.detail,
    required this.icon,
    required this.urgent,
  });

  final String title;
  final String time;
  final String detail;
  final IconData icon;
  final bool urgent;
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.item});
  final _ReminderItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.urgent
        ? const Color(0xFFE05A70)
        : const Color(0xFF8870C6);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(item.icon, color: color, size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(fontWeight: FontWeight.w900, color: color),
                ),
                Text(
                  item.detail,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          Text(
            localizeDigits(context, item.time),
            style: TextStyle(fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }
}

class _CompassionMessage extends StatelessWidget {
  const _CompassionMessage({required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final estimate = summary['estimate'] as Map<String, dynamic>? ?? const {};
    final log = summary['latestSharedDailyLog'] as Map<String, dynamic>?;
    final mood = log?['mood']?.toString();
    final phase = estimate['detailedPhase']?.toString() ??
        estimate['phase']?.toString();
    final message = _compassionCopy(phase, mood);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFF2E5FF), Color(0xFFFFEEF6)],
        ),
        borderRadius: BorderRadius.circular(27),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.format_quote_rounded,
              color: Color(0xFF9B69C6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'سخن امروز برای همدم',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF694384),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.7,
                    color: Color(0xFF6C5A72),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.local_florist_rounded,
            color: Color(0xFFC47AC0),
          ),
        ],
      ),
    );
  }
}

class _RecentActions extends StatelessWidget {
  const _RecentActions({required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final raw = summary['supportActions'] as List<dynamic>? ?? const [];
    final actions = raw
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.history_rounded,
            title: 'همراهی‌های اخیر',
            subtitle: 'کارهای کوچک و واقعی که ثبت کرده‌ای',
          ),
          const SizedBox(height: 10),
          if (actions.isEmpty)
            const Text(
              'هنوز همراهی‌ای ثبت نشده است.',
              style: TextStyle(color: AppColors.secondaryText),
            )
          else
            ...actions.take(5).map((action) {
              final type = action['actionType']?.toString() ?? '';
              final performed = DateTime.tryParse(
                action['performedAtUtc']?.toString() ?? '',
              )?.toLocal();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const Icon(
                      Icons.favorite_rounded,
                      size: 18,
                      color: Color(0xFFD7669C),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _supportLabel(type),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                    if (performed != null)
                      Text(
                        formatAppDate(context, performed),
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: AppColors.secondaryText,
                        ),
                      ),
                  ],
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
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8DDF0)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline_rounded, color: Color(0xFF80649A)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'این صفحه فقط خلاصه مجاز چرخه و ثبت‌هایی را نشان می‌دهد که همسرت صریحاً برای اشتراک انتخاب کرده است. یادداشت خصوصی، تاریخچه کامل علائم و اطلاعات حساس نمایش داده نمی‌شوند. برآوردها پزشکی نیستند.',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.65,
                  color: Color(0xFF6D6174),
                ),
              ),
            ),
          ],
        ),
      );
}

class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.91),
          borderRadius: BorderRadius.circular(27),
          border: Border.all(color: Colors.white),
          boxShadow: const [
            BoxShadow(
              color: Color(0x109366A0),
              blurRadius: 22,
              offset: Offset(0, 9),
            ),
          ],
        ),
        child: child,
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF4ECFA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF8E65AD), size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: _SoftCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.privacy_tip_outlined,
                  size: 54,
                  color: Color(0xFF8E65AD),
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.6),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('تلاش دوباره'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _PhaseVisual {
  const _PhaseVisual(this.label, this.color, this.foreground);

  final String label;
  final Color color;
  final Color foreground;
}

_PhaseVisual _phaseVisual(String? phase) {
  switch (phase) {
    case 'period':
      return const _PhaseVisual(
        'فاز قاعدگی',
        Color(0xFFF15D7B),
        Color(0xFF9F2847),
      );
    case 'follicular':
    case 'post_period':
      return const _PhaseVisual(
        'فاز فولیکولار',
        Color(0xFFB48BE1),
        Color(0xFF6F439F),
      );
    case 'fertile':
      return const _PhaseVisual(
        'پنجره باروری تخمینی',
        Color(0xFF57C5B5),
        Color(0xFF247D72),
      );
    case 'ovulation':
      return const _PhaseVisual(
        'روز تخمک‌گذاری تخمینی',
        Color(0xFF55A8E8),
        Color(0xFF286A9D),
      );
    case 'luteal':
    case 'cycle':
      return const _PhaseVisual(
        'فاز لوتئال',
        Color(0xFFF3B651),
        Color(0xFF946517),
      );
    case 'pms':
    case 'pre_period':
      return const _PhaseVisual(
        'روزهای پیش از دوره',
        Color(0xFFE88973),
        Color(0xFF9D4938),
      );
    default:
      return const _PhaseVisual(
        'ریتم چرخه',
        Color(0xFFB48BE1),
        Color(0xFF6F439F),
      );
  }
}

class _MoodVisual {
  const _MoodVisual(this.label, this.emoji, this.color);

  final String label;
  final String emoji;
  final Color color;
}

_MoodVisual _moodVisual(String? mood) {
  switch (mood) {
    case 'great':
      return const _MoodVisual('حال عالی', '😊', Color(0xFF55B889));
    case 'good':
      return const _MoodVisual('حال خوب', '🙂', Color(0xFF8D78D5));
    case 'neutral':
      return const _MoodVisual('حال معمولی', '😐', Color(0xFFE7B650));
    case 'low':
      return const _MoodVisual('انرژی کمتر', '😔', Color(0xFFE78D69));
    case 'overwhelmed':
      return const _MoodVisual('تحت فشار', '😣', Color(0xFFE46178));
    default:
      return const _MoodVisual('ثبت نشده', '🌸', Color(0xFFB68DD9));
  }
}

String _symptomLabel(String code) {
  switch (code) {
    case 'cramps':
      return 'درد شکم';
    case 'headache':
      return 'سردرد';
    case 'bloating':
      return 'نفخ';
    case 'fatigue':
      return 'خستگی';
    case 'breast_tenderness':
      return 'حساسیت سینه';
    case 'back_pain':
      return 'کمردرد';
    case 'sleep_change':
      return 'تغییر خواب';
    case 'appetite_change':
      return 'تغییر اشتها';
    case 'no_symptom':
      return 'بدون نشانه';
    default:
      return 'نشانه ثبت‌شده';
  }
}

String _supportLabel(String type) {
  switch (type) {
    case 'hydration':
      return 'آب یا نوشیدنی آماده کردم';
    case 'rest':
      return 'زمان استراحت فراهم کردم';
    case 'warmth':
      return 'گرمای ملایم آماده کردم';
    case 'chores':
      return 'در کارهای خانه کمک کردم';
    case 'walk':
      return 'پیاده‌روی کوتاه پیشنهاد دادم';
    case 'checkin':
    case 'check_in':
      return 'با آرامش حالش را پرسیدم';
    default:
      return 'یک همراهی ثبت کردم';
  }
}

String _compassionCopy(String? phase, String? mood) {
  if (mood == 'low' || mood == 'overwhelmed') {
    return 'امروز شاید بیشتر از راه‌حل، به شنیده‌شدن نیاز داشته باشد. آرام بپرس چه کمکی دوست دارد و انتخابش را محترم بدان.';
  }
  switch (phase) {
    case 'period':
      return 'ممکن است استراحت، گرمای ملایم یا کمک کوچک در کارها خوشایند باشد؛ اول بپرس و بعد همراهی کن.';
    case 'pms':
    case 'pre_period':
      return 'امروز کمی صبورتر باش. یک گفت‌وگوی آرام، کم‌کردن فشار روز و احترام به نیازش می‌تواند ارزشمند باشد.';
    case 'follicular':
    case 'post_period':
      return 'حال خوب را هم بدون انتظار و فشار شریک شو؛ یک برنامه سبک دونفره می‌تواند دلنشین باشد.';
    default:
      return 'همراهی یعنی حضور آرام، پرسیدن بدون قضاوت و پذیرفتن اینکه نیاز امروز ممکن است با دیروز فرق داشته باشد.';
  }
}
