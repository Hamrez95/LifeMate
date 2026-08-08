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

const List<String> _shortPersianWeekdays = <String>[
  'ش',
  'ی',
  'د',
  'س',
  'چ',
  'پ',
  'ج',
];

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
      initialDate: _clampDate(initialDate, firstDate, lastDate),
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }

  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (_) => _ModernPersianDatePicker(
      title: title,
      initialDate: _clampDate(initialDate, firstDate, lastDate),
      firstDate: _dateOnly(firstDate),
      lastDate: _dateOnly(lastDate),
    ),
  );
}

class _ModernPersianDatePicker extends StatefulWidget {
  const _ModernPersianDatePicker({
    required this.title,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final String title;
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_ModernPersianDatePicker> createState() =>
      _ModernPersianDatePickerState();
}

class _ModernPersianDatePickerState extends State<_ModernPersianDatePicker> {
  late DateTime _selectedDate;
  late Jalali _focusedMonth;
  bool _showYearPicker = false;

  Jalali get _firstJalali => Jalali.fromDateTime(widget.firstDate);
  Jalali get _lastJalali => Jalali.fromDateTime(widget.lastDate);

  @override
  void initState() {
    super.initState();
    _selectedDate = _dateOnly(widget.initialDate);
    final initial = Jalali.fromDateTime(_selectedDate);
    _focusedMonth = Jalali(initial.year, initial.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final selectedJalali = Jalali.fromDateTime(_selectedDate);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCE2E7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _PickerPreviewHeader(
                    title: widget.title,
                    selectedDate: _selectedDate,
                    selectedJalali: selectedJalali,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFEFF2F5)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0D1B3147),
                            blurRadius: 22,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _showYearPicker
                            ? _buildYearPicker(selectedJalali)
                            : _buildMonthCalendar(selectedJalali),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFEEF1F4))),
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: _selectTodayIfAllowed,
                        child: const Text('امروز'),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('انصراف'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pop(_selectedDate),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('تأیید تاریخ'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(132, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
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

  Widget _buildMonthCalendar(Jalali selectedJalali) {
    final firstDay = _focusedMonth.toDateTime();
    final leadingCells = (firstDay.weekday + 1) % 7;
    final itemCount = leadingCells + _focusedMonth.monthLength;

    return Column(
      key: const ValueKey('persian-date-picker-calendar'),
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'ماه قبل',
              onPressed: _canMoveMonth(-1) ? () => _moveMonth(-1) : null,
              icon: const Icon(
                Icons.chevron_right_rounded,
                textDirection: TextDirection.ltr,
              ),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _showYearPicker = true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          '${_persianMonthNames[_focusedMonth.month - 1]} ${_focusedMonth.year}'
                              .toPersianDigit(true),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'ماه بعد',
              onPressed: _canMoveMonth(1) ? () => _moveMonth(1) : null,
              icon: const Icon(
                Icons.chevron_left_rounded,
                textDirection: TextDirection.ltr,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final label in _shortPersianWeekdays)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF7A8491),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 46,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index < leadingCells) return const SizedBox.shrink();
            final day = index - leadingCells + 1;
            final jalali = Jalali(_focusedMonth.year, _focusedMonth.month, day);
            final date = _dateOnly(jalali.toDateTime());
            final enabled =
                !_isBefore(date, widget.firstDate) &&
                !_isAfter(date, widget.lastDate);
            final selected =
                selectedJalali.year == jalali.year &&
                selectedJalali.month == jalali.month &&
                selectedJalali.day == jalali.day;
            final today = _sameDay(date, DateTime.now());

            return Semantics(
              button: enabled,
              selected: selected,
              label:
                  '${day.toString().toPersianDigit(true)} ${_persianMonthNames[jalali.month - 1]}',
              child: InkWell(
                onTap: enabled
                    ? () => setState(() => _selectedDate = date)
                    : null,
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF18BE8B)
                        : today
                        ? const Color(0xFFE9F9F4)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF18BE8B)
                          : today
                          ? const Color(0xFF6AD2B2)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    day.toString().toPersianDigit(true),
                    style: TextStyle(
                      color: !enabled
                          ? const Color(0xFFC7CDD3)
                          : selected
                          ? Colors.white
                          : const Color(0xFF1D2838),
                      fontSize: 15,
                      fontWeight: selected || today
                          ? FontWeight.w900
                          : FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildYearPicker(Jalali selectedJalali) {
    final firstYear = _firstJalali.year;
    final lastYear = _lastJalali.year;
    return Column(
      key: const ValueKey('persian-date-picker-years'),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'بازگشت به تقویم',
              onPressed: () => setState(() => _showYearPicker = false),
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
            const Expanded(
              child: Text(
                'انتخاب سال',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 250,
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisExtent: 52,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: lastYear - firstYear + 1,
            itemBuilder: (context, index) {
              final year = firstYear + index;
              final selected = year == selectedJalali.year;
              return InkWell(
                onTap: () {
                  final month = _focusedMonth.month
                      .clamp(
                        year == firstYear ? _firstJalali.month : 1,
                        year == lastYear ? _lastJalali.month : 12,
                      )
                      .toInt();
                  setState(() {
                    _focusedMonth = Jalali(year, month, 1);
                    _showYearPicker = false;
                  });
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFE7F8F2)
                        : const Color(0xFFF7F9FA),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF18BE8B)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    year.toString().toPersianDigit(true),
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF087959)
                          : const Color(0xFF263345),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _canMoveMonth(int delta) {
    final target = _shiftMonth(_focusedMonth, delta);
    if (delta < 0) {
      return target.year > _firstJalali.year ||
          (target.year == _firstJalali.year &&
              target.month >= _firstJalali.month);
    }
    return target.year < _lastJalali.year ||
        (target.year == _lastJalali.year && target.month <= _lastJalali.month);
  }

  void _moveMonth(int delta) {
    final target = _shiftMonth(_focusedMonth, delta);
    setState(() => _focusedMonth = target);
  }

  void _selectTodayIfAllowed() {
    final today = _dateOnly(DateTime.now());
    if (_isBefore(today, widget.firstDate) ||
        _isAfter(today, widget.lastDate)) {
      return;
    }
    final jalali = Jalali.fromDateTime(today);
    setState(() {
      _selectedDate = today;
      _focusedMonth = Jalali(jalali.year, jalali.month, 1);
      _showYearPicker = false;
    });
  }
}

class _PickerPreviewHeader extends StatelessWidget {
  const _PickerPreviewHeader({
    required this.title,
    required this.selectedDate,
    required this.selectedJalali,
    required this.onClose,
  });

  final String title;
  final DateTime selectedDate;
  final Jalali selectedJalali;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final weekday = _persianWeekdayNames[selectedDate.weekday] ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF0DBF89), Color(0xFF5CCFAF)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3310AD80),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '$weekday، ${selectedJalali.day.toString().toPersianDigit(true)} ${_persianMonthNames[selectedJalali.month - 1]}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  selectedJalali.year.toString().toPersianDigit(true),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'بستن',
            onPressed: onClose,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

Jalali _shiftMonth(Jalali value, int delta) {
  var year = value.year;
  var month = value.month + delta;
  while (month < 1) {
    month += 12;
    year -= 1;
  }
  while (month > 12) {
    month -= 12;
    year += 1;
  }
  return Jalali(year, month, 1);
}

DateTime _clampDate(DateTime value, DateTime first, DateTime last) {
  final normalized = _dateOnly(value);
  final firstOnly = _dateOnly(first);
  final lastOnly = _dateOnly(last);
  if (_isBefore(normalized, firstOnly)) return firstOnly;
  if (_isAfter(normalized, lastOnly)) return lastOnly;
  return normalized;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

bool _isBefore(DateTime left, DateTime right) =>
    _dateOnly(left).isBefore(_dateOnly(right));

bool _isAfter(DateTime left, DateTime right) =>
    _dateOnly(left).isAfter(_dateOnly(right));
