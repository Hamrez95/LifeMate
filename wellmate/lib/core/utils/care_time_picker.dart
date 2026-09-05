import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../theme/app_style.dart';
import 'persian_date_utils.dart';

/// A 24-hour, Persian-first time picker for care plans.
///
/// It deliberately keeps the selected time large, offers common daily times,
/// and still lets people enter an exact prescribed time without fighting a dial.
Future<TimeOfDay?> showCareTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String title = 'انتخاب ساعت',
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (_) => _CareTimePickerSheet(title: title, initialTime: initialTime),
  );
}

class _CareTimePickerSheet extends StatefulWidget {
  const _CareTimePickerSheet({required this.title, required this.initialTime});

  final String title;
  final TimeOfDay initialTime;

  @override
  State<_CareTimePickerSheet> createState() => _CareTimePickerSheetState();
}

class _CareTimePickerSheetState extends State<_CareTimePickerSheet> {
  late int _hour;
  late int _minute;
  late TextEditingController _hourController;
  late TextEditingController _minuteController;
  String? _error;

  static const _suggestions = <(int, int, String)>[
    (8, 0, 'صبح'),
    (12, 0, 'ظهر'),
    (18, 0, 'عصر'),
    (22, 0, 'شب'),
  ];

  @override
  void initState() {
    super.initState();
    _hour = widget.initialTime.hour;
    _minute = widget.initialTime.minute;
    _hourController = TextEditingController(text: _formatPart(_hour));
    _minuteController = TextEditingController(text: _formatPart(_minute));
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  String _formatPart(int value) =>
      localizeDigits(context, value.toString().padLeft(2, '0'));

  void _setTime(int hour, int minute) {
    setState(() {
      _hour = hour;
      _minute = minute;
      _error = null;
      _hourController.text = _formatPart(hour);
      _minuteController.text = _formatPart(minute);
    });
  }

  int? _parse(String value) {
    final latin = value
        .replaceAll('۰', '0')
        .replaceAll('۱', '1')
        .replaceAll('۲', '2')
        .replaceAll('۳', '3')
        .replaceAll('۴', '4')
        .replaceAll('۵', '5')
        .replaceAll('۶', '6')
        .replaceAll('۷', '7')
        .replaceAll('۸', '8')
        .replaceAll('۹', '9');
    return int.tryParse(latin.trim());
  }

  void _applyPart(String value, {required bool hour}) {
    final parsed = _parse(value);
    final valid = parsed != null && (hour ? parsed <= 23 : parsed <= 59) && parsed >= 0;
    if (!valid) {
      setState(() => _error = hour ? 'ساعت باید بین ۰۰ تا ۲۳ باشد.' : 'دقیقه باید بین ۰۰ تا ۵۹ باشد.');
      return;
    }
    _setTime(hour ? parsed : _hour, hour ? _minute : parsed);
  }

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: _hour, minute: _minute);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Directionality(
      textDirection: LifeMateRuntimeLocale.isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAF9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7E0DC),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.darkBlue)),
                    ),
                    IconButton(
                      tooltip: 'بستن',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    formatAppTime(context, time),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: 1, color: AppColors.darkBlue),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('ساعت دقیق را وارد کنید', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _TimePartField(label: 'ساعت', controller: _hourController, onSubmitted: (value) => _applyPart(value, hour: true))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(':', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.darkBlue)),
                    ),
                    Expanded(child: _TimePartField(label: 'دقیقه', controller: _minuteController, onSubmitted: (value) => _applyPart(value, hour: false))),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Color(0xFFC64040), fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 18),
                const Text('زمان‌های پیشنهادی', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final suggestion in _suggestions)
                      ChoiceChip(
                        label: Text('${suggestion.$3} · ${localizeDigits(context, '${suggestion.$1.toString().padLeft(2, '0')}:${suggestion.$2.toString().padLeft(2, '0')}')}'),
                        selected: _hour == suggestion.$1 && _minute == suggestion.$2,
                        onSelected: (_) => _setTime(suggestion.$1, suggestion.$2),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const ValueKey('care-time-picker-confirm'),
                  onPressed: () => Navigator.of(context).pop(time),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: const Text('تأیید ساعت'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimePartField extends StatelessWidget {
  const _TimePartField({required this.label, required this.controller, required this.onSubmitted});

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey<String>('care-time-picker-$label'),
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLength: 2,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.darkBlue),
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFDFE8E4))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFDFE8E4))),
      ),
      onFieldSubmitted: onSubmitted,
      onChanged: onSubmitted,
    );
  }
}
