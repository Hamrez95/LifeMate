import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../models/event_model.dart';
import '../../models/user_model.dart';
import '../../widgets/caremate_bottom_nav.dart';
import '../../widgets/custom_app_header.dart';
import '../dashboard_screen.dart';
import '../feature_preview_screen.dart';
import 'calendar_view.dart';
import 'schedule_card.dart';
import 'user_selector.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    this.refreshToken = 0,
    this.onNavigationTap,
  });

  final int refreshToken;
  final ValueChanged<int>? onNavigationTap;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  String? _selectedUserId;
  bool _loadingRelationships = true;
  bool _loadingEvents = false;
  bool _backgroundRefreshing = false;
  String? _error;
  List<UserModel> _users = const [];
  List<EventModel> _events = const [];

  @override
  void initState() {
    super.initState();
    _refreshRelationships();
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _refreshRelationships(background: true);
    }
  }

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Future<void> _refreshRelationships({bool background = false}) async {
    setState(() {
      if (_users.isEmpty) {
        _loadingRelationships = true;
      } else if (background) {
        _backgroundRefreshing = true;
      }
      _error = null;
    });
    try {
      final api = context.read<LifeMateApiClient>();
      final results = await Future.wait([
        api.getCurrentUser(),
        api.getCareRelationships(),
      ]);
      final currentUser = results[0] as Map<String, dynamic>;
      final relationships = results[1] as List<Map<String, dynamic>>;
      final user = currentUser['user'] as Map<String, dynamic>? ?? const {};
      final currentUserId = user['id']?.toString();
      final active = relationships
          .where(
            (relationship) =>
                relationship['status']?.toString() == 'active' &&
                relationship['caregiverUserId']?.toString() == currentUserId,
          )
          .toList(growable: false);

      final users = active
          .map(
            (relationship) => UserModel(
              id: relationship['patientUserId'].toString(),
              name:
                  _nonEmpty(relationship['patientDisplayName']) ??
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'فرد تحت مراقبت',
                      en: "Person under care",
                    ),
                    en: "Person under care",
                  ),
              role: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'فرد تحت مراقبت',
                  en: "Person under care",
                ),
                en: "Person under care",
              ),
              profilePhotoUrl: _nonEmpty(
                relationship['patientProfilePhotoUrl'],
              ),
              avatarKey: _nonEmpty(relationship['patientAvatarKey']),
            ),
          )
          .toList(growable: false);

      var selected = _selectedUserId;
      if (!users.any((item) => item.id == selected)) {
        selected = users.isEmpty ? null : users.first.id;
      }

      if (!mounted) return;
      setState(() {
        _users = users;
        _selectedUserId = selected;
        _loadingRelationships = false;
      });
      await _loadMonthEvents(background: background);
    } on LifeMateApiException catch (error) {
      _setError(_friendlyApiError(error));
    } catch (error) {
      debugPrint('CareMate calendar relationship load failed: $error');
      _setError(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'اطلاعات تقویم دریافت نشد. اتصال اینترنت را بررسی کنید.',
            en: "Calendar information not received. Check your internet connection.",
          ),
          en: "Calendar information not received. Check your internet connection.",
        ),
      );
    } finally {
      if (mounted) setState(() => _backgroundRefreshing = false);
    }
  }

  Future<void> _loadMonthEvents({bool background = false}) async {
    final patientUserId = _selectedUserId;
    if (patientUserId == null) {
      if (mounted) setState(() => _events = const []);
      return;
    }

    setState(() {
      if (_events.isEmpty || !background) {
        _loadingEvents = _events.isEmpty;
      }
      if (background && _events.isNotEmpty) _backgroundRefreshing = true;
      _error = null;
    });
    try {
      final api = context.read<LifeMateApiClient>();
      final range = visibleCalendarMonthRange(context, _focusedMonth);
      final results = await Future.wait([
        api.getCareRecipientDoseOccurrences(
          patientUserId: patientUserId,
          fromDate: range.$1,
          toDate: range.$2,
        ),
        api.getCareRecipientCareEvents(
          patientUserId: patientUserId,
          fromDate: range.$1,
          toDate: range.$2,
        ),
      ]);
      final doses = results[0];
      final careEvents = results[1];
      final events =
          <EventModel>[
            ...doses
                .map((dose) => _eventFromDose(patientUserId, dose))
                .whereType<EventModel>(),
            ...careEvents
                .map((event) => _eventFromCareEvent(patientUserId, event))
                .whereType<EventModel>(),
          ]..sort((a, b) {
            final dateCompare = a.date.compareTo(b.date);
            return dateCompare == 0 ? a.time.compareTo(b.time) : dateCompare;
          });
      if (!mounted) return;
      setState(() {
        _events = events;
        _loadingEvents = false;
        _backgroundRefreshing = false;
      });
    } on LifeMateApiException catch (error) {
      _setError(_friendlyApiError(error));
    } catch (error) {
      debugPrint('CareMate calendar event load failed: $error');
      _setError(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'برنامه درمان، ویزیت و تزریق این ماه دریافت نشد.',
            en: "This month's treatment, visit and injection schedule was not received.",
          ),
          en: "This month's treatment, visit and injection schedule was not received.",
        ),
      );
    }
  }

  EventModel? _eventFromDose(String patientUserId, Map<String, dynamic> dose) {
    final rawDate = dose['scheduledLocalDate']?.toString();
    final fallbackUtc = DateTime.tryParse(
      dose['scheduledAtUtc']?.toString() ?? '',
    );
    final date = rawDate == null
        ? fallbackUtc?.toLocal()
        : DateTime.tryParse(rawDate);
    if (date == null) return null;

    final rawTime = dose['scheduledLocalTime']?.toString() ?? '--:--';
    final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
    final status = dose['status']?.toString() ?? 'scheduled';
    final completed = switch (status) {
      'taken' => true,
      'skipped' || 'missed' => false,
      _ => null,
    };

    return EventModel(
      id: dose['id']?.toString() ?? '${date.toIso8601String()}-$time',
      userId: patientUserId,
      title: dose['medicationName']?.toString().trim().isNotEmpty == true
          ? dose['medicationName'].toString()
          : LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
              en: "medicine",
            ),
      date: _normalizeDate(date),
      time: time,
      description: _nonEmpty(dose['doseText']),
      type: EventType.medicine,
      isCompleted: completed,
    );
  }

  EventModel? _eventFromCareEvent(
    String patientUserId,
    Map<String, dynamic> event,
  ) {
    final date = DateTime.tryParse(
      event['scheduledLocalDate']?.toString() ?? '',
    );
    if (date == null) return null;
    final rawTime = event['scheduledLocalTime']?.toString() ?? '--:--';
    final eventType = event['eventType']?.toString().toLowerCase();
    final type = eventType == 'injection'
        ? EventType.injection
        : EventType.appointment;
    final details = <String>[
      if (type == EventType.appointment)
        _nonEmpty(event['providerName']) ?? _nonEmpty(event['specialty']) ?? '',
      if (type == EventType.injection)
        _nonEmpty(event['doseText']) ??
            _administrationRouteLabel(event['administrationRoute']),
      _nonEmpty(event['centerName']) ?? '',
      _nonEmpty(event['addressLine']) ?? '',
    ].where((value) => value.isNotEmpty).join(' • ');

    return EventModel(
      id:
          event['id']?.toString() ??
          '${event['scheduledLocalDate']}-$rawTime-$eventType',
      userId: patientUserId,
      title:
          _nonEmpty(event['title']) ??
          (type == EventType.injection
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
      date: _normalizeDate(date),
      time: rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
      description: details.isEmpty ? null : details,
      type: type,
      isCompleted: event['status']?.toString().toLowerCase() == 'completed'
          ? true
          : null,
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
      _error = message;
      _loadingRelationships = false;
      _loadingEvents = false;
    });
  }

  Future<void> _selectUser(String userId) async {
    if (userId == _selectedUserId) return;
    setState(() {
      _selectedUserId = userId;
      _events = const [];
    });
    await _loadMonthEvents();
  }

  List<EventModel> _getEventsForDayAndUser(DateTime day) {
    final selectedUserId = _selectedUserId;
    if (selectedUserId == null) return const [];
    final normalized = _normalizeDate(day);
    return _events
        .where(
          (event) =>
              event.userId == selectedUserId &&
              _normalizeDate(event.date) == normalized,
        )
        .toList(growable: false);
  }

  bool _hasOverdueEvents(DateTime day) {
    final today = _normalizeDate(DateTime.now());
    if (!day.isBefore(today)) return false;
    return _getEventsForDayAndUser(day).any(
      (event) => event.type == EventType.medicine && event.isCompleted != true,
    );
  }

  Set<EventType> _getDayEventTypes(DateTime day) =>
      _getEventsForDayAndUser(day).map((event) => event.type).toSet();

  List<EventModel> get _activeAlerts {
    final now = DateTime.now();
    final today = _normalizeDate(now);
    return _events
        .where((event) {
          if (event.type != EventType.medicine) return false;
          if (_normalizeDate(event.date) != today) return false;
          if (event.isCompleted != false) return false;
          final parts = event.time.split(':');
          final hour = int.tryParse(parts.first) ?? 0;
          final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
          final scheduled = DateTime(
            event.date.year,
            event.date.month,
            event.date.day,
            hour,
            minute,
          );
          return !scheduled.isAfter(now);
        })
        .toList(growable: false);
  }

  void _showAlerts() {
    final alerts = _activeAlerts;
    if (alerts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'هشدار دارویی فعالی وجود ندارد.',
                en: "There is no active drug warning.",
              ),
              en: "There is no active drug warning.",
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final isPersian = usesPersianCalendar(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(24, 18, 24, 30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'هشدارهای دارویی امروز',
                    en: "Today's drug warnings",
                  ),
                  en: "Today's drug warnings",
                ),
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 14),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: alerts.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10),
                  itemBuilder: (_, index) => ScheduleCard(
                    event: alerts[index],
                    font: Theme.of(context).textTheme.bodyMedium ?? TextStyle(),
                    isPersian: isPersian,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onNavigationTap(int index) {
    final shellNavigation = widget.onNavigationTap;
    if (shellNavigation != null) {
      shellNavigation(index);
      return;
    }
    if (index == 0) return;
    final Widget destination = index == 4
        ? const DashboardScreen()
        : CareMateFeaturePreviewScreen(initialIndex: index);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => destination,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isPersian = usesPersianCalendar(context);
    final font = TextStyle(
      fontFamily: isPersian ? 'Vazir' : 'Nunito',
      color: AppColors.primaryText,
    );
    final selectedUserId = _selectedUserId;
    final eventsForSelectedDay = _getEventsForDayAndUser(_selectedDate);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            CustomAppHeader(
              onNotificationTap: _showAlerts,
              showNotificationDot: _activeAlerts.isNotEmpty,
            ),
            if (_backgroundRefreshing)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshRelationships,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
                  children: [
                    if (_loadingRelationships)
                      const SizedBox(
                        height: 330,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_users.isEmpty)
                      SizedBox(
                        height: 390,
                        child: _EmptyCalendarState(
                          onRefresh: _refreshRelationships,
                        ),
                      )
                    else ...[
                      UserSelector(
                        users: _users,
                        selectedUserId: selectedUserId ?? '',
                        font: font,
                        onUserSelected: _selectUser,
                      ),
                      const SizedBox(height: 12),
                      if (_error != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _CalendarErrorBanner(
                            message: _error!,
                            onRetry: _refreshRelationships,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      CalendarView(
                        focusedMonth: _focusedMonth,
                        selectedDate: _selectedDate,
                        onDaySelected: (selectedDay, focusedDay) {
                          final monthChanged = !isSameVisibleCalendarMonth(
                            context,
                            focusedDay,
                            _focusedMonth,
                          );
                          setState(() {
                            _selectedDate = selectedDay;
                            _focusedMonth = focusedDay;
                          });
                          if (monthChanged) _loadMonthEvents();
                        },
                        onPageChanged: (focusedDay) {
                          setState(() {
                            _focusedMonth = focusedDay;
                            _selectedDate = focusedDay;
                          });
                          _loadMonthEvents();
                        },
                        getDayEventTypes: _getDayEventTypes,
                        hasOverdueEvents: _hasOverdueEvents,
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                loc['cal_schedule'],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: font.copyWith(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                formatAppDate(
                                  context,
                                  _selectedDate,
                                  includeWeekday: isPersian,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: font.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_loadingEvents)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (eventsForSelectedDay.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: AppColors.softDecoration(),
                            child: Text(
                              loc['no_events_today'],
                              textAlign: TextAlign.center,
                              style: font.copyWith(
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              for (
                                var index = 0;
                                index < eventsForSelectedDay.length;
                                index++
                              ) ...[
                                if (index > 0) const SizedBox(height: 10),
                                ScheduleCard(
                                  event: eventsForSelectedDay[index],
                                  font: font,
                                  isPersian: isPersian,
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CareMateBottomNav(
        currentIndex: 0,
        onTap: _onNavigationTap,
        routeTreatmentScreen: widget.onNavigationTap == null,
      ),
    );
  }

  static String _friendlyApiError(LifeMateApiException error) {
    switch (error.code) {
      case 'care_access_denied':
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'دسترسی مراقبت لغو شده است. فهرست را تازه‌سازی کنید.',
            en: "Care access has been revoked. Refresh the list.",
          ),
          en: "Care access has been revoked. Refresh the list.",
        );
      default:
        return error.isUnauthorized
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'نشست شما منقضی شده است. دوباره وارد شوید.',
                  en: "Your session has expired. Sign in again.",
                ),
                en: "Your session has expired. Sign in again.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'درخواست تقویم انجام نشد. دوباره تلاش کنید.',
                  en: "Calendar request failed. Try again.",
                ),
                en: "Calendar request failed. Try again.",
              );
    }
  }
}

class _CalendarErrorBanner extends StatelessWidget {
  const _CalendarErrorBanner({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.red.shade100),
    ),
    child: Row(
      children: [
        Icon(Icons.cloud_off_rounded, color: Colors.red.shade600),
        SizedBox(width: 10),
        Expanded(child: Text(message)),
        TextButton(
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
  );
}

class _EmptyCalendarState extends StatelessWidget {
  const _EmptyCalendarState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(24),
        decoration: AppColors.softDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.family_restroom_rounded,
              size: 58,
              color: AppColors.primaryBlue,
            ),
            SizedBox(height: 14),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'هنوز فردی به مراقبت شما متصل نیست',
                  en: "No one is connected to your care yet",
                ),
                en: "No one is connected to your care yet",
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'پس از پذیرش دعوت، داروها، ویزیت‌ها و تزریق‌های واقعی بیمار در همین تقویم نمایش داده می‌شوند.',
                  en: "After accepting the invitation, the patient's actual medications, visits, and injections are displayed in this calendar.",
                ),
                en: "After accepting the invitation, the patient's actual medications, visits, and injections are displayed in this calendar.",
              ),
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.6, color: AppColors.secondaryText),
            ),
            SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: Icon(Icons.refresh_rounded),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'تازه‌سازی',
                    en: "refresh",
                  ),
                  en: "refresh",
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
