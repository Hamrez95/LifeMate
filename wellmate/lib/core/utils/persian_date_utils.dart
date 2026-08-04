import 'package:flutter/material.dart';
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

String formatAppTime(BuildContext context, TimeOfDay time) {
  final value =
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
  return value.toPersianDigit(usesPersianCalendar(context));
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

Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'انتخاب تاریخ',
}) {
  if (!usesPersianCalendar(context)) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }

  final initial = Jalali.fromDateTime(initialDate);
  final first = Jalali.fromDateTime(firstDate);
  final last = Jalali.fromDateTime(lastDate);
  var year = initial.year;
  var month = initial.month;
  var day = initial.day;
  String? validationError;

  return showDialog<DateTime>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final monthLength = Jalali(year, month, 1).monthLength;
        if (day > monthLength) day = monthLength;

        void confirm() {
          final selected = Jalali(year, month, day).toDateTime();
          final selectedOnly = DateTime(
            selected.year,
            selected.month,
            selected.day,
          );
          final firstOnly = DateTime(
            firstDate.year,
            firstDate.month,
            firstDate.day,
          );
          final lastOnly = DateTime(
            lastDate.year,
            lastDate.month,
            lastDate.day,
          );
          if (selectedOnly.isBefore(firstOnly) ||
              selectedOnly.isAfter(lastOnly)) {
            setDialogState(() {
              validationError = 'تاریخ انتخاب‌شده خارج از بازه مجاز است.';
            });
            return;
          }
          Navigator.of(dialogContext).pop(selectedOnly);
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<int>(
                          initialValue: year,
                          decoration: const InputDecoration(
                            labelText: 'سال',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (
                              var value = first.year;
                              value <= last.year;
                              value++
                            )
                              DropdownMenuItem(
                                value: value,
                                child: Text('$value'.toPersianDigit(true)),
                              ),
                          ],
                          onChanged: (value) => setDialogState(() {
                            year = value ?? year;
                            validationError = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: DropdownButtonFormField<int>(
                          initialValue: month,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'ماه',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (var value = 1; value <= 12; value++)
                              DropdownMenuItem(
                                value: value,
                                child: Text(_persianMonthNames[value - 1]),
                              ),
                          ],
                          onChanged: (value) => setDialogState(() {
                            month = value ?? month;
                            validationError = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<int>(
                          initialValue: day,
                          decoration: const InputDecoration(
                            labelText: 'روز',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (var value = 1; value <= monthLength; value++)
                              DropdownMenuItem(
                                value: value,
                                child: Text('$value'.toPersianDigit(true)),
                              ),
                          ],
                          onChanged: (value) => setDialogState(() {
                            day = value ?? day;
                            validationError = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${_persianWeekdayNames[Jalali(year, month, day).toDateTime().weekday] ?? ''}، '
                    '${day.toString().toPersianDigit(true)} '
                    '${_persianMonthNames[month - 1]} '
                    '${year.toString().toPersianDigit(true)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (validationError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      validationError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('انصراف'),
              ),
              FilledButton(onPressed: confirm, child: const Text('تأیید')),
            ],
          ),
        );
      },
    ),
  );
}
