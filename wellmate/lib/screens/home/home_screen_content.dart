import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../localization/app_localizations.dart';
import '../../models/schedule_item_model.dart';
import '../../providers/medication_provider.dart';
import '../../providers/notification_provider.dart';
import '../treatments/edit_care_event_screen.dart';
import 'active_treatment_card.dart';
import 'home_schedule_loader.dart';
import 'pending_treatment_create_presentation.dart';
import 'soft_schedule_card.dart';

class HomeScreenContent extends StatefulWidget {
  const HomeScreenContent({
    super.key,
    required this.onOpenTreatments,
    required this.onAddTreatment,
    required this.onOpenHealth,
    this.refreshToken = 0,
  });

  final VoidCallback onOpenTreatments;
  final VoidCallback onAddTreatment;
  final VoidCallback onOpenHealth;
  final int refreshToken;

  @override
  State<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<HomeScreenContent> {
  List<ScheduleItemModel> scheduleList = const [];
  List<ScheduleItemModel> _countdownOccurrences = const [];
  Timer? _timer;
  Timer? _retryTimer;
  int _automaticRetryCount = 0;
  static const _maximumAutomaticRetries = 2;
  bool isLoading = true;
  String? loadError;
  String _displayName = '';
  bool _hasTreatmentPlans = false;
  List<PendingTreatmentCreateOccurrence> _pendingTreatmentCreates = const [];
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
  void didUpdateWidget(covariant HomeScreenContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _fetchScheduleFromBackend(background: true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchScheduleFromBackend({bool background = false}) async {
    if (mounted) {
      setState(() {
        if (scheduleList.isEmpty && _countdownOccurrences.isEmpty) {
          isLoading = true;
        }
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
      final pendingTreatmentCreates = projectPendingTreatmentCreates(
        pendingCreates: snapshot.pendingTreatmentCreates,
        fromDate: today,
        toDate: lastVisibleDay,
      );
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
          final pending =
              dose['pendingSync'] == true || status == 'pending_sync';
          final rawTime = (dose['scheduledLocalTime'] ?? '').toString();
          final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
          return ScheduleItemModel(
            id: dose['id'].toString(),
            type: 'medicine',
            title:
                (medication['name'] ??
                        LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'دارو',
                            en: "Medication",
                          ),
                          en: "medicine",
                        ))
                    .toString(),
            time: time,
            dosage: (plan['doseText'] ?? '').toString(),
            status: status,
            version: dose['version'] is int ? dose['version'] as int : 1,
            scheduledAtUtc: DateTime.tryParse(
              dose['scheduledAtUtc']?.toString() ?? '',
            )?.toUtc(),
            isDone: pending ? false : status == 'taken' || status == 'skipped',
            pendingSync: pending,
            pendingStatus: dose['pendingStatus']?.toString(),
            frequency: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'طبق برنامه درمان',
                en: "According to the treatment plan",
              ),
              en: "According to the treatment plan",
            ),
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
                (type == 'injection'
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
            time: rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
            dosage: details,
            status: status,
            version: event['version'] is int ? event['version'] as int : 1,
            scheduledAtUtc: DateTime.tryParse(
              event['scheduledAtUtc']?.toString() ?? '',
            )?.toUtc(),
            isDone: status == 'completed' || status == 'cancelled',
            frequency: type == 'injection'
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
      final countdownOccurrences = selectHomeCountdownItems(
        allItems,
        DateTime.now(),
      );

      if (!mounted) return;
      _automaticRetryCount = 0;
      _retryTimer?.cancel();
      setState(() {
        _displayName = profile['displayName']?.toString().trim() ?? '';
        scheduleList = todayItems;
        _countdownOccurrences = countdownOccurrences;
        _pendingTreatmentCreates = pendingTreatmentCreates;
        _hasTreatmentPlans =
            plans.isNotEmpty || pendingTreatmentCreates.isNotEmpty;
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
        loadError = LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'برنامه امروز دریافت نشد. اتصال را بررسی کنید.',
            en: "Today's program was not received. Check the connection.",
          ),
          en: "Today's program was not received. Check the connection.",
        );
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
      final pendingSync = result['pendingSync'] == true;
      final updated = item.copyWith(
        isDone: pendingSync ? false : status == 'taken' || status == 'skipped',
        pendingSync: pendingSync,
        pendingStatus: pendingSync ? status : null,
        status: (result['status'] ?? status).toString(),
        version: result['version'] is int
            ? result['version'] as int
            : item.version + 1,
      );
      setState(() {
        final index = scheduleList.indexWhere((value) => value.id == item.id);
        if (index >= 0) scheduleList[index] = updated;
        _countdownOccurrences = _countdownOccurrences
            .where((value) => value.id != item.id)
            .toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pendingSync
                ? LifeMateRuntimeLocale.select(
                    fa: '${item.title} روی گوشی ذخیره شد و بعد از اتصال اینترنت همگام می‌شود.',
                    en: '${item.title} was saved on this device and will sync when you reconnect.',
                  )
                : status == 'taken'
                ? LifeMateRuntimeLocale.select(
                    fa: '${item.title} به عنوان مصرف‌شده ثبت شد.',
                    en: '${item.title} was marked as taken.',
                  )
                : LifeMateRuntimeLocale.select(
                    fa: '${item.title} به عنوان مصرف‌نشده ثبت شد.',
                    en: '${item.title} was marked as skipped.',
                  ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _fetchScheduleFromBackend();
    } catch (error) {
      debugPrint('WellMate dose report failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'ثبت مصرف انجام نشد؛ دوباره تلاش کنید.',
                  en: "Consumption registration was not done; Try again.",
                ),
                en: "Consumption registration was not done; Try again.",
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting.remove(item.id));
    }
  }

  Future<void> _reportCareEventStatus(
    ScheduleItemModel item,
    String status,
  ) async {
    if (item.type == 'medicine' || _submitting.contains(item.id)) return;
    final eventId = item.seriesId ?? item.id;
    if (eventId.isEmpty) return;

    // The current recurrence contract stores status on the series row. Never
    // silently complete/cancel an entire recurring series from one occurrence.
    if (item.seriesId != null && item.id != item.seriesId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'ثبت وضعیت یک نوبت تکرارشونده از این کارت هنوز پشتیبانی نمی‌شود.',
                  en: "Registering the status of a recurring turn from this card is not yet supported.",
                ),
                en: "Registering the status of a recurring turn from this card is not yet supported.",
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _submitting.add(item.id));
    try {
      final result = await LifeMateEditApi.fromEnvironment()
          .updateCareEventStatus(eventId: eventId, status: status);
      if (!mounted) return;
      final normalized = (result['status'] ?? status).toString().toLowerCase();
      final updated = item.copyWith(
        isDone: normalized == 'completed' || normalized == 'cancelled',
        status: normalized,
        version: result['version'] is int
            ? result['version'] as int
            : item.version + 1,
      );
      setState(() {
        final index = scheduleList.indexWhere((value) => value.id == item.id);
        if (index >= 0) scheduleList[index] = updated;
        _countdownOccurrences = _countdownOccurrences
            .where((value) => value.id != item.id)
            .toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'completed'
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: '${item.title} به عنوان انجام‌شده ثبت شد.',
                      en: "${item.title} was marked as done.",
                    ),
                    en: "${item.title} registered as done.",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: '${item.title} به عنوان انجام‌نشده ثبت شد.',
                      en: "${item.title} was marked as not done.",
                    ),
                    en: "${item.title} was registered as not committed.",
                  ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _fetchScheduleFromBackend();
    } catch (error) {
      debugPrint('WellMate care event status report failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'ثبت وضعیت انجام نشد؛ دوباره تلاش کنید.',
                  en: "status registration was not done; Try again.",
                ),
                en: "status registration was not done; Try again.",
              ),
            ),
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

  String? _getAssetPath(String type) {
    switch (type) {
      case 'appointment':
      case 'visit':
        return 'assets/icons/stethoscope.png';
      case 'injection':
        return null;
      case 'drop':
        return 'assets/icons/water_drop.png';
      default:
        return 'assets/icons/pill.png';
    }
  }

  Future<void> _editCareEvent(ScheduleItemModel item) async {
    final eventId = item.seriesId ?? item.id;
    if (eventId.isEmpty || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => EditCareEventScreen(eventId: eventId),
      ),
    );
    if (mounted) await _fetchScheduleFromBackend();
  }

  Widget _buildNextOccurrenceCard({
    required ScheduleItemModel item,
    required TextStyle font,
    required bool isPersian,
  }) {
    final secondsLeft = _calculateSecondsLeft(item);
    final overdue = isHomeScheduleOverdue(item, DateTime.now());
    if (item.type == 'medicine') {
      const missedColor = Color(0xFFE06464);
      return ActiveTreatmentCard(
        key: ValueKey('home-countdown-${item.type}-${item.id}'),
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
        supportingText: overdue
            ? (isPersian
                  ? LifeMateRuntimeLocale.select(
                      fa: 'مصرف‌نشده • ${item.time}',
                      en: "Unused • ${item.time}",
                    )
                  : 'Missed • ${item.time}')
            : null,
        countdownLabel: overdue ? (isPersian ? 'گذشته' : 'Missed') : null,
        accentColor: overdue ? missedColor : null,
        progressColor: overdue ? missedColor : null,
        progressBackgroundColor: overdue ? Color(0xFFFFEEEE) : null,
        font: font,
      );
    }

    final isAppointment = item.type == 'appointment';
    final isMissed = item.status == 'missed';
    final eventLabel = isAppointment
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'وقت ویزیت',
              en: "Visiting time",
            ),
            en: "Visiting time",
          )
        : LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'زمان تزریق',
              en: "injection time",
            ),
            en: "injection time",
          );
    final missedColor = const Color(0xFFE06464);
    final eventAccent = isAppointment
        ? AppColors.careVisit
        : AppColors.careInjection;
    return ActiveTreatmentCard(
      key: ValueKey('home-countdown-${item.type}-${item.id}'),
      treatmentName: item.title,
      dose: item.dosage,
      time: item.time,
      assetIconPath: item.type == 'injection' ? null : _getAssetPath(item.type),
      progressValue: _progressValue(item),
      secondsLeft: secondsLeft,
      onTaken: _submitting.contains(item.id)
          ? null
          : () => _reportCareEventStatus(item, 'completed'),
      onSkipped: _submitting.contains(item.id)
          ? null
          : () => _reportCareEventStatus(item, 'cancelled'),
      onEdit: _submitting.contains(item.id) ? null : () => _editCareEvent(item),
      isSubmitting: _submitting.contains(item.id),
      primaryActionLabel: isPersian
          ? LifeMateRuntimeLocale.select(fa: 'انجام شد', en: "Done")
          : 'Done',
      editActionLabel: isPersian
          ? LifeMateRuntimeLocale.select(fa: 'ویرایش', en: "Edit")
          : 'Edit',
      secondaryActionLabel: isPersian
          ? LifeMateRuntimeLocale.select(fa: 'انجام نشد', en: "not done")
          : 'Not done',
      supportingText: isMissed
          ? LifeMateRuntimeLocale.select(
              fa: '$eventLabel انجام‌نشده • ${item.time}',
              en: "$eventLabel not done • ${item.time}",
            )
          : '$eventLabel • ${item.time}',
      countdownLabel: isMissed
          ? (isPersian
                ? LifeMateRuntimeLocale.select(fa: 'گذشته', en: "the past")
                : 'Missed')
          : null,
      accentColor: isMissed ? missedColor : eventAccent,
      progressColor: isMissed ? missedColor : eventAccent,
      progressBackgroundColor: isMissed
          ? Color(0xFFFFEEEE)
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
    final now = DateTime.now();
    final visibleToday = scheduleList.where((item) => !item.isDone).toList()
      ..sort((left, right) => compareHomeScheduleForDisplay(left, right, now));
    final countdownItems = _countdownOccurrences;

    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(24, 20, 24, 16),
            child: Text(
              isPersian
                  ? (_displayName.isEmpty
                        ? LifeMateRuntimeLocale.select(
                            fa: 'سلام،',
                            en: "Hello,",
                          )
                        : LifeMateRuntimeLocale.select(
                            fa: 'سلام $_displayName جان،',
                            en: "Hi $_displayName John,",
                          ))
                  : (_displayName.isEmpty ? 'Hello,' : 'Hi $_displayName,'),
              style: font.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (isLoading)
            Expanded(child: Center(child: CircularProgressIndicator()))
          else if (loadError != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 52),
                    SizedBox(height: 12),
                    Text(loadError!, textAlign: TextAlign.center),
                    SizedBox(height: 14),
                    FilledButton(
                      onPressed: _retryManually,
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
            )
          else ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: countdownItems.isEmpty
                  ? _TreatmentTimerPlaceholder(
                      hasTreatmentPlans: _hasTreatmentPlans,
                      onAction: _hasTreatmentPlans
                          ? widget.onOpenTreatments
                          : widget.onAddTreatment,
                      font: font,
                    )
                  : _buildNextOccurrenceCard(
                      item: countdownItems.first,
                      font: font,
                      isPersian: isPersian,
                    ),
            ),
            if (_pendingTreatmentCreates.isNotEmpty) ...[
              SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: PendingTreatmentCreateCard(
                  occurrence: _pendingTreatmentCreates.first,
                  pendingCount: _pendingTreatmentCreates.length,
                  font: font,
                  isPersian: isPersian,
                ),
              ),
            ],
            SizedBox(height: 14),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: _HomeHealthCard(onTap: widget.onOpenHealth),
            ),
            SizedBox(height: 14),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, 16),
                      child: Text(
                        loc['today_schedule'] ??
                            LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'برنامه امروز',
                                en: "Today's program",
                              ),
                              en: "Today's program",
                            ),
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
                                padding: EdgeInsetsDirectional.fromSTEB(
                                  24,
                                  0,
                                  24,
                                  16,
                                ),
                                itemCount: visibleToday.length,
                                separatorBuilder: (_, __) =>
                                    SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final item = visibleToday[index];
                                  final missed = isHomeScheduleOverdue(
                                    item,
                                    now,
                                  );
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
                                    onCompleted:
                                        item.type != 'medicine' &&
                                            missed &&
                                            !_submitting.contains(item.id)
                                        ? () => _reportCareEventStatus(
                                            item,
                                            'completed',
                                          )
                                        : null,
                                    onNotCompleted:
                                        item.type != 'medicine' &&
                                            missed &&
                                            !_submitting.contains(item.id)
                                        ? () => _reportCareEventStatus(
                                            item,
                                            'cancelled',
                                          )
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

class _HomeHealthCard extends StatelessWidget {
  const _HomeHealthCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final title = LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سلامت من', en: "My Health"),
      en: "My Health",
    );
    final subtitle = LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ثبت سریع و مرور تاریخچه سلامت',
        en: "Quick log and health history",
      ),
      en: "Quick log and health history",
    );
    return Semantics(
      button: true,
      label: LifeMateRuntimeLocale.select(
        fa: 'باز کردن $title',
        en: 'Open $title',
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          key: const ValueKey('home-health-card'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(16, 14, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.monitor_heart_rounded,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: AppColors.textPrimary.withValues(
                              alpha: 0.62,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    isPersian
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
List<ScheduleItemModel> selectHomeCountdownItems(
  Iterable<ScheduleItemModel> items,
  DateTime now, {
  int limit = 1,
}) {
  final actionable = items
      .where((item) {
        if (item.type == 'medicine') {
          return item.status == 'scheduled' || item.status == 'missed';
        }
        return item.status != 'completed' && item.status != 'cancelled';
      })
      .toList(growable: false);

  final future =
      actionable.where((item) {
        final scheduled = _homeCountdownScheduledDateTime(item);
        return scheduled != null && !scheduled.isBefore(now);
      }).toList()..sort((left, right) {
        final l = _homeCountdownScheduledDateTime(left) ?? DateTime(2100);
        final r = _homeCountdownScheduledDateTime(right) ?? DateTime(2100);
        return l.compareTo(r);
      });

  if (future.isNotEmpty) return future.take(limit).toList(growable: false);

  final missed = actionable.where((item) => item.status == 'missed').toList()
    ..sort((left, right) {
      final l = _homeCountdownScheduledDateTime(left) ?? DateTime(2100);
      final r = _homeCountdownScheduledDateTime(right) ?? DateTime(2100);
      return l.compareTo(r);
    });
  return missed.take(1).toList(growable: false);
}

DateTime? _homeCountdownScheduledDateTime(ScheduleItemModel item) {
  if (item.scheduledAtUtc != null) return item.scheduledAtUtc!.toLocal();
  final date = item.startDate;
  final parts = item.time.split(':');
  if (date == null || parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1].split(' ').first);
  if (hour == null || minute == null) return null;
  return DateTime(date.year, date.month, date.day, hour, minute);
}

@visibleForTesting
bool isHomeScheduleOverdue(ScheduleItemModel item, DateTime now) {
  if (item.isDone) return false;
  final status = item.status.trim().toLowerCase();
  if (status == 'missed') return true;
  if (status != 'scheduled') return false;
  final scheduled = _homeCountdownScheduledDateTime(item);
  return scheduled != null && scheduled.isBefore(now);
}

@visibleForTesting
int compareHomeScheduleForDisplay(
  ScheduleItemModel left,
  ScheduleItemModel right,
  DateTime now,
) {
  final leftOverdue = isHomeScheduleOverdue(left, now);
  final rightOverdue = isHomeScheduleOverdue(right, now);
  if (leftOverdue != rightOverdue) return leftOverdue ? 1 : -1;
  final leftDate = _homeCountdownScheduledDateTime(left) ?? DateTime(2100);
  final rightDate = _homeCountdownScheduledDateTime(right) ?? DateTime(2100);
  return leftDate.compareTo(rightDate);
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
    final title = hasTreatmentPlans
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'برنامه بعدی در راه است',
              en: "The next program is coming",
            ),
            en: "The next program is coming",
          )
        : LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'شروع مراقبت از خودت',
              en: "Start taking care of yourself",
            ),
            en: "Start taking care of yourself",
          );
    final description = hasTreatmentPlans
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'وقتی زمان بعدی برسد، شمارش معکوس همین‌جا نمایش داده می‌شود.',
              en: "When the next time arrives, the countdown will be displayed here.",
            ),
            en: "When the next time arrives, the countdown will be displayed here.",
          )
        : LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'اولین برنامه را ثبت کن؛ بعد از آن برنامه امروز و شمارش معکوس خودکار می‌شوند.',
              en: "Record the first program; After that, today's schedule and countdown will be automatic.",
            ),
            en: "Record the first program; After that, today's schedule and countdown will be automatic.",
          );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.96, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        alignment: Alignment.center,
        child: child,
      ),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFFFFFFF), Color(0xFFF0FAF5)],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE5F1EA)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C1D5B43),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F8F1),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    hasTreatmentPlans
                        ? Icons.schedule_rounded
                        : Icons.auto_awesome_rounded,
                    size: 34,
                    color: AppColors.primary,
                  ),
                  if (!hasTreatmentPlans)
                    Positioned(
                      left: 9,
                      bottom: 9,
                      child: Icon(
                        Icons.add_circle_rounded,
                        size: 17,
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!hasTreatmentPlans) ...[
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'اولین قدم',
                            en: "The first step",
                          ),
                          en: "The first step",
                        ),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    SizedBox(height: 7),
                  ],
                  Text(
                    title,
                    style: font.copyWith(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.darkBlue,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    description,
                    style: font.copyWith(
                      fontSize: 12.5,
                      height: 1.55,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 7),
                  TextButton.icon(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(
                      hasTreatmentPlans
                          ? Icons.arrow_back_rounded
                          : Icons.add_rounded,
                      size: 18,
                    ),
                    label: Text(
                      hasTreatmentPlans
                          ? LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'مشاهده درمان‌ها',
                                en: "View treatments",
                              ),
                              en: "View treatments",
                            )
                          : LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'ثبت اولین برنامه',
                                en: "Registration of the first program",
                              ),
                              en: "Registration of the first program",
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
    final title = hasTreatmentPlans
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'امروز برنامه‌ای باقی نمانده',
              en: "There are no programs left today",
            ),
            en: "There are no programs left today",
          )
        : LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'امروز را از یک برنامه ساده شروع کن',
              en: "Start today with a simple plan",
            ),
            en: "Start today with a simple plan",
          );
    final description = hasTreatmentPlans
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'برنامه بعدی به‌صورت خودکار در خانه و تقویم نمایش داده می‌شود.',
              en: "The next program is automatically displayed in the home and calendar.",
            ),
            en: "The next program is automatically displayed in the home and calendar.",
          )
        : LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'دارو، ویزیت یا تزریق را ثبت کن تا LifeMate زمان‌بندی و یادآوری‌ها را برایت مرتب کند.',
              en: "Record a medication, visit, or injection and LifeMate will organize the schedule and reminders for you.",
            ),
            en: "Record a medication, visit, or injection and LifeMate will organize the schedule and reminders for you.",
          );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.86, end: 1),
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeOutBack,
              builder: (context, value, child) =>
                  Transform.scale(scale: value, child: child),
              child: Container(
                width: 74,
                height: 74,
                decoration: const BoxDecoration(
                  color: Color(0xFFE7F8F1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasTreatmentPlans
                      ? Icons.task_alt_rounded
                      : Icons.health_and_safety_rounded,
                  size: 37,
                  color: AppColors.primary,
                ),
              ),
            ),
            SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: font.copyWith(
                fontSize: 16.5,
                fontWeight: FontWeight.w900,
                color: AppColors.darkBlue,
              ),
            ),
            SizedBox(height: 7),
            Text(
              description,
              textAlign: TextAlign.center,
              style: font.copyWith(
                fontSize: 12.5,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            if (!hasTreatmentPlans) ...[
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _EmptyCareTypeChip(
                      icon: Icons.medication_rounded,
                      label: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'دارو',
                          en: "Medication",
                        ),
                        en: "medicine",
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _EmptyCareTypeChip(
                      icon: Icons.medical_services_rounded,
                      label: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'ویزیت',
                          en: "Appointment",
                        ),
                        en: "visit",
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _EmptyCareTypeChip(
                      icon: Icons.vaccines_rounded,
                      label: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'تزریق',
                          en: "Injection",
                        ),
                        en: "Injection",
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAddTreatment,
                icon: Icon(Icons.add_rounded),
                label: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ثبت اولین برنامه',
                      en: "Registration of the first program",
                    ),
                    en: "Registration of the first program",
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyCareTypeChip extends StatelessWidget {
  const _EmptyCareTypeChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF5FAF7),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFFE5F1EA)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}
