import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart'
    hide LifeMateLocaleDigitInputFormatter;

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
        _error = context.tr('medication.schedule.rules.invalidSpacing');
      });
      return;
    }
    if (_note.text.trim().length > 240) {
      setState(() {
        _error = context.tr('medication.schedule.rules.noteTooLong');
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
          content: Text(context.tr('medication.schedule.rules.saved')),
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
            _error = context.tr('medication.schedule.rules.stale');
          });
          return;
        } catch (_) {
          // Fall through to the generic failure below.
        }
      }
      setState(() {
        _saving = false;
        _error = context.tr('medication.schedule.rules.saveFailed');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.tr('medication.schedule.rules.saveFailed');
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
        title: Text(context.tr('medication.schedule.rules.title')),
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
                      context.tr('medication.schedule.rules.fixedTitle'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      context.tr('medication.schedule.rules.fixedDescription'),
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
                      context.tr('medication.schedule.rules.nearbyTitle'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      context.tr('medication.schedule.rules.nearbyDescription'),
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
                    context.tr('medication.schedule.rules.spacingTitle'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('medication.schedule.rules.spacingDescription'),
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
                          inputFormatters: const [
                            LifeMateLocaleDigitInputFormatter(),
                          ],
                          onChanged: (_) => setState(() {
                            if ((_spacing(_before) ?? 0) > 0 ||
                                (_spacing(_after) ?? 0) > 0) {
                              _nearby = false;
                            }
                          }),
                          decoration: InputDecoration(
                            labelText: context.tr(
                              'medication.schedule.rules.minutesBefore',
                            ),
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
                          inputFormatters: const [
                            LifeMateLocaleDigitInputFormatter(),
                          ],
                          onChanged: (_) => setState(() {
                            if ((_spacing(_before) ?? 0) > 0 ||
                                (_spacing(_after) ?? 0) > 0) {
                              _nearby = false;
                            }
                          }),
                          decoration: InputDecoration(
                            labelText: context.tr(
                              'medication.schedule.rules.minutesAfter',
                            ),
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
                      labelText: context.tr('medication.schedule.rules.note'),
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
              label: Text(context.tr('common.save')),
            ),
          ],
        ),
      ),
    );
  }
}
