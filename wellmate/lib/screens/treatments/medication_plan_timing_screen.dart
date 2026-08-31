import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/theme/app_style.dart';

class MedicationPlanTimingScreen extends StatefulWidget {
  const MedicationPlanTimingScreen({
    required this.plan,
    super.key,
    this.api,
  });

  final LifeMateMedicationSchedulePlan plan;
  final LifeMateMedicationScheduleApi? api;

  @override
  State<MedicationPlanTimingScreen> createState() =>
      _MedicationPlanTimingScreenState();
}

class _MedicationPlanTimingScreenState extends State<MedicationPlanTimingScreen> {
  late final LifeMateMedicationScheduleApi _api =
      widget.api ?? LifeMateMedicationScheduleApi.fromEnvironment();
  late LifeMateTreatmentPlanTiming _current = widget.plan.timing;
  late bool _locked = _current.timingLocked;
  late bool _nearby = _current.nearbyGroupingEnabled;
  late final TextEditingController _before = TextEditingController(
    text: _current.manualSpacingBeforeMinutes.toString(),
  );
  late final TextEditingController _after = TextEditingController(
    text: _current.manualSpacingAfterMinutes.toString(),
  );
  late final TextEditingController _note = TextEditingController(
    text: _current.timingNote ?? '',
  );
  bool _saving = false;
  String? _error;

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';
  String _copy(String fa, String en) => _fa ? fa : en;

  @override
  void dispose() {
    _before.dispose();
    _after.dispose();
    _note.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  int? _spacing(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    return value != null && value >= 0 && value <= 1440 ? value : null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final before = _spacing(_before);
    final after = _spacing(_after);
    if (before == null || after == null) {
      setState(() {
        _error = _copy(
          'فاصله باید عددی بین ۰ تا ۱۴۴۰ دقیقه باشد.',
          'Spacing must be an integer from 0 to 1440 minutes.',
        );
      });
      return;
    }
    if (_note.text.trim().length > 240) {
      setState(() {
        _error = _copy(
          'توضیح فاصله حداکثر ۲۴۰ نویسه است.',
          'The spacing note can be at most 240 characters.',
        );
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _api.savePlanTiming(
        current: _current,
        nearbyGroupingEnabled: _nearby,
        timingLocked: _locked,
        manualSpacingBeforeMinutes: before,
        manualSpacingAfterMinutes: after,
        timingNote: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _current = updated;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _copy('قواعد زمان‌بندی ذخیره شد.', 'Timing rules saved.'),
          ),
        ),
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 409) {
        try {
          final refreshed = await _api.getPlanTiming(_current.treatmentPlanId);
          if (!mounted) return;
          setState(() {
            _current = refreshed;
            _locked = refreshed.timingLocked;
            _nearby = refreshed.nearbyGroupingEnabled;
            _before.text = refreshed.manualSpacingBeforeMinutes.toString();
            _after.text = refreshed.manualSpacingAfterMinutes.toString();
            _note.text = refreshed.timingNote ?? '';
            _saving = false;
            _error = _copy(
              'این تنظیمات جای دیگری تغییر کرده بود. آخرین نسخه بارگذاری شد؛ دوباره بررسی و ذخیره کن.',
              'These settings changed elsewhere. The latest version was loaded; review and save again.',
            );
          });
          return;
        } catch (_) {
          // Fall through to the generic failure below.
        }
      }
      setState(() {
        _saving = false;
        _error = _copy(
          'ذخیره قواعد زمان‌بندی انجام نشد.',
          'Timing rules could not be saved.',
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _copy(
          'ذخیره قواعد زمان‌بندی انجام نشد.',
          'Timing rules could not be saved.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final manualSpacing = (_spacing(_before) ?? 0) > 0 ||
        (_spacing(_after) ?? 0) > 0 ||
        _note.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(_copy('قواعد زمان‌بندی', 'Medication timing rules')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              widget.plan.medicationName,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.darkBlue,
              ),
            ),
            if (widget.plan.strengthText != null) ...[
              const SizedBox(height: 4),
              Text(widget.plan.strengthText!),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _locked,
                    onChanged: _saving
                        ? null
                        : (value) {
                            setState(() {
                              _locked = value;
                              if (value) _nearby = false;
                            });
                          },
                    secondary: const Icon(Icons.lock_clock_outlined),
                    title: Text(
                      _copy('این زمان ثابت بماند', 'Keep this timing fixed'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      _copy(
                        'وقتی روشن است، این دارو وارد هیچ پیشنهاد جابه‌جایی خودکار نمی‌شود.',
                        'When enabled, this medication is excluded from automatic timing proposals.',
                      ),
                    ),
                  ),
                  const Divider(height: 24),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _nearby,
                    onChanged: _saving || _locked || manualSpacing
                        ? null
                        : (value) => setState(() => _nearby = value),
                    secondary: const Icon(Icons.merge_type_rounded),
                    title: Text(
                      _copy(
                        'اجازه پیشنهاد برای زمان‌های نزدیک',
                        'Allow nearby-time proposals',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      _copy(
                        'فقط اجازه ساخت پیش‌نمایش می‌دهد؛ هیچ زمان مصرفی بدون تأیید تو تغییر نمی‌کند.',
                        'This only allows a preview to be prepared; no dose time changes without your confirmation.',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _copy(
                      'دستور فاصله زمانی',
                      'Required spacing instruction',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _copy(
                      'فقط فاصله‌ای را وارد کن که در نسخه یا دستور پزشک/داروساز به تو گفته شده است. LifeMate این مقدار را از نظر پزشکی بررسی یا استنباط نمی‌کند.',
                      'Only enter spacing from your prescription or pharmacist/clinician instruction. LifeMate does not medically validate or infer this value.',
                    ),
                    style: const TextStyle(height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _before,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {
                            if ((_spacing(_before) ?? 0) > 0 ||
                                (_spacing(_after) ?? 0) > 0) {
                              _nearby = false;
                            }
                          }),
                          decoration: InputDecoration(
                            labelText: _copy('دقیقه قبل', 'Minutes before'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _after,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {
                            if ((_spacing(_before) ?? 0) > 0 ||
                                (_spacing(_after) ?? 0) > 0) {
                              _nearby = false;
                            }
                          }),
                          decoration: InputDecoration(
                            labelText: _copy('دقیقه بعد', 'Minutes after'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _note,
                    enabled: !_saving,
                    maxLength: 240,
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: _copy(
                        'توضیح اختیاری دستور',
                        'Optional instruction note',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_copy('ذخیره', 'Save')),
            ),
          ],
        ),
      ),
    );
  }
}
