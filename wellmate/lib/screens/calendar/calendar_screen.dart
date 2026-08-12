import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../localization/app_localizations.dart';
import '../../models/schedule_item_model.dart';
import '../treatments/edit_care_event_screen.dart';
import 'custom_table_calendar.dart';
import 'schedule_item_card.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.refreshToken = 0});

  final int refreshToken;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  bool _loading = true;
  bool _backgroundRefreshing = false;
  String? _error;
  List<ScheduleItemModel> _monthItems = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMonth());
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _loadMonth();
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Future<void> _loadMonth() async {
    if (!mounted) return;
    setState(() {
      if (_monthItems.isEmpty) {
        _loading = true;
      } else {
        _backgroundRefreshing = true;
      }
      _error = null;
    });
    try {
      final api = context.read<LifeMateApiClient>();
      final range = visibleCalendarMonthRange(context, _focusedMonth);
      final results = await Future.wait<dynamic>([
        api.getTreatmentPlans(),
        api.getDoseOccurrences(fromDate: range.$1, toDate: range.$2),
        api.getCareEvents(fromDate: range.$1, toDate: range.$2),
      ]);
      final plans = results[0] as List<Map<String, dynamic>>;
      final doses = results[1] as List<Map<String, dynamic>>;
      final careEvents = results[2] as List<Map<String, dynamic>>;
      final plansById = <String, Map<String, dynamic>>{
        for (final plan in plans) plan['id'].toString(): plan,
      };
      final items =
          <ScheduleItemModel>[
            ...doses.map(
              (dose) => _scheduleItemFromDose(
                dose,
                plansById[dose['treatmentPlanId'].toString()] ?? const {},
              ),
            ),
            ...careEvents.map(_scheduleItemFromCareEvent),
          ]..sort((a, b) {
            final dateCompare = (a.startDate ?? _selectedDate).compareTo(
              b.startDate ?? _selectedDate,
            );
            return dateCompare == 0 ? a.time.compareTo(b.time) : dateCompare;
          });
      if (!mounted) return;
      setState(() {
        _monthItems = items;
        _loading = false;
        _backgroundRefreshing = false;
      });
    } on LifeMateApiException catch (error) {
      _setError(
        error.isUnauthorized
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'نشست شما منقضی شده است. دوباره وارد شوید.',
                  en: "Your session has expired. Sign in again.",
                ),
                en: "Your session has expired. Sign in again.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تقویم درمان و مراقبت دریافت نشد. دوباره تلاش کنید.',
                  en: "The treatment and care calendar was not received. Try again.",
                ),
                en: "The treatment and care calendar was not received. Try again.",
              ),
      );
    } catch (error) {
      debugPrint('WellMate calendar load failed: $error');
      _setError(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تقویم درمان و مراقبت دریافت نشد. اتصال را بررسی کنید.',
            en: "The treatment and care calendar was not received. Check the connection.",
          ),
          en: "The treatment and care calendar was not received. Check the connection.",
        ),
      );
    }
  }

  ScheduleItemModel _scheduleItemFromDose(
    Map<String, dynamic> dose,
    Map<String, dynamic> plan,
  ) {
    final medication = plan['medication'] is Map<String, dynamic>
        ? plan['medication'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final status = dose['status']?.toString() ?? 'scheduled';
    final rawTime = dose['scheduledLocalTime']?.toString() ?? '';
    final scheduledDate =
        DateTime.tryParse(dose['scheduledLocalDate']?.toString() ?? '') ??
        DateTime.tryParse(
          dose['scheduledAtUtc']?.toString() ?? '',
        )?.toLocal() ??
        _selectedDate;
    return ScheduleItemModel(
      id: dose['id']?.toString() ?? '',
      title: medication['name']?.toString().trim().isNotEmpty == true
          ? medication['name'].toString()
          : dose['medicationName']?.toString() ??
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'دارو',
                    en: "Medication",
                  ),
                  en: "medicine",
                ),
      time: rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
      dosage:
          plan['doseText']?.toString() ?? dose['doseText']?.toString() ?? '',
      type: 'medicine',
      frequency: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'طبق برنامه درمان',
          en: "According to the treatment plan",
        ),
        en: "According to the treatment plan",
      ),
      isDone: status == 'taken' || status == 'skipped',
      status: status,
      version: dose['version'] is int ? dose['version'] as int : 1,
      scheduledAtUtc: DateTime.tryParse(
        dose['scheduledAtUtc']?.toString() ?? '',
      )?.toUtc(),
      startDate: _dateOnly(scheduledDate),
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
  }

  ScheduleItemModel _scheduleItemFromCareEvent(Map<String, dynamic> event) {
    final eventType = event['eventType']?.toString().toLowerCase();
    final type = eventType == 'injection' ? 'injection' : 'appointment';
    final rawTime = event['scheduledLocalTime']?.toString() ?? '--:--';
    final date =
        DateTime.tryParse(event['scheduledLocalDate']?.toString() ?? '') ??
        _selectedDate;
    final rawStatus = event['status']?.toString().toLowerCase() ?? 'scheduled';
    final status =
        rawStatus == 'scheduled' &&
            _isTimePassed(
              rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
              date,
            )
        ? 'missed'
        : rawStatus;
    final details = <String>[
      if (type == 'appointment')
        _nonEmpty(event['providerName']) ?? _nonEmpty(event['specialty']) ?? '',
      if (type == 'injection')
        _nonEmpty(event['doseText']) ??
            _administrationRouteLabel(event['administrationRoute']),
      _nonEmpty(event['centerName']) ?? '',
      _nonEmpty(event['addressLine']) ?? '',
    ].where((value) => value.isNotEmpty).join(' • ');
    return ScheduleItemModel(
      id: event['id']?.toString() ?? '',
      seriesId: event['seriesId']?.toString(),
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
      type: type,
      frequency: type == 'injection'
          ? LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(fa: 'تزریق', en: "Injection"),
              en: "Injection",
            )
          : LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(fa: 'ویزیت', en: "Appointment"),
              en: "visit",
            ),
      isDone: status == 'completed' || status == 'cancelled',
      status: status,
      version: event['version'] is int ? event['version'] as int : 1,
      startDate: _dateOnly(date),
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
  }

  static String? _nonEmpty(dynamic value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String _administrationRouteLabel(dynamic value) {
    return switch (value?.toString().toLowerCase()) {
      'intramuscular' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'عضلانی', en: "muscular"),
        en: "muscular",
      ),
      'subcutaneous' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'زیرجلدی', en: "Undercover"),
        en: "Undercover",
      ),
      'intravenous' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'وریدی', en: "vein"),
        en: "vein",
      ),
      'other' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'طبق دستور درمانگر',
          en: "According to the therapist's instructions",
        ),
        en: "According to the therapist's instructions",
      ),
      _ => '',
    };
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _backgroundRefreshing = false;
      _error = message;
    });
  }

  bool _isTimePassed(String time, DateTime targetDate) {
    final now = DateTime.now();
    final targetDay = _dateOnly(targetDate);
    final today = _dateOnly(now);
    if (targetDay.isBefore(today)) return true;
    if (targetDay.isAfter(today)) return false;
    final parts = time.split(':');
    if (parts.length < 2) return false;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1].split(' ').first);
    if (hour == null || minute == null) return false;
    return now.isAfter(DateTime(now.year, now.month, now.day, hour, minute));
  }

  List<ScheduleItemModel> _getEventsForDay(DateTime targetDate) {
    final normalized = _dateOnly(targetDate);
    final items = _monthItems
        .where((item) => _dateOnly(item.startDate ?? targetDate) == normalized)
        .toList(growable: false);
    items.sort((a, b) => a.time.compareTo(b.time));
    return items;
  }

  Set<String> _getDayEventTypes(DateTime day) {
    final types = <String>{};
    for (final item in _getEventsForDay(day)) {
      types.add(item.type.isEmpty ? 'medicine' : item.type);
      if (item.status == 'missed' ||
          (!item.isDone && _isTimePassed(item.time, day))) {
        types.add('missed');
      }
    }
    return types;
  }

  Future<void> _changeMonth(DateTime focusedDay) async {
    setState(() => _focusedMonth = focusedDay);
    await _loadMonth();
  }

  Future<void> _openCareEventEditor(ScheduleItemModel item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditCareEventScreen(eventId: item.seriesId ?? item.id),
      ),
    );
    if (changed == true && mounted) await _loadMonth();
  }

  Widget _eventCard(
    BuildContext context,
    ScheduleItemModel item,
    AppLocalizations loc,
    bool isPersian,
  ) {
    final now = DateTime.now();
    final isFuture = _dateOnly(_selectedDate).isAfter(_dateOnly(now));
    final isMedicine = item.type == 'medicine';
    final isMissed =
        item.status == 'missed' ||
        (!item.isDone && _isTimePassed(item.time, _selectedDate));
    final showDoneMark = isMedicine && item.isDone && !isFuture;
    return Padding(
      key: ValueKey<String>('calendar-event-${item.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: ScheduleItemCard(
        item: item,
        loc: loc,
        isPersian: isPersian,
        isMissed: isMissed,
        showDone: showDoneMark,
        onTap: isMedicine ? null : () => _openCareEventEditor(item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    final selectedEvents = _getEventsForDay(_selectedDate);
    final scheduleTitle = isPersian
        ? LifeMateRuntimeLocale.select(
            fa: 'برنامه روز ${formatAppDate(context, _selectedDate, includeWeekday: true)}',
            en: "Program of the day ${formatAppDate(context, _selectedDate, includeWeekday: true)}",
          )
        : '${loc['calendar_schedule_for'] ?? 'Schedule for'} '
              '${formatAppDate(context, _selectedDate)}';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadMonth,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 20, top: 10),
            child: Column(
              children: [
                if (_backgroundRefreshing)
                  const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: CustomTableCalendar(
                    focusedMonth: _focusedMonth,
                    selectedDate: _selectedDate,
                    isPersian: isPersian,
                    getDayEventTypes: _getDayEventTypes,
                    onPageChanged: _changeMonth,
                    onDaySelected: (selectedDay, focusedDay) async {
                      final monthChanged = !isSameVisibleCalendarMonth(
                        context,
                        focusedDay,
                        _focusedMonth,
                      );
                      setState(() {
                        _selectedDate = selectedDay;
                        _focusedMonth = focusedDay;
                      });
                      if (monthChanged) await _loadMonth();
                    },
                  ),
                ),
                const SizedBox(height: 25),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadowDark.withValues(alpha: 0.5),
                        blurRadius: 10,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scheduleTitle,
                        style: AppTextStyles.heading(
                          context,
                        ).copyWith(fontSize: 18),
                      ),
                      SizedBox(height: 16),
                      if (_loading)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_error != null)
                        _CalendarErrorState(
                          message: _error!,
                          onRetry: _loadMonth,
                        )
                      else if (selectedEvents.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              loc['calendar_empty'] ??
                                  LifeMateRuntimeLocale.select(
                                    fa: LifeMateRuntimeLocale.select(
                                      fa: 'بدون برنامه',
                                      en: "No program",
                                    ),
                                    en: "No program",
                                  ),
                              style: AppTextStyles.body(context),
                            ),
                          ),
                        )
                      else
                        Column(
                          key: ValueKey<String>('calendar-event-list'),
                          children: [
                            for (final item in selectedEvents)
                              _eventCard(context, item, loc, isPersian),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarErrorState extends StatelessWidget {
  const _CalendarErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 34),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.primary),
            SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            SizedBox(height: 14),
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
    );
  }
}
