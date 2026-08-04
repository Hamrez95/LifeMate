from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace(path: str, old: str, new: str, count: int = 1) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Expected block not found in {path}: {old[:180]!r}")
    target.write_text(text.replace(old, new, count), encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content.rstrip() + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# Version: the frozen v0.9.0-internal.2 tag remains unchanged. New work starts
# at internal.3.
# ---------------------------------------------------------------------------
for pubspec in ("wellmate/pubspec.yaml", "caremate/pubspec.yaml"):
    replace(pubspec, "version: 0.9.0-internal.2+13", "version: 0.9.0-internal.3+14")

replace(
    "wellmate/lib/core/constants/app_version.dart",
    "const String wellMateAppVersion = '0.9.0-internal.2+13';",
    "const String wellMateAppVersion = '0.9.0-internal.3+14';",
)
replace(
    "caremate/lib/core/constants/app_version.dart",
    "const String careMateAppVersion = '0.9.0-internal.2+13';",
    "const String careMateAppVersion = '0.9.0-internal.3+14';",
)

# ---------------------------------------------------------------------------
# CareMate gains the same locale-aware Jalali/digit boundary as WellMate.
# ---------------------------------------------------------------------------
write(
    "caremate/lib/core/utils/persian_date_utils.dart",
    r'''import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'string_extensions.dart';

const List<String> _persianMonthNames = <String>[
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];

const Map<int, String> _persianWeekdayNames = <int, String>{
  DateTime.saturday: 'شنبه',
  DateTime.sunday: 'یکشنبه',
  DateTime.monday: 'دوشنبه',
  DateTime.tuesday: 'سه‌شنبه',
  DateTime.wednesday: 'چهارشنبه',
  DateTime.thursday: 'پنجشنبه',
  DateTime.friday: 'جمعه',
};

bool usesPersianCalendar(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'fa';

String localizeDigits(BuildContext context, Object? value) =>
    (value?.toString() ?? '').toPersianDigit(usesPersianCalendar(context));

String formatAppDate(
  BuildContext context,
  DateTime date, {
  bool includeWeekday = false,
}) {
  if (!usesPersianCalendar(context)) {
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }
  final jalali = Jalali.fromDateTime(date);
  final numeric =
      '${jalali.year.toString().padLeft(4, '0')}/'
              '${jalali.month.toString().padLeft(2, '0')}/'
              '${jalali.day.toString().padLeft(2, '0')}'
          .toPersianDigit(true);
  if (!includeWeekday) return numeric;
  return '${_persianWeekdayNames[date.weekday] ?? ''} $numeric'.trim();
}

String formatAppMonth(BuildContext context, DateTime date) {
  if (!usesPersianCalendar(context)) {
    return MaterialLocalizations.of(context).formatMonthYear(date);
  }
  final jalali = Jalali.fromDateTime(date);
  return '${_persianMonthNames[jalali.month - 1]} ${jalali.year}'
      .toPersianDigit(true);
}

(DateTime, DateTime) visibleCalendarMonthRange(
  BuildContext context,
  DateTime focusedDate,
) {
  if (!usesPersianCalendar(context)) {
    return (
      DateTime(focusedDate.year, focusedDate.month, 1),
      DateTime(focusedDate.year, focusedDate.month + 1, 0),
    );
  }
  final focused = Jalali.fromDateTime(focusedDate);
  final first = Jalali(focused.year, focused.month, 1);
  final last = Jalali(focused.year, focused.month, first.monthLength);
  return (first.toDateTime(), last.toDateTime());
}

bool isSameVisibleCalendarMonth(
  BuildContext context,
  DateTime left,
  DateTime right,
) {
  if (!usesPersianCalendar(context)) {
    return left.year == right.year && left.month == right.month;
  }
  final leftJalali = Jalali.fromDateTime(left);
  final rightJalali = Jalali.fromDateTime(right);
  return leftJalali.year == rightJalali.year &&
      leftJalali.month == rightJalali.month;
}
''',
)

# ---------------------------------------------------------------------------
# WellMate treatment details: parse backend ISO dates, render Jalali in fa, and
# pass every visible value through the locale digit formatter.
# ---------------------------------------------------------------------------
replace(
    "wellmate/lib/screens/treatments/treatments_screen.dart",
    "import '../../core/theme/app_style.dart';",
    "import '../../core/theme/app_style.dart';\nimport '../../core/utils/persian_date_utils.dart';",
)
replace(
    "wellmate/lib/screens/treatments/treatments_screen.dart",
    """              final firstTime =
                  rawTime.length >= 5 ? rawTime.substring(0, 5) : 'بدون زمان';""",
    """              final firstTime = localizeDigits(
                context,
                rawTime.length >= 5 ? rawTime.substring(0, 5) : 'بدون زمان',
              );""",
)
replace(
    "wellmate/lib/screens/treatments/treatments_screen.dart",
    """                    medication['name']?.toString() ?? 'دارو',""",
    """                    localizeDigits(
                      context,
                      medication['name']?.toString() ?? 'دارو',
                    ),""",
)
replace(
    "wellmate/lib/screens/treatments/treatments_screen.dart",
    """                      '${plan['doseText'] ?? ''} • هر روز ساعت $firstTime',""",
    """                      localizeDigits(
                        context,
                        '${plan['doseText'] ?? ''} • هر روز ساعت $firstTime',
                      ),""",
)
replace(
    "wellmate/lib/screens/treatments/treatments_screen.dart",
    """                                _text(medication['name'], fallback: 'دارو'),""",
    """                                _localizedText(
                                  context,
                                  medication['name'],
                                  fallback: 'دارو',
                                ),""",
)
replace(
    "wellmate/lib/screens/treatments/treatments_screen.dart",
    """                          value: _text(medication['strengthText']),""",
    """                          value: _localizedText(
                            context,
                            medication['strengthText'],
                          ),""",
)
replace(
    "wellmate/lib/screens/treatments/treatments_screen.dart",
    """                          value: _text(plan['doseText']),""",
    """                          value: _localizedText(context, plan['doseText']),""",
)
replace(
    "wellmate/lib/screens/treatments/treatments_screen.dart",
    """                          value: _text(plan['instructions']),""",
    """                          value: _localizedText(
                            context,
                            plan['instructions'],
                          ),""",
)
replace(
    "wellmate/lib/screens/treatments/treatments_screen.dart",
    """                          value: _text(plan['startDate']),""",
    """                          value: _localizedDate(context, plan['startDate']),""",
)
replace(
    "wellmate/lib/screens/treatments/treatments_screen.dart",
    """                          value: _text(plan['endDate'], fallback: 'بدون پایان'),""",
    """                          value: _localizedDate(
                            context,
                            plan['endDate'],
                            fallback: 'بدون پایان',
                          ),""",
)
replace(
    "wellmate/lib/screens/treatments/treatments_screen.dart",
    """                          title: Text(time, textDirection: TextDirection.ltr),""",
    """                          title: Text(
                            localizeDigits(context, time),
                            textDirection: TextDirection.ltr,
                          ),""",
)
replace(
    "wellmate/lib/screens/treatments/treatments_screen.dart",
    """String _text(dynamic value, {String fallback = 'ثبت نشده'}) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String _weekdayLabel""",
    """String _text(dynamic value, {String fallback = 'ثبت نشده'}) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String _localizedText(
  BuildContext context,
  dynamic value, {
  String fallback = 'ثبت نشده',
}) => localizeDigits(context, _text(value, fallback: fallback));

String _localizedDate(
  BuildContext context,
  dynamic value, {
  String fallback = 'ثبت نشده',
}) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return fallback;
  final parsed = DateTime.tryParse(text);
  return parsed == null
      ? localizeDigits(context, text)
      : formatAppDate(context, parsed);
}

String _weekdayLabel""",
)

# ---------------------------------------------------------------------------
# CareMate real Jalali calendar. The RTL header is explicit: previous month is
# on the right with '>', next month is on the left with '<'. LTR keeps the
# conventional previous-left / next-right ordering.
# ---------------------------------------------------------------------------
write(
    "caremate/lib/screens/calendar/calendar_view.dart",
    r'''import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../core/utils/string_extensions.dart';
import '../../models/event_model.dart';

typedef GetEventTypesCallback = Set<EventType> Function(DateTime day);
typedef HasOverdueEventsCallback = bool Function(DateTime day);

class CalendarView extends StatelessWidget {
  const CalendarView({
    super.key,
    required this.focusedMonth,
    required this.selectedDate,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.getDayEventTypes,
    required this.hasOverdueEvents,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;
  final GetEventTypesCallback getDayEventTypes;
  final HasOverdueEventsCallback hasOverdueEvents;

  @override
  Widget build(BuildContext context) {
    final isPersian = usesPersianCalendar(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: isPersian
          ? _PersianCalendar(
              focusedMonth: focusedMonth,
              selectedDate: selectedDate,
              onDaySelected: onDaySelected,
              onPageChanged: onPageChanged,
              getDayEventTypes: getDayEventTypes,
              hasOverdueEvents: hasOverdueEvents,
            )
          : _GregorianCalendar(
              focusedMonth: focusedMonth,
              selectedDate: selectedDate,
              onDaySelected: onDaySelected,
              onPageChanged: onPageChanged,
              getDayEventTypes: getDayEventTypes,
              hasOverdueEvents: hasOverdueEvents,
            ),
    );
  }
}

class _PersianCalendar extends StatelessWidget {
  const _PersianCalendar({
    required this.focusedMonth,
    required this.selectedDate,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.getDayEventTypes,
    required this.hasOverdueEvents,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;
  final GetEventTypesCallback getDayEventTypes;
  final HasOverdueEventsCallback hasOverdueEvents;

  static const _weekDays = <String>['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];

  DateTime _moveMonth(int delta) {
    final current = Jalali.fromDateTime(focusedMonth);
    var year = current.year;
    var month = current.month + delta;
    if (month < 1) {
      year -= 1;
      month = 12;
    } else if (month > 12) {
      year += 1;
      month = 1;
    }
    return Jalali(year, month, 1).toDateTime();
  }

  @override
  Widget build(BuildContext context) {
    final focused = Jalali.fromDateTime(focusedMonth);
    final first = Jalali(focused.year, focused.month, 1);
    final firstDate = first.toDateTime();
    final leadingCells = (firstDate.weekday + 1) % 7;
    final today = _dateOnly(DateTime.now());

    return Column(
      children: [
        Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('caremate-previous-month'),
                tooltip: 'ماه قبل',
                onPressed: () => onPageChanged(_moveMonth(-1)),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              Expanded(
                child: Text(
                  formatAppMonth(context, focusedMonth),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Vazir',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('caremate-next-month'),
                tooltip: 'ماه بعد',
                onPressed: () => onPageChanged(_moveMonth(1)),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ],
          ),
        ),
        Row(
          children: [
            for (final label in _weekDays)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Vazir',
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leadingCells + first.monthLength,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 0.92,
          ),
          itemBuilder: (context, index) {
            if (index < leadingCells) return const SizedBox.shrink();
            final dayNumber = index - leadingCells + 1;
            final day = Jalali(
              focused.year,
              focused.month,
              dayNumber,
            ).toDateTime();
            return _CalendarCell(
              day: day,
              label: '$dayNumber'.toPersianDigit(true),
              eventTypes: getDayEventTypes(day),
              isPastDay: _dateOnly(day).isBefore(today),
              isOverdue: hasOverdueEvents(day),
              isSelected: _sameDay(day, selectedDate),
              isToday: _sameDay(day, today),
              isPersian: true,
              onTap: () => onDaySelected(day, day),
            );
          },
        ),
      ],
    );
  }
}

class _GregorianCalendar extends StatelessWidget {
  const _GregorianCalendar({
    required this.focusedMonth,
    required this.selectedDate,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.getDayEventTypes,
    required this.hasOverdueEvents,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;
  final GetEventTypesCallback getDayEventTypes;
  final HasOverdueEventsCallback hasOverdueEvents;

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    return TableCalendar(
      locale: 'en_US',
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2035, 12, 31),
      focusedDay: focusedMonth,
      currentDay: DateTime.now(),
      calendarFormat: CalendarFormat.month,
      startingDayOfWeek: StartingDayOfWeek.sunday,
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      selectedDayPredicate: (day) => _sameDay(selectedDate, day),
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        leftChevronIcon:
            Icon(Icons.chevron_left_rounded, color: Colors.grey.shade700),
        rightChevronIcon:
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade700),
      ),
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, _) => _CalendarCell(
          day: day,
          label: '${day.day}',
          eventTypes: getDayEventTypes(day),
          isPastDay: _dateOnly(day).isBefore(today),
          isOverdue: hasOverdueEvents(day),
          isSelected: false,
          isToday: false,
          isPersian: false,
          onTap: () => onDaySelected(day, day),
        ),
        todayBuilder: (context, day, _) => _CalendarCell(
          day: day,
          label: '${day.day}',
          eventTypes: getDayEventTypes(day),
          isPastDay: false,
          isOverdue: false,
          isSelected: _sameDay(day, selectedDate),
          isToday: true,
          isPersian: false,
          onTap: () => onDaySelected(day, day),
        ),
        selectedBuilder: (context, day, _) => _CalendarCell(
          day: day,
          label: '${day.day}',
          eventTypes: getDayEventTypes(day),
          isPastDay: _dateOnly(day).isBefore(today),
          isOverdue: hasOverdueEvents(day),
          isSelected: true,
          isToday: _sameDay(day, today),
          isPersian: false,
          onTap: () => onDaySelected(day, day),
        ),
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    required this.day,
    required this.label,
    required this.eventTypes,
    required this.isPastDay,
    required this.isOverdue,
    required this.isSelected,
    required this.isToday,
    required this.isPersian,
    required this.onTap,
  });

  final DateTime day;
  final String label;
  final Set<EventType> eventTypes;
  final bool isPastDay;
  final bool isOverdue;
  final bool isSelected;
  final bool isToday;
  final bool isPersian;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = isSelected
        ? Colors.white
        : isPastDay
            ? const Color(0xFF666666)
            : Colors.black;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: isSelected
            ? AppColors.CalPrimary
            : isOverdue
                ? AppColors.CalBackForgotten
                : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isToday && !isSelected
                  ? Border.all(color: AppColors.CalPrimary, width: 1.5)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Text(
                  label.toPersianDigit(isPersian),
                  style: TextStyle(
                    fontFamily: isPersian ? 'Vazir' : 'Nunito',
                    color: textColor,
                  ),
                ),
                const Spacer(),
                if (eventTypes.isNotEmpty) _EventDots(eventTypes: eventTypes),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventDots extends StatelessWidget {
  const _EventDots({required this.eventTypes});

  final Set<EventType> eventTypes;

  @override
  Widget build(BuildContext context) {
    final colors = <Color>[
      if (eventTypes.contains(EventType.medicine)) AppColors.CalFisrtDot,
      if (eventTypes.contains(EventType.appointment) ||
          eventTypes.contains(EventType.doctor))
        AppColors.CalSecondDot,
      if (eventTypes.contains(EventType.injection) ||
          eventTypes.contains(EventType.checkup))
        Colors.orangeAccent,
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final color in colors.take(3))
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
      ],
    );
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
''',
)

# CareMate calendar screen uses Jalali boundaries and shared formatting.
replace(
    "caremate/lib/screens/calendar/calendar_screen.dart",
    "import '../../core/utils/string_extensions.dart';",
    "import '../../core/utils/persian_date_utils.dart';\nimport '../../core/utils/string_extensions.dart';",
)
replace(
    "caremate/lib/screens/calendar/calendar_screen.dart",
    """  DateTime _monthStart(DateTime date) => DateTime(date.year, date.month, 1);

  DateTime _monthEnd(DateTime date) =>
      DateTime(date.year, date.month + 1, 0);

""",
    "",
)
replace(
    "caremate/lib/screens/calendar/calendar_screen.dart",
    """      final api = context.read<LifeMateApiClient>();
      final results = await Future.wait([
        api.getCareRecipientDoseOccurrences(
          patientUserId: patientUserId,
          fromDate: _monthStart(_focusedMonth),
          toDate: _monthEnd(_focusedMonth),
        ),
        api.getCareRecipientCareEvents(
          patientUserId: patientUserId,
          fromDate: _monthStart(_focusedMonth),
          toDate: _monthEnd(_focusedMonth),
        ),
      ]);""",
    """      final api = context.read<LifeMateApiClient>();
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
      ]);""",
)
replace(
    "caremate/lib/screens/calendar/calendar_screen.dart",
    """    final isPersian = Directionality.of(context) == TextDirection.rtl;""",
    """    final isPersian = usesPersianCalendar(context);""",
    count=2,
)
replace(
    "caremate/lib/screens/calendar/calendar_screen.dart",
    """    const monthNamesEn = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const monthNamesFa = [
      'ژانویه',
      'فوریه',
      'مارس',
      'آوریل',
      'مه',
      'ژوئن',
      'ژوئیه',
      'اوت',
      'سپتامبر',
      'اکتبر',
      'نوامبر',
      'دسامبر',
    ];
    final monthName =
        (isPersian ? monthNamesFa : monthNamesEn)[_selectedDate.month - 1];
""",
    "",
)
replace(
    "caremate/lib/screens/calendar/calendar_screen.dart",
    """                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDate = selectedDay;
                    _focusedMonth = focusedDay;
                  });
                },""",
    """                onDaySelected: (selectedDay, focusedDay) {
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
                },""",
)
replace(
    "caremate/lib/screens/calendar/calendar_screen.dart",
    """                    _selectedDate = DateTime(
                      focusedDay.year,
                      focusedDay.month,
                      1,
                    );""",
    """                    _selectedDate = focusedDay;""",
)
replace(
    "caremate/lib/screens/calendar/calendar_screen.dart",
    """                        '${_selectedDate.day} $monthName, ${_selectedDate.year}'
                            .toPersianDigit(isPersian),""",
    """                        formatAppDate(
                          context,
                          _selectedDate,
                          includeWeekday: isPersian,
                        ),""",
)

# Schedule cards also localize numbers embedded in medication/event titles.
replace(
    "caremate/lib/screens/calendar/schedule_card.dart",
    """                  event.title,""",
    """                  event.title.toPersianDigit(isPersian),""",
)

# Care event management lists no longer expose raw ISO dates or English digits.
replace(
    "caremate/lib/screens/care_event_management_screen.dart",
    "import '../core/constants/app_colors.dart';",
    "import '../core/constants/app_colors.dart';\nimport '../core/utils/persian_date_utils.dart';",
)
replace(
    "caremate/lib/screens/care_event_management_screen.dart",
    """    final date = event['scheduledLocalDate']?.toString() ?? '----/--/--';
    final time = event['scheduledLocalTime']?.toString() ?? '--:--';""",
    """    final rawDate = event['scheduledLocalDate']?.toString() ?? '';
    final parsedDate = DateTime.tryParse(rawDate);
    final date = parsedDate == null
        ? localizeDigits(context, rawDate.isEmpty ? '----/--/--' : rawDate)
        : formatAppDate(context, parsedDate);
    final rawTime = event['scheduledLocalTime']?.toString() ?? '--:--';
    final time = localizeDigits(
      context,
      rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
    );""",
)
replace(
    "caremate/lib/screens/care_event_management_screen.dart",
    """                  event['title']?.toString() ??
                      (isInjection ? 'تزریق' : 'ویزیت'),""",
    """                  localizeDigits(
                    context,
                    event['title']?.toString() ??
                        (isInjection ? 'تزریق' : 'ویزیت'),
                  ),""",
)
replace(
    "caremate/lib/screens/care_event_management_screen.dart",
    """                  '$date  •  ${time.length >= 5 ? time.substring(0, 5) : time}',
                  textDirection: TextDirection.ltr,""",
    """                  '$date  •  $time',
                  textDirection: usesPersianCalendar(context)
                      ? TextDirection.rtl
                      : TextDirection.ltr,""",
)
replace(
    "caremate/lib/screens/care_event_management_screen.dart",
    """                  Text(center, style: const TextStyle(fontSize: 12)),""",
    """                  Text(
                    localizeDigits(context, center),
                    style: const TextStyle(fontSize: 12),
                  ),""",
)
replace(
    "caremate/lib/screens/care_event_management_screen.dart",
    """                          address,""",
    """                          localizeDigits(context, address),""",
)
replace(
    "caremate/lib/screens/care_event_management_screen.dart",
    """              dose['medicationName']?.toString() ?? 'دارو',""",
    """              localizeDigits(
                context,
                dose['medicationName']?.toString() ?? 'دارو',
              ),""",
)
replace(
    "caremate/lib/screens/care_event_management_screen.dart",
    """            time.length >= 5 ? time.substring(0, 5) : time,""",
    """            localizeDigits(
              context,
              time.length >= 5 ? time.substring(0, 5) : time,
            ),""",
)

# ---------------------------------------------------------------------------
# Regression tests for the exact physical feedback.
# ---------------------------------------------------------------------------
write(
    "wellmate/test/treatment_details_persian_localization_test.dart",
    r'''import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/screens/treatments/treatments_screen.dart';

void main() {
  testWidgets('treatment details renders Jalali dates and Persian digits',
      (tester) async {
    await tester.pumpWidget(
      Provider<LifeMateApiClient>.value(
        value: _TreatmentApi(),
        child: const MaterialApp(
          locale: Locale('fa'),
          supportedLocales: [Locale('fa'), Locale('en')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: TreatmentsScreen(refreshToken: 0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('سیتریزین'), findsOneWidget);
    expect(find.textContaining('۲۱:۰۰'), findsOneWidget);
    await tester.tap(find.text('سیتریزین'));
    await tester.pumpAndSettle();

    expect(find.text('۱۰'), findsOneWidget);
    expect(find.text('۱ قرص'), findsOneWidget);
    expect(find.text('۱۴۰۵/۰۵/۱۳'), findsOneWidget);
    expect(find.text('۱۴۰۵/۰۶/۳۰'), findsOneWidget);
    expect(find.text('۲۱:۰۰'), findsWidgets);
    expect(find.text('2026-08-04'), findsNothing);
    expect(find.text('2026-09-21'), findsNothing);
  });
}

class _TreatmentApi extends LifeMateApiClient {
  _TreatmentApi()
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () => 'test-token',
        );

  @override
  Future<List<Map<String, dynamic>>> getTreatmentPlans() async => [
        {
          'id': 'plan-1',
          'status': 'active',
          'doseText': '1 قرص',
          'instructions': 'بعدش سوار موتور نشو',
          'startDate': '2026-08-04',
          'endDate': '2026-09-21',
          'medication': {
            'name': 'سیتریزین',
            'strengthText': '10',
          },
          'schedules': [
            {'dayOfWeek': 'friday', 'localTime': '21:00:00'},
            {'dayOfWeek': 'monday', 'localTime': '21:00:00'},
          ],
        },
      ];
}
''',
)

write(
    "caremate/test/jalali_calendar_localization_test.dart",
    r'''import 'package:caremate/screens/calendar/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Persian CareMate calendar is Jalali with correct RTL arrows',
      (tester) async {
    DateTime? page;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: CalendarView(
            focusedMonth: DateTime(2026, 8, 4),
            selectedDate: DateTime(2026, 8, 4),
            onDaySelected: (_, __) {},
            onPageChanged: (value) => page = value,
            getDayEventTypes: (_) => const {},
            hasOverdueEvents: (_) => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مرداد ۱۴۰۵'), findsOneWidget);
    expect(find.text('ژوئیه'), findsNothing);
    expect(
      find.byKey(const ValueKey('caremate-previous-month')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('caremate-previous-month')),
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('caremate-next-month')),
        matching: find.byIcon(Icons.chevron_left_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('caremate-next-month')));
    await tester.pump();
    expect(page, isNotNull);
    expect(page!.isAfter(DateTime(2026, 8, 4)), isTrue);
  });
}
''',
)

print('v0.9.0-internal.3 Persian localization patch applied.')
