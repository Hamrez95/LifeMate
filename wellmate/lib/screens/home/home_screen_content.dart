import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/string_extensions.dart';
import '../../localization/app_localizations.dart';
import '../../models/schedule_item_model.dart';
import '../../providers/medication_provider.dart';
import '../../providers/notification_provider.dart';
import 'active_treatment_card.dart';
import 'soft_schedule_card.dart';

class HomeScreenContent extends StatefulWidget {
  const HomeScreenContent({
    super.key,
    required this.onOpenTreatments,
    required this.onAddTreatment,
  });

  final VoidCallback onOpenTreatments;
  final VoidCallback onAddTreatment;

  @override
  State<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<HomeScreenContent> {
  List<ScheduleItemModel> scheduleList = const [];
  ScheduleItemModel? _nextOccurrence;
  Timer? _timer;
  bool isLoading = true;
  String? loadError;
  String _displayName = '';
  bool _hasTreatmentPlans = false;
  final Set<String> _submitting = <String>{};

  @override
  void initState() {
    super.initState();
    _fetchScheduleFromBackend();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchScheduleFromBackend() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        loadError = null;
      });
    }
    try {
      final api = context.read<LifeMateApiClient>();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastVisibleDay = today.add(const Duration(days: 7));
      final results = await Future.wait<dynamic>([
        api.getCurrentUser(),
        api.getTreatmentPlans(),
        api.getDoseOccurrences(fromDate: today, toDate: lastVisibleDay),
        api.getCareEvents(fromDate: today, toDate: lastVisibleDay),
      ]);
      final currentUser = results[0] as Map<String, dynamic>;
      final plans = results[1] as List<Map<String, dynamic>>;
      final doses = results[2] as List<Map<String, dynamic>>;
      final careEvents = results[3] as List<Map<String, dynamic>>;
      final profile =
          currentUser['profile'] as Map<String, dynamic>? ?? const {};
      final plansById = <String, Map<String, dynamic>>{
        for (final plan in plans) plan['id'].toString(): plan,
      };

      final allItems = <ScheduleItemModel>[
        ...doses.map((dose) {
          final plan =
              plansById[dose['treatmentPlanId'].toString()] ?? const {};
          final medication = plan['medication'] is Map<String, dynamic>
              ? plan['medication'] as Map<String, dynamic>
              : const <String, dynamic>{};
          final status = (dose['status'] ?? 'scheduled').toString();
          final rawTime = (dose['scheduledLocalTime'] ?? '').toString();
          final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
          return ScheduleItemModel(
            id: dose['id'].toString(),
            type: 'medicine',
            title: (medication['name'] ?? 'دارو').toString(),
            time: time,
            dosage: (plan['doseText'] ?? '').toString(),
            status: status,
            version: dose['version'] is int ? dose['version'] as int : 1,
            scheduledAtUtc: DateTime.tryParse(
              dose['scheduledAtUtc']?.toString() ?? '',
            )?.toUtc(),
            isDone: status == 'taken' || status == 'skipped',
            frequency: 'طبق برنامه درمان',
            startDate: dose['scheduledLocalDate'] == null
                ? today
                : DateTime.tryParse(dose['scheduledLocalDate'].toString()),
            intervalDays: 1,
            patientReminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
              dose['patientReminderMinutesBefore'],
              fallback: LifeMateReminderLeadTimes.defaultPatientMinutes,
            ),
            caregiverReminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
              dose['caregiverReminderMinutesBefore'],
              fallback: LifeMateReminderLeadTimes.defaultCaregiverMinutes,
            ),
          );
        }),
        ...careEvents.map((event) {
          final eventType = event['eventType']?.toString().toLowerCase();
          final type = eventType == 'injection' ? 'injection' : 'appointment';
          final rawTime = event['scheduledLocalTime']?.toString() ?? '--:--';
          final rawStatus =
              event['status']?.toString().toLowerCase() ?? 'scheduled';
          final status = rawStatus == 'scheduled' && _isPastCareEvent(event)
              ? 'missed'
              : rawStatus;
          final details = <String>[
            if (type == 'appointment')
              _nonEmpty(event['providerName']) ??
                  _nonEmpty(event['specialty']) ??
                  '',
            if (type == 'injection') _nonEmpty(event['doseText']) ?? '',
            _nonEmpty(event['centerName']) ?? '',
          ].where((value) => value.isNotEmpty).join(' • ');
          return ScheduleItemModel(
            id: event['id']?.toString() ?? '',
            type: type,
            title:
                _nonEmpty(event['title']) ??
                (type == 'injection' ? 'تزریق' : 'ویزیت'),
            time: rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
            dosage: details,
            status: status,
            version: event['version'] is int ? event['version'] as int : 1,
            isDone: status == 'completed' || status == 'cancelled',
            frequency: type == 'injection' ? 'تزریق' : 'ویزیت',
            startDate: DateTime.tryParse(
              event['scheduledLocalDate']?.toString() ?? '',
            ),
            intervalDays: 1,
            patientReminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
              event['patientReminderMinutesBefore'],
              fallback: LifeMateReminderLeadTimes.defaultPatientMinutes,
            ),
            caregiverReminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
              event['caregiverReminderMinutesBefore'],
              fallback: LifeMateReminderLeadTimes.defaultCaregiverMinutes,
            ),
          );
        }),
      ]..sort(_compareOccurrence);

      final todayItems = allItems
          .where((item) {
            final date = item.startDate;
            return date != null && _sameDay(date, today);
          })
          .toList(growable: false);
      final actionable = allItems
          .where((item) {
            if (item.type == 'medicine') {
              return item.status == 'scheduled' || item.status == 'missed';
            }
            return item.status != 'completed' && item.status != 'cancelled';
          })
          .toList(growable: false);
      final future =
          actionable
              .where((item) {
                final scheduled = _scheduledDateTime(item);
                return scheduled != null && !scheduled.isBefore(DateTime.now());
              })
              .toList(growable: false)
            ..sort(_compareOccurrence);
      final missedOccurrences =
          actionable
              .where((item) => item.status == 'missed')
              .toList(growable: false)
            ..sort(_compareOccurrence);
      final nextOccurrence = future.isNotEmpty
          ? future.first
          : (missedOccurrences.isNotEmpty ? missedOccurrences.first : null);

      if (!mounted) return;
      setState(() {
        _displayName = profile['displayName']?.toString().trim() ?? '';
        scheduleList = todayItems;
        _nextOccurrence = nextOccurrence;
        _hasTreatmentPlans = plans.isNotEmpty;
        isLoading = false;
      });

      final medicineToday = todayItems
          .where((item) => item.type == 'medicine')
          .toList(growable: false);
      final reminderWindow = allItems
          .where((item) {
            if (item.status != 'scheduled') return false;
            final scheduled = _scheduledDateTime(item);
            return scheduled != null && scheduled.isAfter(DateTime.now());
          })
          .toList(growable: false);
      context.read<MedicationProvider>().setMedications(medicineToday);
      try {
        await context.read<NotificationProvider>().syncReminders(
          reminderWindow,
          timeZone: profile['timeZone']?.toString() ?? 'Asia/Tehran',
          isPersian: Localizations.localeOf(context).languageCode == 'fa',
        );
      } catch (error) {
        debugPrint('WellMate reminder sync failed: $error');
      }
    } catch (error) {
      debugPrint('WellMate home schedule sync failed: $error');
      if (!mounted) return;
      setState(() {
        isLoading = false;
        loadError = 'برنامه امروز دریافت نشد. اتصال را بررسی کنید.';
      });
    }
  }

  Future<void> _reportStatus(ScheduleItemModel item, String status) async {
    if (item.type != 'medicine' || _submitting.contains(item.id)) return;
    setState(() => _submitting.add(item.id));
    try {
      final result = await context.read<LifeMateApiClient>().reportDose(
        occurrenceId: item.id,
        clientRequestId: LifeMateApiClient.createClientRequestId(),
        version: item.version,
        status: status,
        occurredAtUtc: DateTime.now().toUtc(),
      );
      if (!mounted) return;
      final updated = item.copyWith(
        isDone: status == 'taken' || status == 'skipped',
        status: (result['status'] ?? status).toString(),
        version: result['version'] is int
            ? result['version'] as int
            : item.version + 1,
      );
      setState(() {
        final index = scheduleList.indexWhere((value) => value.id == item.id);
        if (index >= 0) scheduleList[index] = updated;
        if (_nextOccurrence?.id == item.id) _nextOccurrence = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'taken'
                ? '${item.title} به عنوان مصرف‌شده ثبت شد.'
                : '${item.title} به عنوان مصرف‌نشده ثبت شد.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _fetchScheduleFromBackend();
    } catch (error) {
      debugPrint('WellMate dose report failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ثبت مصرف انجام نشد؛ دوباره تلاش کنید.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting.remove(item.id));
    }
  }

  int _calculateSecondsLeft(ScheduleItemModel item) {
    final scheduled = _scheduledDateTime(item);
    if (scheduled == null) return 0;
    final seconds = scheduled.difference(DateTime.now()).inSeconds;
    return seconds > 0 ? seconds : 0;
  }

  String _getAssetPath(String type) {
    switch (type) {
      case 'appointment':
      case 'visit':
        return 'assets/icons/stethoscope.png';
      case 'drop':
        return 'assets/icons/water_drop.png';
      default:
        return 'assets/icons/pill.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final font = AppTextStyles.body(context);
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final visibleToday = scheduleList.where((item) => !item.isDone).toList()
      ..sort(_compareOccurrence);
    final nextItem = _nextOccurrence;

    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 16),
            child: Text(
              isPersian
                  ? (_displayName.isEmpty ? 'سلام،' : 'سلام $_displayName جان،')
                  : (_displayName.isEmpty ? 'Hello,' : 'Hi $_displayName,'),
              style: font.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (loadError != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 52),
                    const SizedBox(height: 12),
                    Text(loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _fetchScheduleFromBackend,
                      child: const Text('تلاش دوباره'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: nextItem == null
                  ? _TreatmentTimerPlaceholder(
                      hasTreatmentPlans: _hasTreatmentPlans,
                      onAction: _hasTreatmentPlans
                          ? widget.onOpenTreatments
                          : widget.onAddTreatment,
                      font: font,
                    )
                  : nextItem.type == 'medicine'
                  ? ActiveTreatmentCard(
                      treatmentName: nextItem.title,
                      dose: nextItem.dosage,
                      time: nextItem.time,
                      assetIconPath: _getAssetPath(nextItem.type),
                      progressValue:
                          1.0 -
                          (_calculateSecondsLeft(nextItem) / 86400).clamp(
                            0.0,
                            1.0,
                          ),
                      secondsLeft: _calculateSecondsLeft(nextItem),
                      onTaken: _submitting.contains(nextItem.id)
                          ? null
                          : () => _reportStatus(nextItem, 'taken'),
                      onSkipped: _submitting.contains(nextItem.id)
                          ? null
                          : () => _reportStatus(nextItem, 'skipped'),
                      onEdit: widget.onOpenTreatments,
                      isSubmitting: _submitting.contains(nextItem.id),
                      font: font,
                    )
                  : _UpcomingCareEventCard(
                      item: nextItem,
                      isMissed: nextItem.status == 'missed',
                      secondsLeft: _calculateSecondsLeft(nextItem),
                      assetPath: _getAssetPath(nextItem.type),
                      font: font,
                      isPersian: isPersian,
                    ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        24,
                        24,
                        24,
                        16,
                      ),
                      child: Text(
                        loc['today_schedule'] ?? 'برنامه امروز',
                        style: font.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: visibleToday.isEmpty
                          ? _HomeEmptyState(
                              hasTreatmentPlans: _hasTreatmentPlans,
                              onAddTreatment: widget.onAddTreatment,
                              font: font,
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchScheduleFromBackend,
                              child: ListView.separated(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  24,
                                  0,
                                  24,
                                  110,
                                ),
                                itemCount: visibleToday.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final item = visibleToday[index];
                                  final missed = item.status == 'missed';
                                  return SoftScheduleCard(
                                    item: item,
                                    index: index,
                                    font: font,
                                    assetPath: _getAssetPath(item.type),
                                    isMissed: missed,
                                    onTaken:
                                        missed && !_submitting.contains(item.id)
                                        ? () => _reportStatus(item, 'taken')
                                        : null,
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static bool _isPastCareEvent(Map<String, dynamic> event) {
    final date = DateTime.tryParse(
      event['scheduledLocalDate']?.toString() ?? '',
    );
    final parts =
        event['scheduledLocalTime']?.toString().split(':') ?? const [];
    if (date == null || parts.length < 2) return false;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return false;
    return DateTime(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    ).isBefore(DateTime.now());
  }

  static DateTime? _scheduledDateTime(ScheduleItemModel item) {
    if (item.scheduledAtUtc != null) return item.scheduledAtUtc!.toLocal();
    final date = item.startDate;
    final parts = item.time.split(':');
    if (date == null || parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1].split(' ').first);
    if (hour == null || minute == null) return null;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static int _compareOccurrence(
    ScheduleItemModel left,
    ScheduleItemModel right,
  ) {
    final leftDate = _scheduledDateTime(left) ?? DateTime(2100);
    final rightDate = _scheduledDateTime(right) ?? DateTime(2100);
    return leftDate.compareTo(rightDate);
  }

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

class _UpcomingCareEventCard extends StatelessWidget {
  const _UpcomingCareEventCard({
    required this.item,
    required this.isMissed,
    required this.secondsLeft,
    required this.font,
    required this.isPersian,
    required this.assetPath,
  });

  final ScheduleItemModel item;
  final bool isMissed;
  final int secondsLeft;
  final TextStyle font;
  final bool isPersian;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    final isAppointment = item.type == 'appointment';
    final accent = isMissed
        ? const Color(0xFFE06464)
        : isAppointment
        ? const Color(0xFF5AA7DF)
        : const Color(0xFFD95B93);
    final soft = isMissed
        ? const Color(0xFFFFEEEE)
        : isAppointment
        ? const Color(0xFFEAF7FD)
        : const Color(0xFFFFEDF5);
    final compactCountdown = isMissed
        ? (isPersian ? 'گذشته' : 'Missed')
        : _formatCompactCountdown(secondsLeft, isPersian);
    final fullCountdown = isMissed
        ? (isPersian ? 'زمان این رویداد گذشته است' : 'This event time has passed')
        : _formatCareEventCountdown(secondsLeft, isPersian);
    final time = item.time.toPersianDigit(isPersian);

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(18, 20, 18, 20),
      decoration: BoxDecoration(
        color: isMissed ? const Color(0xFFFFFAFA) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: isMissed ? Border.all(color: accent.withValues(alpha: 0.28)) : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withValues(alpha: 0.65),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 10,
            offset: Offset(-5, -5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 330;
          final countdown = _CareEventCountdownDial(
            assetPath: assetPath,
            accent: accent,
            soft: soft,
            secondsLeft: secondsLeft,
            label: compactCountdown,
          );
          final details = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isMissed
                    ? (isAppointment ? 'ویزیت انجام‌نشده' : 'تزریق انجام‌نشده')
                    : (isAppointment ? 'وقت ویزیت' : 'یادآوری تزریق'),
                style: font.copyWith(
                  color: accent,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: font.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  height: 1.35,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (item.dosage.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  item.dosage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: font.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _CareEventInfoPill(
                    icon: Icons.schedule_rounded,
                    label: time,
                    accent: accent,
                    forceLtr: true,
                  ),
                  Semantics(
                    label: fullCountdown,
                    child: Text(
                      fullCountdown,
                      style: font.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              children: [
                countdown,
                const SizedBox(height: 16),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: details,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              countdown,
              const SizedBox(width: 18),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}

class _CareEventCountdownDial extends StatelessWidget {
  const _CareEventCountdownDial({
    required this.assetPath,
    required this.accent,
    required this.soft,
    required this.secondsLeft,
    required this.label,
  });

  final String assetPath;
  final Color accent;
  final Color soft;
  final int secondsLeft;
  final String label;

  @override
  Widget build(BuildContext context) {
    final progress = secondsLeft <= 0
        ? 1.0
        : (1 - (secondsLeft.clamp(0, 86400) / 86400))
              .clamp(0.08, 1.0)
              .toDouble();
    return Semantics(
      label: 'شمارش معکوس $label',
      image: true,
      child: SizedBox.square(
        dimension: 112,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.square(
              dimension: 112,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 8,
                strokeCap: StrokeCap.round,
                backgroundColor: soft,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
              padding: const EdgeInsets.all(9),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    assetPath,
                    width: 34,
                    height: 34,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.event_available_rounded,
                      color: accent,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          color: accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CareEventInfoPill extends StatelessWidget {
  const _CareEventInfoPill({
    required this.icon,
    required this.label,
    required this.accent,
    this.forceLtr = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final bool forceLtr;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: accent,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: forceLtr
          ? Directionality(textDirection: TextDirection.ltr, child: content)
          : content,
    );
  }
}

String _formatCareEventCountdown(int seconds, bool isPersian) {
  if (seconds <= 0) return isPersian ? 'اکنون' : 'Now';
  final totalMinutes = (seconds / 60).ceil();
  final days = totalMinutes ~/ (24 * 60);
  final hours = (totalMinutes % (24 * 60)) ~/ 60;
  final minutes = totalMinutes % 60;
  final raw = days > 0
      ? (isPersian
            ? '$days روز و $hours ساعت دیگر'
            : 'in $days days and $hours hours')
      : hours > 0
      ? (isPersian
            ? '$hours ساعت و $minutes دقیقه دیگر'
            : 'in $hours hours and $minutes minutes')
      : (isPersian ? '$minutes دقیقه دیگر' : 'in $minutes minutes');
  return raw.toPersianDigit(isPersian);
}

String _formatCompactCountdown(int seconds, bool isPersian) {
  if (seconds <= 0) return isPersian ? 'اکنون' : 'Now';
  final totalMinutes = (seconds / 60).ceil();
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  final raw = hours > 0
      ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}'
      : '$minutes ${isPersian ? 'دقیقه' : 'min'}';
  return raw.toPersianDigit(isPersian);
}

class _TreatmentTimerPlaceholder extends StatelessWidget {
  const _TreatmentTimerPlaceholder({
    required this.hasTreatmentPlans,
    required this.onAction,
    required this.font,
  });

  final bool hasTreatmentPlans;
  final VoidCallback onAction;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 48,
            backgroundColor: Color(0xFFF1FAF5),
            child: Icon(
              Icons.medication_rounded,
              size: 44,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasTreatmentPlans
                      ? 'برنامه بعدی در اینجا نمایش داده می‌شود'
                      : 'تایمر درمان آماده است',
                  style: font.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasTreatmentPlans
                      ? 'برای دیدن جزئیات، برنامه درمان را باز کنید.'
                      : 'پس از ثبت اولین دارو یا ویزیت، شمارش معکوس اینجا دیده می‌شود.',
                  style: font.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(hasTreatmentPlans ? 'درمان‌ها' : 'افزودن برنامه'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState({
    required this.hasTreatmentPlans,
    required this.onAddTreatment,
    required this.font,
  });

  final bool hasTreatmentPlans;
  final VoidCallback onAddTreatment;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 110),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 48,
              backgroundColor: Color(0xFFE7F8F1),
              child: Icon(
                Icons.medication_liquid_rounded,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasTreatmentPlans
                  ? 'برای امروز برنامه‌ای باقی نمانده است.'
                  : 'هنوز برنامه درمانی ثبت نشده است.',
              textAlign: TextAlign.center,
              style: font.copyWith(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              hasTreatmentPlans
                  ? 'برنامه‌های دارویی، ویزیت و تزریق بعدی به‌صورت خودکار نمایش داده می‌شوند.'
                  : 'اولین دارو، ویزیت یا تزریق را اضافه کنید.',
              textAlign: TextAlign.center,
              style: font.copyWith(color: AppColors.textSecondary),
            ),
            if (!hasTreatmentPlans) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onAddTreatment,
                icon: const Icon(Icons.add_rounded),
                label: const Text('افزودن برنامه'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
