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
  String? _relationshipPatientProfilePhotoUrl;
  String? _relationshipPatientAvatarKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<Map<String, dynamic>>> _loadRelationshipMetadata(
    LifeMateApiClient api,
  ) async {
    try {
      return await api.getCareRelationships();
    } catch (error) {
      debugPrint('Care companion relationship metadata load failed: $error');
      return const <Map<String, dynamic>>[];
    }
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
        _loadRelationshipMetadata(api),
      ]);
      if (!mounted) return;
      final relationships = results[3] as List<Map<String, dynamic>>;
      Map<String, dynamic>? targetRelationship;
      for (final relationship in relationships) {
        if (relationship['status']?.toString().toLowerCase() != 'active') {
          continue;
        }
        if (relationship['patientUserId']?.toString() != widget.patientUserId) {
          continue;
        }
        if (relationship['canViewWomenCalendar'] != true) continue;
        targetRelationship = relationship;
        break;
      }
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _todayDoses = results[1] as List<Map<String, dynamic>>;
        _todayCareEvents = results[2] as List<Map<String, dynamic>>;
        _relationshipPatientProfilePhotoUrl = _optionalText(
          targetRelationship?['patientProfilePhotoUrl'],
        );
        _relationshipPatientAvatarKey = _optionalText(
          targetRelationship?['patientAvatarKey'],
        );
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          'women_calendar_access_denied' => LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'دسترسی همدم به چرخه فعال نیست یا توسط همسرت متوقف شده است.',
              en: "Companion access to the cycle is not active or has been stopped by your partner.",
            ),
            en: "Companion access to the cycle is not active or has been stopped by your partner.",
          ),
          'women_calendar_not_active' => LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'تقویم بانوان برای ${widget.patientName} فعال نیست.',
              en: "Ladies calendar is not enabled for ${widget.patientName}.",
            ),
            en: "Ladies calendar is not enabled for ${widget.patientName}.",
          ),
          'women_calendar_feature_disabled' => LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'این قابلیت در نسخه فعلی فعال نیست.',
              en: "This feature is not enabled in the current version.",
            ),
            en: "This feature is not enabled in the current version.",
          ),
          _ => LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'خلاصه همدم دریافت نشد. دوباره تلاش کنید.',
              en: "The companion summary was not received. Try again.",
            ),
            en: "The companion summary was not received. Try again.",
          ),
        };
      });
    } catch (error) {
      debugPrint('Care companion dashboard load failed: $error');
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'خلاصه همدم دریافت نشد. دوباره تلاش کنید.',
              en: "The companion summary was not received. Try again.",
            ),
            en: "The companion summary was not received. Try again.",
          ),
        );
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
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: '$label ثبت شد؛ یک همراهی کوچک می‌تواند خیلی ارزشمند باشد.',
                en: "$label registered; A little companionship can be very valuable.",
              ),
              en: "$label registered; A little companionship can be very valuable.",
            ),
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
            error.code == 'women_calendar_access_denied'
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'دسترسی همدم دیگر فعال نیست.',
                      en: "Companion access is no longer enabled.",
                    ),
                    en: "Companion access is no longer enabled.",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ثبت همراهی انجام نشد.',
                      en: "Accompanying registration was not done.",
                    ),
                    en: "Accompanying registration was not done.",
                  ),
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
      backgroundColor: Color(0xFFFBF7FF),
      appBar: AppBar(
        toolbarHeight: 66,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'همدم من',
                  en: "my companion",
                ),
                en: "my companion",
              ),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF452D62),
              ),
            ),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'همراهی محترمانه، با رضایت و بدون قضاوت',
                  en: "Respectful companionship, with consent and without judgment",
                ),
                en: "Respectful companionship, with consent and without judgment",
              ),
              style: TextStyle(fontSize: 10, color: Color(0xFF8B789D)),
            ),
          ],
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFCF7FF), Color(0xFFF7F0FF), Color(0xFFFFF9FB)],
          ),
        ),
        child: _loading
            ? Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  key: ValueKey('care-companion-mobile-dashboard'),
                  physics: AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(18, 8, 18, 28),
                  children: [
                    _ConnectedPartnerHero(
                      patientName: _patientName,
                      patientAvatarKey: _patientAvatarKey,
                      patientProfilePhotoUrl: _patientProfilePhotoUrl,
                    ),
                    SizedBox(height: 14),
                    _PartnerCycleSummary(summary: _summary),
                    SizedBox(height: 14),
                    _SharedWellbeingCard(summary: _summary),
                    SizedBox(height: 14),
                    _TodayCareStatus(
                      patientName: _patientName,
                      doses: _todayDoses,
                      events: _todayCareEvents,
                    ),
                    SizedBox(height: 14),
                    _SupportActions(saving: _saving, onAction: _recordAction),
                    SizedBox(height: 14),
                    _ImportantReminders(
                      doses: _todayDoses,
                      events: _todayCareEvents,
                    ),
                    SizedBox(height: 14),
                    _CompassionMessage(summary: _summary),
                    SizedBox(height: 14),
                    _RecentActions(summary: _summary),
                    SizedBox(height: 14),
                    _PrivacyNotice(),
                  ],
                ),
              ),
      ),
    );
  }

  String get _patientName {
    final patient = _summary['patient'] as Map<String, dynamic>?;
    return _optionalText(patient?['displayName']) ?? widget.patientName;
  }

  String get _patientAvatarKey {
    final patient = _summary['patient'] as Map<String, dynamic>?;
    return _optionalText(patient?['avatarKey']) ??
        _relationshipPatientAvatarKey ??
        'person_purple';
  }

  String? get _patientProfilePhotoUrl {
    final patient = _summary['patient'] as Map<String, dynamic>?;
    return _optionalText(patient?['profilePhotoUrl']) ??
        _relationshipPatientProfilePhotoUrl;
  }

  static String? _optionalText(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class _ConnectedPartnerHero extends StatelessWidget {
  const _ConnectedPartnerHero({
    required this.patientName,
    required this.patientAvatarKey,
    required this.patientProfilePhotoUrl,
  });

  final String patientName;
  final String patientAvatarKey;
  final String? patientProfilePhotoUrl;

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
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    LifeMateProfileAvatar(
                      key: const ValueKey('care-women-patient-avatar'),
                      avatarKey: patientAvatarKey,
                      photoUrl: patientProfilePhotoUrl,
                      radius: 38,
                    ),
                    Transform.translate(
                      offset: Offset(5, 0),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Color(0xFFD98AD0),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.favorite_rounded,
                          color: Color(0xFFD966A4),
                          size: 20,
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(-5, 0),
                      child: LifeMateCurrentUserAvatar(
                        key: ValueKey('care-women-current-caregiver-avatar'),
                        apiClient: api,
                        radius: 38,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'ما کنار هم مراقبت می‌کنیم',
                en: "We care together",
              ),
              en: "We care together",
            ),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xFF4E3568),
            ),
          ),
          SizedBox(height: 5),
          Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'وضعیت $patientName فقط در محدوده‌ای نمایش داده می‌شود که خودش انتخاب کرده است.',
                en: "$patientName status is only displayed in the range it has selected.",
              ),
              en: "$patientName status is only displayed in the range it has selected.",
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
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
    final phase =
        estimate['detailedPhase']?.toString() ?? estimate['phase']?.toString();
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
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'خلاصه چرخه',
                    en: "Summary of the cycle",
                  ),
                  en: "Summary of the cycle",
                ),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 5),
              Text(
                visual.label,
                style: TextStyle(
                  color: visual.foreground,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 6),
              Text(
                daysLeft == null
                    ? LifeMateRuntimeLocale.select(
                        fa: 'اطلاعات کافی برای برآورد وجود ندارد.',
                        en: "There is not enough information to estimate.",
                      )
                    : LifeMateRuntimeLocale.select(
                        fa: 'حدود ${localizeDigits(context, daysLeft)} روز تا شروع تخمینی دوره بعدی',
                        en: "About ${localizeDigits(context, daysLeft)} days until the estimated start of the next period",
                      ),
                style: TextStyle(
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
            children: [
              ring,
              const SizedBox(width: 16),
              Expanded(child: copy),
            ],
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
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
              ),
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'از ${localizeDigits(context, length)} روز',
                    en: "of ${localizeDigits(context, length)} days",
                  ),
                  en: "of ${localizeDigits(context, length)} days",
                ),
                style: TextStyle(fontSize: 9.5, color: AppColors.secondaryText),
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
          _SectionHeader(
            icon: Icons.favorite_border_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'حال ثبت‌شده همسرم',
                en: "My wife's registered status",
              ),
              en: "My wife's registered status",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'فقط خلاصه‌ای که خودش برای اشتراک انتخاب کرده',
                en: "Only the summary that he chose to share",
              ),
              en: "Only the summary that he chose to share",
            ),
          ),
          SizedBox(height: 13),
          if (log == null)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Color(0xFFF8F3FC),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'امروز خلاصه‌ای به اشتراک گذاشته نشده است. همین که بدون اصرار کنارش باشی، حمایت ارزشمندی است.',
                    en: "No summary has been shared today. Just being by his side without insistence is a valuable support.",
                  ),
                  en: "No summary has been shared today. Just being by his side without insistence is a valuable support.",
                ),
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
                child: Text(mood.emoji, style: TextStyle(fontSize: 28)),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mood.label,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 4),
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: 'انرژی ${localizeDigits(context, log['energyLevel'] ?? '—')} از ۵ • درد ${localizeDigits(context, log['painLevel'] ?? '—')} از ۵',
                      en: "Energy ${localizeDigits(context, log['energyLevel'] ?? '—')} out of 5 • Pain ${localizeDigits(context, log['painLevel'] ?? '—')} out of 5",
                    ),
                    style: TextStyle(
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
          SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: symptoms
                  .map(
                    (label) => Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Color(0xFFFFEFF5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(label, style: TextStyle(fontSize: 10)),
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
        .where(
          (item) => item['status']?.toString().toLowerCase() == 'scheduled',
        )
        .length;

    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.today_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'وضعیت امروز',
                en: "Today's situation",
              ),
              en: "Today's situation",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'سلامت و برنامه‌های روزانه، جدا از اطلاعات خصوصی چرخه',
                en: "Health and daily schedules, separate from private cycle information",
              ),
              en: "Health and daily schedules, separate from private cycle information",
            ),
          ),
          SizedBox(height: 12),
          _StatusLine(
            icon: Icons.medication_rounded,
            color: missed > 0 ? Color(0xFFE15C72) : Color(0xFF5AA781),
            title: LifeMateRuntimeLocale.select(
              fa: 'داروها',
              en: "Medications",
            ),
            value: missed > 0
                ? LifeMateRuntimeLocale.select(
                    fa: '${localizeDigits(context, missed)} مورد انجام‌نشده',
                    en: "${localizeDigits(context, missed)} Item not done",
                  )
                : '${localizeDigits(context, taken)} مورد ثبت‌شده',
          ),
          _StatusLine(
            icon: Icons.calendar_month_rounded,
            color: Color(0xFF8E70CE),
            title: 'ویزیت و تزریق',
            value: upcoming == 0
                ? 'برنامه‌ای برای امروز نیست'
                : '${localizeDigits(context, upcoming)} برنامه پیش رو',
          ),
          _StatusLine(
            icon: Icons.favorite_rounded,
            color: Color(0xFFD8679C),
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'نوع همراهی',
                en: "Companion type",
              ),
              en: "Companion type",
            ),
            value: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'پرسیدن، شنیدن و احترام به نیاز $patientName',
                en: "Asking, listening and respecting the need for $patientName",
              ),
              en: "Asking, listening and respecting the need for $patientName",
            ),
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

  static final actions = <_SupportDefinition>[
    _SupportDefinition(
      type: 'hydration',
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'نوشیدنی آماده کردم',
          en: "I prepared a drink",
        ),
        en: "I prepared a drink",
      ),
      icon: Icons.local_drink_rounded,
      color: Color(0xFF4C9BE8),
    ),
    _SupportDefinition(
      type: 'rest',
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'فضای استراحت دادم',
          en: "I gave space to rest",
        ),
        en: "I gave space to rest",
      ),
      icon: Icons.bedtime_rounded,
      color: Color(0xFF7772D7),
    ),
    _SupportDefinition(
      type: 'warmth',
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'گرمای ملایم آماده کردم',
          en: "I prepared gentle heat",
        ),
        en: "I prepared gentle heat",
      ),
      icon: Icons.device_thermostat_rounded,
      color: Color(0xFFE58970),
    ),
    _SupportDefinition(
      type: 'chores',
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'در کارها کمک کردم',
          en: "I helped with the work",
        ),
        en: "I helped with the work",
      ),
      icon: Icons.home_work_rounded,
      color: Color(0xFF55A77A),
    ),
    _SupportDefinition(
      type: 'walk',
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'پیاده‌روی پیشنهاد دادم',
          en: "I suggested a walk",
        ),
        en: "I suggested a walk",
      ),
      icon: Icons.directions_walk_rounded,
      color: Color(0xFFB57A4E),
    ),
    _SupportDefinition(
      type: 'check_in',
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'با آرامش حالش را پرسیدم',
          en: "I asked him calmly",
        ),
        en: "I asked him calmly",
      ),
      icon: Icons.forum_rounded,
      color: Color(0xFFD7659B),
    ),
  ];

  @override
  Widget build(BuildContext context) => _SoftCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.volunteer_activism_rounded,
          title: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'امروز چطور همراه باشم؟',
              en: "How can I be with you today?",
            ),
            en: "How can I be with you today?",
          ),
          subtitle: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'فقط کاری را ثبت کن که واقعاً انجام داده‌ای.',
              en: "Just record what you actually did.",
            ),
            en: "Just record what you actually did.",
          ),
        ),
        SizedBox(height: 12),
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
          title:
              dose['medicationName']?.toString() ??
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
                en: "medicine",
              ),
          time: _time(dose['scheduledLocalTime']),
          detail: status == 'missed'
              ? LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'انجام‌نشده',
                    en: "not done",
                  ),
                  en: "not done",
                )
              : LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'در انتظار',
                    en: "waiting",
                  ),
                  en: "waiting",
                ),
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
          title:
              event['title']?.toString() ??
              (injection
                  ? LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'تزریق',
                        en: "Injection",
                      ),
                      en: "Injection",
                    )
                  : LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'ویزیت',
                        en: "Appointment",
                      ),
                      en: "visit",
                    )),
          time: _time(event['scheduledLocalTime']),
          detail: injection
              ? LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'تزریق',
                    en: "Injection",
                  ),
                  en: "Injection",
                )
              : LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'ویزیت',
                    en: "Appointment",
                  ),
                  en: "visit",
                ),
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
          _SectionHeader(
            icon: Icons.notifications_active_outlined,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'یادآوری‌های مهم',
                en: "Important reminders",
              ),
              en: "Important reminders",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'برنامه‌های مراقبتی امروز، بدون اطلاعات خصوصی چرخه',
                en: "Care plans today, without private cycle information",
              ),
              en: "Care plans today, without private cycle information",
            ),
          ),
          SizedBox(height: 10),
          if (items.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'یادآوری فعالی برای امروز وجود ندارد.',
                    en: "There are no active reminders for today.",
                  ),
                  en: "There are no active reminders for today.",
                ),
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
    final phase =
        estimate['detailedPhase']?.toString() ?? estimate['phase']?.toString();
    final message = _compassionCopy(phase, mood);
    return Container(
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFF2E5FF), Color(0xFFFFEEF6)],
        ),
        borderRadius: BorderRadius.circular(27),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white,
            child: Icon(Icons.format_quote_rounded, color: Color(0xFF9B69C6)),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'سخن امروز برای همدم',
                      en: "Today's speech is for my companion",
                    ),
                    en: "Today's speech is for my companion",
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF694384),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.7,
                    color: Color(0xFF6C5A72),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.local_florist_rounded, color: Color(0xFFC47AC0)),
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
          _SectionHeader(
            icon: Icons.history_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'همراهی‌های اخیر',
                en: "Recent companions",
              ),
              en: "Recent companions",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'کارهای کوچک و واقعی که ثبت کرده‌ای',
                en: "Small and real things that you have recorded",
              ),
              en: "Small and real things that you have recorded",
            ),
          ),
          SizedBox(height: 10),
          if (actions.isEmpty)
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'هنوز همراهی‌ای ثبت نشده است.',
                  en: "No accompaniment has been registered yet.",
                ),
                en: "No accompaniment has been registered yet.",
              ),
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
    padding: EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.74),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Color(0xFFE8DDF0)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, color: Color(0xFF80649A)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'این صفحه فقط خلاصه مجاز چرخه و ثبت‌هایی را نشان می‌دهد که همسرت صریحاً برای اشتراک انتخاب کرده است. یادداشت خصوصی، تاریخچه کامل علائم و اطلاعات حساس نمایش داده نمی‌شوند. برآوردها پزشکی نیستند.',
                en: "This page only shows authorized cycle summaries and records that your partner has explicitly chosen to subscribe to. Private notes, full symptom history, and sensitive information are not displayed. Estimates are not medical.",
              ),
              en: "This page only shows authorized cycle summaries and records that your partner has explicitly chosen to subscribe to. Private notes, full symptom history, and sensitive information are not displayed. Estimates are not medical.",
            ),
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
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
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
      padding: EdgeInsets.all(26),
      child: _SoftCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.privacy_tip_outlined,
              size: 54,
              color: Color(0xFF8E65AD),
            ),
            SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.6),
            ),
            SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded),
              label: Text(
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
      return _PhaseVisual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'فاز قاعدگی',
            en: "Menstrual phase",
          ),
          en: "Menstrual phase",
        ),
        Color(0xFFF15D7B),
        Color(0xFF9F2847),
      );
    case 'follicular':
    case 'post_period':
      return _PhaseVisual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'فاز فولیکولار',
            en: "Follicular phase",
          ),
          en: "Follicular phase",
        ),
        Color(0xFFB48BE1),
        Color(0xFF6F439F),
      );
    case 'fertile':
      return _PhaseVisual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'پنجره باروری تخمینی',
            en: "Estimated fertility window",
          ),
          en: "Estimated fertility window",
        ),
        Color(0xFF57C5B5),
        Color(0xFF247D72),
      );
    case 'ovulation':
      return _PhaseVisual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'روز تخمک‌گذاری تخمینی',
            en: "Estimated day of ovulation",
          ),
          en: "Estimated day of ovulation",
        ),
        Color(0xFF55A8E8),
        Color(0xFF286A9D),
      );
    case 'luteal':
    case 'cycle':
      return _PhaseVisual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'فاز لوتئال',
            en: "Luteal phase",
          ),
          en: "Luteal phase",
        ),
        Color(0xFFF3B651),
        Color(0xFF946517),
      );
    case 'pms':
    case 'pre_period':
      return _PhaseVisual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'روزهای پیش از دوره',
            en: "Days before the period",
          ),
          en: "Days before the period",
        ),
        Color(0xFFE88973),
        Color(0xFF9D4938),
      );
    default:
      return _PhaseVisual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'ریتم چرخه', en: "Cycle rhythm"),
          en: "Cycle rhythm",
        ),
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
      return _MoodVisual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'حال عالی', en: "great now"),
          en: "great now",
        ),
        '😊',
        Color(0xFF55B889),
      );
    case 'good':
      return _MoodVisual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'حال خوب', en: "good mood"),
          en: "good mood",
        ),
        '🙂',
        Color(0xFF8D78D5),
      );
    case 'neutral':
      return _MoodVisual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'حال معمولی', en: "Normal now"),
          en: "Normal now",
        ),
        '😐',
        Color(0xFFE7B650),
      );
    case 'low':
      return _MoodVisual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'انرژی کمتر', en: "Less energy"),
          en: "Less energy",
        ),
        '😔',
        Color(0xFFE78D69),
      );
    case 'overwhelmed':
      return _MoodVisual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تحت فشار',
            en: "under pressure",
          ),
          en: "under pressure",
        ),
        '😣',
        Color(0xFFE46178),
      );
    default:
      return _MoodVisual(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'ثبت نشده', en: "Not recorded"),
          en: "not registered",
        ),
        '🌸',
        Color(0xFFB68DD9),
      );
  }
}

String _symptomLabel(String code) {
  switch (code) {
    case 'cramps':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'درد شکم', en: "Abdominal pain"),
        en: "Abdominal pain",
      );
    case 'headache':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'سردرد', en: "headache"),
        en: "headache",
      );
    case 'bloating':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'نفخ', en: "flatulence"),
        en: "flatulence",
      );
    case 'fatigue':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'خستگی', en: "tiredness"),
        en: "tiredness",
      );
    case 'breast_tenderness':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'حساسیت سینه',
          en: "Breast tenderness",
        ),
        en: "Breast tenderness",
      );
    case 'back_pain':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'کمردرد', en: "back pain"),
        en: "back pain",
      );
    case 'sleep_change':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'تغییر خواب', en: "sleep change"),
        en: "sleep change",
      );
    case 'appetite_change':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'تغییر اشتها',
          en: "Change in appetite",
        ),
        en: "Change in appetite",
      );
    case 'no_symptom':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'بدون نشانه', en: "no sign"),
        en: "no sign",
      );
    default:
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'نشانه ثبت‌شده',
          en: "Registered mark",
        ),
        en: "Registered mark",
      );
  }
}

String _supportLabel(String type) {
  switch (type) {
    case 'hydration':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'آب یا نوشیدنی آماده کردم',
          en: "I prepared water or drink",
        ),
        en: "I prepared water or drink",
      );
    case 'rest':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'زمان استراحت فراهم کردم',
          en: "I provided rest time",
        ),
        en: "I provided rest time",
      );
    case 'warmth':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'گرمای ملایم آماده کردم',
          en: "I prepared gentle heat",
        ),
        en: "I prepared gentle heat",
      );
    case 'chores':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'در کارهای خانه کمک کردم',
          en: "I helped with the housework",
        ),
        en: "I helped with the housework",
      );
    case 'walk':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'پیاده‌روی کوتاه پیشنهاد دادم',
          en: "I suggested a short walk",
        ),
        en: "I suggested a short walk",
      );
    case 'checkin':
    case 'check_in':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'با آرامش حالش را پرسیدم',
          en: "I asked him calmly",
        ),
        en: "I asked him calmly",
      );
    default:
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'یک همراهی ثبت کردم',
          en: "I registered a companion",
        ),
        en: "I registered a companion",
      );
  }
}

String _compassionCopy(String? phase, String? mood) {
  if (mood == 'low' || mood == 'overwhelmed') {
    return LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'امروز شاید بیشتر از راه‌حل، به شنیده‌شدن نیاز داشته باشد. آرام بپرس چه کمکی دوست دارد و انتخابش را محترم بدان.',
        en: "Today, perhaps more than a solution, it needs to be heard. Ask calmly what kind of help he likes and respect his choice.",
      ),
      en: "Today, perhaps more than a solution, it needs to be heard. Ask calmly what kind of help he likes and respect his choice.",
    );
  }
  switch (phase) {
    case 'period':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'ممکن است استراحت، گرمای ملایم یا کمک کوچک در کارها خوشایند باشد؛ اول بپرس و بعد همراهی کن.',
          en: "Rest, gentle warmth, or a little help with chores may be welcome; Ask first and then accompany.",
        ),
        en: "Rest, gentle warmth, or a little help with chores may be welcome; Ask first and then accompany.",
      );
    case 'pms':
    case 'pre_period':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'امروز کمی صبورتر باش. یک گفت‌وگوی آرام، کم‌کردن فشار روز و احترام به نیازش می‌تواند ارزشمند باشد.',
          en: "Be a little more patient today. A calm conversation, de-stressing the day and respecting his needs can be valuable.",
        ),
        en: "Be a little more patient today. A calm conversation, de-stressing the day and respecting his needs can be valuable.",
      );
    case 'follicular':
    case 'post_period':
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'حال خوب را هم بدون انتظار و فشار شریک شو؛ یک برنامه سبک دونفره می‌تواند دلنشین باشد.',
          en: "Share the good mood without waiting and pressure; A two-person style program can be enjoyable.",
        ),
        en: "Share the good mood without waiting and pressure; A two-person style program can be enjoyable.",
      );
    default:
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'همراهی یعنی حضور آرام، پرسیدن بدون قضاوت و پذیرفتن اینکه نیاز امروز ممکن است با دیروز فرق داشته باشد.',
          en: "Companionship means being quietly present, asking questions without judgment, and accepting that today's needs may be different from yesterday's.",
        ),
        en: "Companionship means being quietly present, asking questions without judgment, and accepting that today's needs may be different from yesterday's.",
      );
  }
}
