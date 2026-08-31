import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/theme/app_style.dart';

class SleepScheduleOptimizationScreen extends StatefulWidget {
  const SleepScheduleOptimizationScreen({super.key, this.api});
  final LifeMateMedicationSleepScheduleApi? api;

  @override
  State<SleepScheduleOptimizationScreen> createState() =>
      _SleepScheduleOptimizationScreenState();
}

class _SleepScheduleOptimizationScreenState
    extends State<SleepScheduleOptimizationScreen> {
  late final LifeMateMedicationSleepScheduleApi _api =
      widget.api ?? LifeMateMedicationSleepScheduleApi.fromEnvironment();
  LifeMateSleepOptimizationMode _mode =
      LifeMateSleepOptimizationMode.strictAnchorShift;
  int _variation = 30;
  late DateTime _from = DateTime.now();
  late DateTime _until = DateTime.now().add(const Duration(days: 6));
  LifeMateSleepOptimizationPreview? _preview;
  LifeMateSleepOptimizationReceipt? _receipt;
  bool _busy = false;
  String? _error;

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';
  String _copy(String fa, String en) => _fa ? fa : en;

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _receipt = null;
    });
    try {
      final value = await _api.preview(
        mode: _mode,
        effectiveFrom: _from,
        effectiveUntil: _until,
        maxVariationMinutes:
            _mode == LifeMateSleepOptimizationMode.flexibleInterval
                ? _variation
                : null,
      );
      if (!mounted) return;
      setState(() {
        _preview = value;
        _busy = false;
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.code == 'sleep_preferences_required'
            ? _copy(
                'اول ساعات خواب را در تنظیمات زمان‌بندی فعال کن.',
                'Enable sleep preferences in medication timing settings first.',
              )
            : _copy(
                'پیشنهاد آماده نشد. برنامه یا تنظیمات تغییر کرده؛ دوباره تلاش کن.',
                'The proposal could not be prepared. Your schedule or settings may have changed.',
              );
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _copy(
            'پیشنهاد آماده نشد. اتصال را بررسی کن.',
            'The proposal could not be prepared. Check your connection.',
          );
        });
      }
    }
  }

  Future<void> _apply() async {
    final preview = _preview;
    if (preview == null || !preview.hasChanges || _busy) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_copy('تأیید تغییرات زمان', 'Confirm timing changes')),
        content: Text(
          _mode == LifeMateSleepOptimizationMode.flexibleInterval
              ? _copy(
                  'تو زمان‌های پیشنهادی و تغییر فاصله هر نوبت را دیده‌ای. این انتخاب توصیه پزشکی یا تأیید ایمنی نیست؛ اگر پزشک یا داروساز فاصله مشخصی گفته، همان دستور را دنبال کن.',
                  'You reviewed the proposed times and every changed gap. This is not medical advice or a safety approval; follow any timing instruction from your prescriber or pharmacist.',
                )
              : _copy(
                  'فقط ساعت شروع جابه‌جا می‌شود و فاصله دقیق هر دارو تغییر نمی‌کند. این پیشنهاد بررسی تداخل دارویی نیست.',
                  'Only the schedule anchor moves; every exact medication interval remains unchanged. This proposal does not check drug interactions.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_copy('انصراف', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_copy('تأیید و اعمال', 'Confirm & apply')),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await _api.apply(preview: preview);
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _busy = false;
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.statusCode == 409
            ? _copy(
                'پیشنهاد قدیمی شده است. پیش‌نمایش تازه بگیر.',
                'This proposal is stale. Create a fresh preview.',
              )
            : _copy('تغییرات اعمال نشد.', 'Changes were not applied.');
      });
    }
  }

  Future<void> _undo() async {
    final receipt = _receipt;
    if (receipt == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.undo(receipt.runId);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _receipt = null;
        _preview = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _copy(
              'برنامه به حالت دقیق قبلی برگشت.',
              'The schedule returned to its previous exact state.',
            ),
          ),
        ),
      );
    } on LifeMateApiException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _copy(
            'بعد از اعمال، برنامه دوباره تغییر کرده و بازگشت خودکار ممکن نیست.',
            'The schedule changed after apply, so automatic undo is no longer available.',
          );
        });
      }
    }
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _gap(int? minutes) {
    if (minutes == null) return '—';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (_fa) return rest == 0 ? '$hours ساعت' : '$hours ساعت و $rest دقیقه';
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(_copy('تنظیم زمان با ساعات خواب', 'Sleep-aware medication timing')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _copy('۱. روش پیشنهادی', '1. Proposal mode'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  RadioListTile<LifeMateSleepOptimizationMode>(
                    value: LifeMateSleepOptimizationMode.strictAnchorShift,
                    groupValue: _mode,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                              _mode = value!;
                              _preview = null;
                            }),
                    title: Text(_copy('فاصله دقیق را نگه دار', 'Keep exact interval')),
                    subtitle: Text(
                      _copy(
                        'ممکن است ساعت شروع بیشتر از ۳۰ دقیقه جابه‌جا شود، اما مثلاً فاصله ۸ ساعت دقیقاً ۸ ساعت می‌ماند.',
                        'The anchor may move by more than 30 minutes, but an 8-hour interval stays exactly 8 hours.',
                      ),
                    ),
                  ),
                  RadioListTile<LifeMateSleepOptimizationMode>(
                    value: LifeMateSleepOptimizationMode.flexibleInterval,
                    groupValue: _mode,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                              _mode = value!;
                              _preview = null;
                            }),
                    title: Text(_copy('پیشنهاد زمان منعطف را ببین', 'See a flexible-time proposal')),
                    subtitle: Text(
                      _copy(
                        'فقط با انتخاب تو؛ هر فاصله می‌تواند حداکثر به اندازه‌ای که مشخص می‌کنی کم یا زیاد شود و فقط در بازه زیر.',
                        'Only if you choose it; each gap may vary only within your selected bound and only for the date range below.',
                      ),
                    ),
                  ),
                  if (_mode == LifeMateSleepOptimizationMode.flexibleInterval) ...[
                    const Divider(height: 28),
                    Text(
                      _copy('حداکثر تغییر هر فاصله', 'Maximum change per gap'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final value in const [15, 30, 45, 60])
                          ChoiceChip(
                            label: Text(_copy('$value دقیقه', '$value min')),
                            selected: _variation == value,
                            onSelected: _busy
                                ? null
                                : (_) => setState(() {
                                      _variation = value;
                                      _preview = null;
                                    }),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _copy('۲. بازه اثر', '2. Effective range'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text('${_date(_from)} → ${_date(_until)}'),
                  const SizedBox(height: 8),
                  Text(
                    _copy(
                      'نسخه اول حداکثر ۱۴ روز است. بعد از پایان بازه، برنامه منعطف به فاصله دقیق اصلی برمی‌گردد.',
                      'V1 is limited to 14 days. After the range ends, flexible timing returns to the original exact recurrence.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final days in const [3, 7, 14])
                        ChoiceChip(
                          label: Text(_copy('$days روز', '$days days')),
                          selected: _until.difference(_from).inDays + 1 == days,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() {
                                    _until = _from.add(Duration(days: days - 1));
                                    _preview = null;
                                  }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _prepare,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.preview_outlined),
              label: Text(_copy('ساخت پیش‌نمایش', 'Create preview')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _card(child: Text(_error!)),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 22),
              _previewSection(_preview!),
            ],
            if (_receipt != null) ...[
              const SizedBox(height: 18),
              _receiptSection(_receipt!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _previewSection(LifeMateSleepOptimizationPreview preview) {
    if (!preview.hasChanges) {
      return _card(
        child: Text(
          _copy(
            'با محدودیت‌های انتخاب‌شده پیشنهاد بهتری پیدا نشد؛ برنامه دقیق فعلی بدون تغییر می‌ماند.',
            'No better proposal satisfies the selected constraints; your exact schedule remains unchanged.',
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _copy('۳. پیش‌نمایش دقیق', '3. Exact preview'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        for (final plan in preview.proposals) ...[
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.medicationName,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 7),
                if (preview.mode == 'strict_anchor_shift') ...[
                  Text('${plan.oldAnchorLocalTime} → ${plan.newAnchorLocalTime}'),
                  Text(
                    _copy(
                      'فاصله دقیق هر ${plan.intervalHours} ساعت بدون تغییر می‌ماند.',
                      'The exact ${plan.intervalHours}-hour interval remains unchanged.',
                    ),
                  ),
                ] else ...[
                  Text(
                    _copy(
                      'فاصله واردشده: ${plan.intervalHours} ساعت · حداکثر تغییر مجاز: ${preview.maxVariationMinutes} دقیقه',
                      'Entered interval: ${plan.intervalHours}h · maximum allowed change: ${preview.maxVariationMinutes} min',
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final occurrence in plan.occurrences)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${occurrence.originalLocalDate} ${occurrence.originalLocalTime} → '
                        '${occurrence.proposedLocalDate} ${occurrence.proposedLocalTime} · '
                        '${_gap(occurrence.enteredGapMinutes)} → ${_gap(occurrence.proposedGapMinutes)}',
                      ),
                    ),
                ],
                const SizedBox(height: 6),
                Text(
                  _copy(
                    'برخورد با ساعات خواب: ${plan.sleepHitsBefore} → ${plan.sleepHitsAfter}',
                    'Sleep-window hits: ${plan.sleepHitsBefore} → ${plan.sleepHitsAfter}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        _card(
          child: Text(
            _copy(
              'LifeMate بر اساس نام دارو هیچ فاصله پزشکی اختراع نمی‌کند و درباره ایمنی مصرف همزمان قضاوت نمی‌کند.',
              'LifeMate never invents clinical spacing from a medication name and does not judge whether taking medications together is safe.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _apply,
          icon: const Icon(Icons.done_all_rounded),
          label: Text(_copy('تأیید نهایی و اعمال', 'Final confirm & apply')),
        ),
      ],
    );
  }

  Widget _receiptSection(LifeMateSleepOptimizationReceipt receipt) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _copy('رسید تغییر زمان‌بندی', 'Timing change receipt'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text('${receipt.effectiveFromLocalDate} → ${receipt.effectiveUntilLocalDate}'),
            Text(_copy(
              'این رسید فقط ثبت می‌کند که تو زمان‌های نمایش‌داده‌شده را انتخاب کردی؛ تأیید پزشکی نیست.',
              'This receipt records that you chose the displayed timing changes; it is not medical approval.',
            )),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _undo,
              icon: const Icon(Icons.undo_rounded),
              label: Text(_copy('بازگشت به برنامه دقیق', 'Return to exact schedule')),
            ),
          ],
        ),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );
}
