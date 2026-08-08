import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../localization/app_localizations.dart';
import '../../models/schedule_item_model.dart';
import '../../providers/medication_provider.dart';
import '../../providers/notification_provider.dart';
import 'active_treatment_card.dart';
import 'home_schedule_loader.dart';
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
  Timer? _retryTimer;
  int _automaticRetryCount = 0;
  static const _maximumAutomaticRetries = 2;
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
    _retryTimer?.cancel();
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
      final snapshot = await const HomeScheduleLoader().load(
        api: api,
        fromDate: today,
        toDate: lastVisibleDay,
      );
      final currentUser = snapshot.currentUser;
      final plans = snapshot.treatmentPlans;
      final doses = snapshot.doseOccurrences;
      final careEvents = snapshot.careEvents;
      for (final failure in snapshot.failures) {
        debugPrint(
          'WellMate home partial load (${failure.source}): ${failure.error}',
        );
      }
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
            seriesId: event['seriesId']?.toString(),
            type: type,
            title:
                _nonEmpty(event['title']) ??
                (type == 'injection' ? 'تزریق' : 'ویزیت'),
            time: rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
            dosage: details,
            status: status,
            version: event['version'] is int ? event['version'] as int : 1,
            scheduledAtUtc: DateTime.tryParse(
              event['scheduledAtUtc']?.toString() ?? '',
            )?.toUtc(),
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
      _automaticRetryCount = 0;
      _retryTimer?.cancel();
      setState(() {
        _displayName = profile['displayName']?.toString().trim() ?? '';
        scheduleList = todayItems;
        _nextOccurrence = nextOccurrence;
        _hasTreatmentPlans = plans.isNotEmpty;
        isLoading = false;
      });

      final reminderWindow = allItems
          .where((item) {
            if (item.status != 'scheduled') return false;
            final scheduled = _scheduledDateTime(item);
            return scheduled != null && scheduled.isAfter(DateTime.now());
          })
          .toList(growable: false);
      context.read<MedicationProvider>().setScheduleItems(todayItems);
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
      if (_isTransientLoadError(error) &&
          _automaticRetryCount < _maximumAutomaticRetries) {
        _automaticRetryCount += 1;
        final delay = Duration(milliseconds: 500 * _automaticRetryCount);
        setState(() {
          isLoading = true;
          loadError = null;
        });
        _retryTimer?.cancel();
        _retryTimer = Timer(delay, _fetchScheduleFromBackend);
        return;
      }
      setState(() {
        isLoading = false;
        loadError = 'برنامه امروز دریافت نشد. اتصال را بررسی کنید.';
      });
    }
  }

  bool _isTransientLoadError(Object error) {
    if (error is LifeMateApiException) {
      return error.statusCode == 0 ||
          error.statusCode == 500 ||
          error.statusCode == 502 ||
          error.statusCode == 503 ||
          error.statusCode == 504;
    }
    if (error is HomeScheduleLoadException) {
      return error.failures.any(
        (failure) => _isTransientLoadError(failure.error),
      );
    }
    return false;
  }

  void _retryManually() {
    _automaticRetryCount = 0;
    _retryTimer?.cancel();
    _fetchScheduleFromBackend();
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

  double _progressValue(ScheduleItemModel item) {
    return 1.0 -
        (_calculateSecondsLeft(item) / 86400).clamp(0.0, 1.0).toDouble();
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

  Widget _buildNextOccurrenceCard({
    required ScheduleItemModel item,
    required TextStyle font,
    required bool isPersian,
  }) {
    final secondsLeft = _calculateSecondsLeft(item);
    if (item.type == 'medicine') {
      return ActiveTreatmentCard(
        treatmentName: item.title,
        dose: item.dosage,
        time: item.time,
        assetIconPath: _getAssetPath(item.type),
        progressValue: _progressValue(item),
        secondsLeft: secondsLeft,
        onTaken: _submitting.contains(item.id)
            ? null
            : () => _reportStatus(item, 'taken'),
        onSkipped: _submitting.contains(item.id)
            ? null
            : () => _reportStatus(item, 'skipped'),
        onEdit: widget.onOpenTreatments,
        isSubmitting: _submitting.contains(item.id),
        font: font,
      );
    }

    final isAppointment = item.type == 'appointment';
    final isMissed = item.status == 'missed';
    final eventLabel = isAppointment ? 'وقت ویزیت' : 'زمان تزریق';
    final missedColor = const Color(0xFFE06464);
    return ActiveTreatmentCard(
      treatmentName: item.title,
      dose: item.dosage,
      time: item.time,
      assetIconPath: _getAssetPath(item.type),
      progressValue: _progressValue(item),
      secondsLeft: secondsLeft,
      onTaken: null,
      onSkipped: null,
      onEdit: null,
      showActions: false,
      supportingText: isMissed
          ? '$eventLabel انجام‌نشده • ${item.time}'
          : '$eventLabel • ${item.time}',
      countdownLabel: isMissed ? (isPersian ? 'گذشته' : 'Missed') : null,
      accentColor: isMissed ? missedColor : AppColors.primary,
      progressColor: isMissed ? missedColor : AppColors.primaryLight,
      progressBackgroundColor: isMissed
          ? const Color(0xFFFFEEEE)
          : AppColors.background,
      fallbackIcon: isAppointment
          ? Icons.medical_services_rounded
          : Icons.vaccines_rounded,
      font: font,
    );
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
                      onPressed: _retryManually,
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
                  : _buildNextOccurrenceCard(
                      item: nextItem,
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
                                  16,
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
                                        item.type == 'medicine' &&
                                            missed &&
                                            !_submitting.contains(item.id)
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
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
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
