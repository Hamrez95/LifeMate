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
            ? (isPersian ? 'مصرف‌نشده • ${item.time}' : 'Missed • ${item.time}')
            : null,
        countdownLabel: overdue ? (isPersian ? 'گذشته' : 'Missed') : null,
        accentColor: overdue ? missedColor : null,
        progressColor: overdue ? missedColor : null,
        progressBackgroundColor: overdue ? const Color(0xFFFFEEEE) : null,
        font: font,
      );
    }

    final isAppointment = item.type == 'appointment';
    final isMissed = item.status == 'missed';
    final eventLabel = isAppointment
        ? LifeMateRuntimeLocale.select(fa: 'وقت ویزیت', en: 'Visiting time')
        : LifeMateRuntimeLocale.select(fa: 'زمان تزریق', en: 'Injection time');
    const missedColor = Color(0xFFE06464);
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
      primaryActionLabel: isPersian ? 'انجام شد' : 'Done',
      editActionLabel: isPersian ? 'ویرایش' : 'Edit',
      secondaryActionLabel: isPersian ? 'انجام نشد' : 'Not done',
      supportingText: isMissed
          ? '$eventLabel ${isPersian ? 'انجام‌نشده' : 'not done'} • ${item.time}'
          : '$eventLabel • ${item.time}',
      countdownLabel: isMissed ? (isPersian ? 'گذشته' : 'Missed') : null,
      accentColor: isMissed ? missedColor : eventAccent,
      progressColor: isMissed ? missedColor : eventAccent,
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
                      child: Text(isPersian ? 'تلاش دوباره' : 'Try again'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _HomeHealthCard(
                onTap: widget.onOpenHealth,
                isPersian: isPersian,
              ),
            ),
            const SizedBox(height: 14),
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
                      padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 24, 16),
                      child: Text(
                        loc['today_schedule'] ??
                            (isPersian ? 'برنامه امروز' : "Today's schedule"),
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
                                padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 16),
                                itemCount: visibleToday.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final item = visibleToday[index];
                                  final missed = isHomeScheduleOverdue(item, now);
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
                                        ? () => _reportCareEventStatus(item, 'completed')
                                        : null,
                                    onNotCompleted:
                                        item.type != 'medicine' &&
                                            missed &&
                                            !_submitting.contains(item.id)
                                        ? () => _reportCareEventStatus(item, 'cancelled')
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
    final date = DateTime.tryParse(event['scheduledLocalDate']?.toString() ?? '');
    final parts = event['scheduledLocalTime']?.toString().split(':') ?? const [];
    if (date == null || parts.length < 2) return false;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return false;
    return DateTime(date.year, date.month, date.day, hour, minute)
        .isBefore(DateTime.now());
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

  static int _compareOccurrence(ScheduleItemModel left, ScheduleItemModel right) {
    final leftDate = _scheduledDateTime(left) ?? DateTime(2100);
    final rightDate = _scheduledDateTime(right) ?? DateTime(2100);
    return leftDate.compareTo(rightDate);
  }

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year && left.month == right.month && left.day == right.day;
}

class _HomeHealthCard extends StatelessWidget {
  const _HomeHealthCard({required this.onTap, required this.isPersian});

  final VoidCallback onTap;
  final bool isPersian;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isPersian ? 'باز کردن سلامت من' : 'Open My Health',
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
              padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.monitor_heart_rounded,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPersian ? 'سلامت من' : 'My Health',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isPersian
                              ? 'ثبت و مرور فشار، وزن، علائم و تاریخچه سلامت'
                              : 'Log and review vitals, symptoms and health history',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: AppColors.textPrimary.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
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

  final future = actionable.where((item) {
    final scheduled = _homeCountdownScheduledDateTime(item);
    return scheduled != null && !scheduled.isBefore(now);
  }).toList()
    ..sort((left, right) {
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
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final title = hasTreatmentPlans
        ? (isPersian ? 'برنامه بعدی در راه است' : 'The next schedule is coming')
        : (isPersian ? 'شروع مراقبت از خودت' : 'Start taking care of yourself');
    final description = hasTreatmentPlans
        ? (isPersian
              ? 'وقتی زمان بعدی برسد، شمارش معکوس همین‌جا نمایش داده می‌شود.'
              : 'Your next countdown will appear here when it is scheduled.')
        : (isPersian
              ? 'اولین درمان یا برنامه‌ات را اضافه کن تا زمان‌بندی اینجا نمایش داده شود.'
              : 'Add your first treatment to see its schedule here.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: font.copyWith(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Text(description, style: font.copyWith(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onAction,
            icon: Icon(hasTreatmentPlans ? Icons.medication_rounded : Icons.add_rounded),
            label: Text(hasTreatmentPlans
                ? (isPersian ? 'درمان‌ها' : 'Treatments')
                : (isPersian ? 'افزودن درمان' : 'Add treatment')),
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
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      children: [
        const Icon(Icons.event_available_rounded, size: 46, color: AppColors.primary),
        const SizedBox(height: 12),
        Text(
          hasTreatmentPlans
              ? (isPersian ? 'برای امروز برنامه بازی نمانده.' : 'Nothing pending for today.')
              : (isPersian ? 'هنوز درمانی ثبت نکرده‌ای.' : 'No treatment has been added yet.'),
          textAlign: TextAlign.center,
          style: font.copyWith(fontWeight: FontWeight.w700),
        ),
        if (!hasTreatmentPlans) ...[
          const SizedBox(height: 14),
          Center(
            child: FilledButton.icon(
              onPressed: onAddTreatment,
              icon: const Icon(Icons.add_rounded),
              label: Text(isPersian ? 'افزودن درمان' : 'Add treatment'),
            ),
          ),
        ],
      ],
    );
  }
}
