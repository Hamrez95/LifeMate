import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:lifemate_client/lifemate_client.dart';

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
    LifeMateNumbers.localize(context, value);

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
