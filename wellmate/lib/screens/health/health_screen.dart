import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/state/wellmate_refresh.dart';
import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../calendar/custom_table_calendar.dart';
import 'health_entry_sheet.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key, this.refreshToken = 0, this.healthApi});

  final int refreshToken;
  final LifeMateHealthApi? healthApi;

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  late final LifeMateHealthApi _healthApi;
  late final bool _ownsHealthApi;
  List<LifeMateHealthObservation> _observations = const [];
  List<_TimelineEvent> _treatmentTimeline = const [];
  bool _loading = true;
  String? _loadError;
  String _timeZone = 'Asia/Tehran';
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ownsHealthApi = widget.healthApi == null;
    _healthApi = widget.healthApi ?? LifeMateHealthApi.fromEnvironment();
    _load();
  }

  @override
  void didUpdateWidget(covariant HealthScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load(background: true);
    }
  }

  @override
  void dispose() {
    if (_ownsHealthApi) _healthApi.close();
    super.dispose();
  }

  Future<void> _load({bool background = false}) async {
    if (!background && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final now = DateTime.now();
      final from = DateTime(now.year - 1, now.month, now.day);
      final to = DateTime(now.year, now.month, now.day);
      final observations = await _healthApi.listObservations(
        fromDate: from,
        toDate: to,
      );

      var timeZone = _timeZone;
      var treatmentTimeline = _treatmentTimeline;
      LifeMateApiClient? coreApi;
      try {
        coreApi = context.read<LifeMateApiClient>();
      } catch (_) {
        coreApi = null;
      }
      if (coreApi != null) {
        try {
          final current = await coreApi.getCurrentUser();
          final profile = current['profile'];
          if (profile is Map &&
              profile['timeZone']?.toString().trim().isNotEmpty == true) {
            timeZone = profile['timeZone'].toString().trim();
          }
        } catch (_) {
          // Health logging remains usable even if the profile refresh is partial.
        }
        treatmentTimeline = await _loadTreatmentTimeline(coreApi);
      }

      if (!mounted) return;
      setState(() {
        _observations = _sortedUnique(observations);
        _treatmentTimeline = treatmentTimeline;
        _timeZone = timeZone;
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'اطلاعات سلامت دریافت نشد. اتصال را بررسی کن.',
            en: "Health information not received. Check the connection.",
          ),
          en: "Health information not received. Check the connection.",
        );
      });
    }
  }

  Future<List<_TimelineEvent>> _loadTreatmentTimeline(
    LifeMateApiClient api,
  ) async {
    try {
      final now = DateTime.now();
      final from = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 7));
      final to = DateTime(now.year, now.month, now.day);
      final plans = await api.getTreatmentPlans();
      final plansById = <String, Map<String, dynamic>>{
        for (final plan in plans) plan['id'].toString(): plan,
      };
      final doses = await api.getDoseOccurrences(fromDate: from, toDate: to);
      final careEvents = await api.getCareEvents(fromDate: from, toDate: to);
      final values = <_TimelineEvent>[];

      for (final dose in doses) {
        if (dose['status']?.toString().toLowerCase() != 'taken') continue;
        final plan = plansById[dose['treatmentPlanId']?.toString() ?? ''];
        final medication = plan?['medication'];
        final medicationName = medication is Map
            ? medication['name']?.toString().trim()
            : null;
        final timestamp = DateTime.tryParse(
          dose['respondedAtUtc']?.toString() ??
              dose['scheduledAtUtc']?.toString() ??
              '',
        );
        if (timestamp == null) continue;
        values.add(
          _TimelineEvent(
            occurredAt: timestamp.toLocal(),
            title: medicationName?.isNotEmpty == true
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'داروی $medicationName مصرف شد',
                      en: "$medicationName medicine was consumed",
                    ),
                    en: "$medicationName medicine was consumed",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'مصرف دارو ثبت شد',
                      en: "Medication intake was recorded",
                    ),
                    en: "Medication intake was recorded",
                  ),
            subtitle: plan?['doseText']?.toString() ?? '',
            icon: Icons.medication_rounded,
            color: Color(0xFF31B99B),
          ),
        );
      }
      for (final event in careEvents) {
        if (event['status']?.toString().toLowerCase() != 'completed') continue;
        final timestamp = DateTime.tryParse(
          event['updatedAtUtc']?.toString() ??
              event['scheduledAtUtc']?.toString() ??
              '',
        );
        if (timestamp == null) continue;
        final type = event['eventType']?.toString().toLowerCase();
        values.add(
          _TimelineEvent(
            occurredAt: timestamp.toLocal(),
            title: LifeMateRuntimeLocale.select(
              fa: '${event['title'] ?? (type == 'injection' ? 'تزریق' : 'ویزیت')} انجام شد',
              en: "${event['title'] ?? (type == 'injection' ? 'تزریق' : 'ویزیت')} done",
            ),
            subtitle: type == 'injection'
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'تزریق',
                      en: "Injection",
                    ),
                    en: "Injection",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'رویداد مراقبتی',
                      en: "Care event",
                    ),
                    en: "Care event",
                  ),
            icon: type == 'injection'
                ? Icons.vaccines_rounded
                : Icons.event_available_rounded,
            color: type == 'injection' ? Color(0xFFF2A43A) : Color(0xFF5A9EE7),
          ),
        );
      }
      values.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return values.take(12).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _loadFocusedMonth(DateTime focused) async {
    setState(() => _focusedMonth = focused);
    final range = visibleCalendarMonthRange(context, focused);
    try {
      final additional = await _healthApi.listObservations(
        fromDate: range.$1,
        toDate: range.$2,
      );
      if (!mounted) return;
      setState(
        () => _observations = _sortedUnique([..._observations, ...additional]),
      );
    } catch (_) {
      // Existing history stays visible when paging temporarily fails.
    }
  }

  List<LifeMateHealthObservation> _sortedUnique(
    Iterable<LifeMateHealthObservation> values,
  ) {
    final byId = <String, LifeMateHealthObservation>{
      for (final value in values) value.id: value,
    };
    final result = byId.values.toList(growable: false)
      ..sort((a, b) => b.observedAtUtc.compareTo(a.observedAtUtc));
    return result;
  }

  Future<void> _openEntry(HealthEntryType type) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (_) => HealthEntrySheet(
        type: type,
        onSubmit: (draft) async {
          await _healthApi.createObservation(
            observationType: draft.observationType,
            valuePrimary: draft.valuePrimary,
            valueSecondary: draft.valueSecondary,
            note: draft.note,
            observedAtUtc: draft.localDateTime.toUtc(),
            observedLocalDate: draft.localDateTime,
            timeZone: _timeZone,
          );
          await _load(background: true);
          WellMateRefreshSignal.notifyChanged();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'اطلاعات سلامت ذخیره شد.',
                      en: "Health information saved.",
                    ),
                    en: "Health information saved.",
                  ),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _deleteObservation(LifeMateHealthObservation observation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'حذف این ثبت؟',
              en: "Delete this record?",
            ),
            en: "Delete this record?",
          ),
        ),
        content: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'این مورد از تاریخچه سلامت حذف می‌شود.',
              en: "This item will be removed from your health history.",
            ),
            en: "This item will be removed from your health history.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'انصراف', en: "opt out"),
                en: "opt out",
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'حذف', en: "Delete"),
                en: "remove",
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _healthApi.deleteObservation(observationId: observation.id);
      await _load(background: true);
      WellMateRefreshSignal.notifyChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'حذف انجام نشد. دوباره تلاش کن.',
                  en: "Delete failed. try again",
                ),
                en: "Delete failed. try again",
              ),
            ),
          ),
        );
      }
    }
  }

  LifeMateHealthObservation? _latest(String type) {
    for (final value in _observations) {
      if (value.observationType == type) return value;
    }
    return null;
  }

  List<LifeMateHealthObservation> _forDay(DateTime date) => _observations
      .where((value) => _sameDay(value.observedLocalDate, date))
      .toList(growable: false);

  double? get _bmi {
    final weight = _latest('weight')?.valuePrimary;
    final heightCm = _latest('height')?.valuePrimary;
    if (weight == null || heightCm == null || heightCm <= 0) return null;
    final meters = heightCm / 100;
    return weight / (meters * meters);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _observations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        key: const PageStorageKey('wellmate-health-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          _buildTitle(),
          const SizedBox(height: 18),
          if (_loadError != null) ...[
            _ErrorBanner(message: _loadError!, onRetry: _load),
            const SizedBox(height: 14),
          ],
          _buildTodaySummary(),
          const SizedBox(height: 14),
          _buildBodyCards(),
          const SizedBox(height: 14),
          _buildVitals(),
          const SizedBox(height: 14),
          _buildQuickLog(),
          const SizedBox(height: 14),
          _buildTimeline(),
          const SizedBox(height: 18),
          _buildCalendarHistory(),
          const SizedBox(height: 18),
          const _ConnectedHealthComingSoon(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.09),
                blurRadius: 18,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Icon(
            Icons.monitor_heart_outlined,
            color: AppColors.primary,
            size: 29,
          ),
        ),
        SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'سلامت من',
                    en: "My Health",
                  ),
                  en: "my health",
                ),
                key: ValueKey('health-title'),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 3),
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'خلاصه وضعیت بدن و علائم حیاتی',
                    en: "Summary of body condition and vital signs",
                  ),
                  en: "Summary of body condition and vital signs",
                ),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTodaySummary() {
    final weight = _latest('weight');
    final pressure = _latest('blood_pressure');
    final heartRate = _latest('heart_rate');
    final sleep = _latest('sleep_duration');
    final latest = _observations.isEmpty ? null : _observations.first;
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.event_available_rounded, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'خلاصه امروز',
                      en: "Today's summary",
                    ),
                    en: "Today's summary",
                  ),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          SizedBox(height: 5),
          Text(
            latest == null
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'هنوز اطلاعاتی ثبت نشده',
                      en: "No information has been registered yet",
                    ),
                    en: "No information has been registered yet",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'آخرین ثبت: ${formatAppDate(context, latest.observedLocalDate)} • ${_formatClock(latest.observedAtUtc.toLocal())}',
                      en: "Last registration: ${formatAppDate(context, latest.observedLocalDate)} • ${_formatClock(latest.observedAtUtc.toLocal())}",
                    ),
                    en: "Last registration: ${formatAppDate(context, latest.observedLocalDate)} • ${_formatClock(latest.observedAtUtc.toLocal())}",
                  ),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.bedtime_rounded,
                  color: Color(0xFF956CE6),
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(fa: 'خواب', en: "sleep"),
                    en: "sleep",
                  ),
                  value: sleep == null ? '—' : _sleepLabel(sleep.valuePrimary),
                  onTap: () => _openEntry(HealthEntryType.sleep),
                ),
              ),
              _SummaryDivider(),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.favorite_rounded,
                  color: Color(0xFFF26C7D),
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ضربان قلب',
                      en: "heartbeat",
                    ),
                    en: "heartbeat",
                  ),
                  value: heartRate == null
                      ? '—'
                      : '${_number(heartRate.valuePrimary, decimals: 0)} bpm',
                  onTap: () => _openEntry(HealthEntryType.heartRate),
                ),
              ),
              _SummaryDivider(),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.water_drop_rounded,
                  color: Color(0xFFFF8A4C),
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'فشار خون',
                      en: "blood pressure",
                    ),
                    en: "blood pressure",
                  ),
                  value: pressure == null
                      ? '—'
                      : '${_number(pressure.valuePrimary, decimals: 0)}/${_number(pressure.valueSecondary, decimals: 0)}',
                  onTap: () => _openEntry(HealthEntryType.bloodPressure),
                ),
              ),
              _SummaryDivider(),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.monitor_weight_rounded,
                  color: Color(0xFF48B9C7),
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(fa: 'وزن', en: "weight"),
                    en: "weight",
                  ),
                  value: weight == null
                      ? '—'
                      : '${_number(weight.valuePrimary)} kg',
                  onTap: () => _openEntry(HealthEntryType.weight),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBodyCards() {
    final weights =
        _observations
            .where((item) => item.observationType == 'weight')
            .where(
              (item) =>
                  DateTime.now().difference(item.observedAtUtc).inDays <= 30,
            )
            .toList(growable: false)
          ..sort((a, b) => a.observedAtUtc.compareTo(b.observedAtUtc));
    final latestWeight = _latest('weight');
    final bmi = _bmi;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = <Widget>[
          _BmiCard(
            bmi: bmi,
            hasHeight: _latest('height') != null,
            onTap: () => _openEntry(
              _latest('height') == null
                  ? HealthEntryType.height
                  : HealthEntryType.weight,
            ),
          ),
          _WeightTrendCard(
            latest: latestWeight,
            values: weights,
            onTap: () => _openEntry(HealthEntryType.weight),
          ),
        ];
        if (constraints.maxWidth < 350) {
          return Column(
            children: [cards[0], const SizedBox(height: 12), cards[1]],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
          ],
        );
      },
    );
  }

  Widget _buildVitals() {
    final pressure = _latest('blood_pressure');
    final heart = _latest('heart_rate');
    final sleep = _latest('sleep_duration');
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'علائم حیاتی',
                en: "Vital signs",
              ),
              en: "Vital signs",
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _VitalCard(
                  icon: Icons.bedtime_rounded,
                  color: Color(0xFF956CE6),
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(fa: 'خواب', en: "sleep"),
                    en: "sleep",
                  ),
                  value: sleep == null
                      ? LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'ثبت نشده',
                            en: "Not recorded",
                          ),
                          en: "not registered",
                        )
                      : _sleepLabel(sleep.valuePrimary),
                  onTap: () => _openEntry(HealthEntryType.sleep),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _VitalCard(
                  icon: Icons.favorite_rounded,
                  color: Color(0xFFF26C7D),
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ضربان قلب',
                      en: "heartbeat",
                    ),
                    en: "heartbeat",
                  ),
                  value: heart == null
                      ? LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'ثبت نشده',
                            en: "Not recorded",
                          ),
                          en: "not registered",
                        )
                      : LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: '${_number(heart.valuePrimary, decimals: 0)} ضربه/دقیقه',
                            en: "${_number(heart.valuePrimary, decimals: 0)} beats/min",
                          ),
                          en: "${_number(heart.valuePrimary, decimals: 0)} beats/min",
                        ),
                  onTap: () => _openEntry(HealthEntryType.heartRate),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _VitalCard(
                  icon: Icons.water_drop_rounded,
                  color: Color(0xFFFF8A4C),
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'فشار خون',
                      en: "blood pressure",
                    ),
                    en: "blood pressure",
                  ),
                  value: pressure == null
                      ? LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'ثبت نشده',
                            en: "Not recorded",
                          ),
                          en: "not registered",
                        )
                      : '${_number(pressure.valuePrimary, decimals: 0)}/${_number(pressure.valueSecondary, decimals: 0)}',
                  onTap: () => _openEntry(HealthEntryType.bloodPressure),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickLog() {
    return _SurfaceCard(
      key: ValueKey('health-quick-log'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'ثبت سریع',
                en: "Quick registration",
              ),
              en: "Quick registration",
            ),
            trailing: Icon(Icons.bolt_rounded, color: AppColors.primary),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickButton(
                  icon: Icons.notes_rounded,
                  color: Color(0xFF8D72D7),
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(fa: 'یادداشت', en: "Note"),
                    en: "Note",
                  ),
                  onTap: () => _openEntry(HealthEntryType.note),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _QuickButton(
                  icon: Icons.bloodtype_rounded,
                  color: Color(0xFFFF9A58),
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'قند خون',
                      en: "blood sugar",
                    ),
                    en: "blood sugar",
                  ),
                  onTap: () => _openEntry(HealthEntryType.bloodGlucose),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _QuickButton(
                  icon: Icons.favorite_rounded,
                  color: Color(0xFF31B99B),
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'فشار خون',
                      en: "blood pressure",
                    ),
                    en: "blood pressure",
                  ),
                  onTap: () => _openEntry(HealthEntryType.bloodPressure),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _QuickButton(
                  icon: Icons.monitor_weight_rounded,
                  color: Color(0xFF48B9C7),
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(fa: 'وزن', en: "weight"),
                    en: "weight",
                  ),
                  onTap: () => _openEntry(HealthEntryType.weight),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final healthEvents = _observations.take(20).map(_TimelineEvent.fromHealth);
    final all = <_TimelineEvent>[...healthEvents, ..._treatmentTimeline]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final visible = all.take(8).toList(growable: false);
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'تایم‌لاین سلامت',
                en: "Timeline of health",
              ),
              en: "Timeline of health",
            ),
            trailing: Icon(Icons.history_rounded, color: AppColors.primary),
          ),
          SizedBox(height: 8),
          if (visible.isEmpty)
            _EmptyHint(
              icon: Icons.timeline_rounded,
              text: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'با ثبت اولین اطلاعات، تایم‌لاین سلامتت از همین‌جا شروع می‌شود.',
                  en: "By registering the first information, your health timeline starts from here.",
                ),
                en: "By registering the first information, your health timeline starts from here.",
              ),
            )
          else
            for (var index = 0; index < visible.length; index++) ...[
              _TimelineRow(event: visible[index]),
              if (index != visible.length - 1)
                const Divider(height: 1, color: Color(0xFFEEF2EF)),
            ],
        ],
      ),
    );
  }

  Widget _buildCalendarHistory() {
    final selected = _forDay(_selectedDate);
    return Column(
      key: ValueKey('health-calendar-history'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: _SectionTitle(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'تاریخچه سلامت',
                en: "Health history",
              ),
              en: "Health history",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'هر روز را انتخاب کن تا ثبت‌های همان روز را ببینی',
                en: "Select any day to see the records of that day",
              ),
              en: "Select any day to see the records of that day",
            ),
          ),
        ),
        SizedBox(height: 12),
        CustomTableCalendar(
          focusedMonth: _focusedMonth,
          selectedDate: _selectedDate,
          isPersian: usesPersianCalendar(context),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDate = selectedDay;
              _focusedMonth = focusedDay;
            });
          },
          onPageChanged: _loadFocusedMonth,
          getDayEventTypes: (day) =>
              _forDay(day).isEmpty ? <String>{} : <String>{'health'},
        ),
        SizedBox(height: 12),
        _SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 19,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formatAppDate(
                        context,
                        _selectedDate,
                        includeWeekday: true,
                      ),
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: '${localizeDigits(context, selected.length)} ثبت',
                        en: "${localizeDigits(context, selected.length)} registration",
                      ),
                      en: "${localizeDigits(context, selected.length)} registration",
                    ),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              if (selected.isEmpty)
                _EmptyHint(
                  icon: Icons.event_note_rounded,
                  text: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'برای این روز اطلاعات سلامتی ثبت نشده.',
                      en: "No health information has been recorded for this day.",
                    ),
                    en: "No health information has been recorded for this day.",
                  ),
                )
              else
                for (var index = 0; index < selected.length; index++) ...[
                  _HistoryRow(
                    observation: selected[index],
                    onDelete: () => _deleteObservation(selected[index]),
                  ),
                  if (index != selected.length - 1)
                    const Divider(height: 1, color: Color(0xFFEEF2EF)),
                ],
            ],
          ),
        ),
      ],
    );
  }

  String _number(double? value, {int decimals = 1}) {
    if (value == null) return '—';
    final rounded = value.toStringAsFixed(decimals);
    final display = decimals > 0
        ? rounded.replaceFirst(RegExp(r'\.0+$'), '')
        : rounded;
    return localizeDigits(context, display);
  }

  String _sleepLabel(double? hours) {
    if (hours == null) return '—';
    final whole = hours.floor();
    final minutes = ((hours - whole) * 60).round();
    if (minutes == 0)
      return LifeMateRuntimeLocale.select(
        fa: '${localizeDigits(context, whole)} ساعت',
        en: "${localizeDigits(context, whole)} hours",
      );
    return LifeMateRuntimeLocale.select(
      fa: '${localizeDigits(context, whole)} ساعت و ${localizeDigits(context, minutes)} دقیقه',
      en: "${localizeDigits(context, whole)} hours and ${localizeDigits(context, minutes)} minutes",
    );
  }

  String _formatClock(DateTime value) =>
      formatAppTime(context, TimeOfDay(hour: value.hour, minute: value.minute));
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0F4F1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C173529),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({this.title, this.subtitle, this.trailing});
  final String? title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (trailing != null) ...[trailing!, const SizedBox(width: 7)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title ?? '',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 64, color: const Color(0xFFEDF1EF));
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: Column(
          children: [
            Icon(icon, color: color, size: 25),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BmiCard extends StatelessWidget {
  const _BmiCard({
    required this.bmi,
    required this.hasHeight,
    required this.onTap,
  });
  final double? bmi;
  final bool hasHeight;
  final VoidCallback onTap;

  String get _label {
    final value = bmi;
    if (value == null)
      return hasHeight
          ? LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'وزن را ثبت کن',
                en: "Record the weight",
              ),
              en: "Record the weight",
            )
          : LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'قد را ثبت کن',
                en: "Record the height",
              ),
              en: "Record the height",
            );
    if (value < 18.5)
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'کمتر از محدوده معمول',
          en: "Less than normal range",
        ),
        en: "Less than normal range",
      );
    if (value < 25)
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'محدوده معمول', en: "Usual range"),
        en: "Usual range",
      );
    return LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'بالاتر از محدوده معمول',
        en: "Above the normal range",
      ),
      en: "Above the normal range",
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: InkWell(
        key: ValueKey('health-bmi-card'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Color(0xFF98A1AA),
                  ),
                  Spacer(),
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'شاخص توده بدنی (BMI)',
                        en: "body mass index (BMI)",
                      ),
                      en: "body mass index (BMI)",
                    ),
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ],
              ),
              SizedBox(height: 8),
              SizedBox(
                height: 130,
                child: CustomPaint(
                  painter: _BmiGaugePainter(bmi),
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 52),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            bmi == null
                                ? '—'
                                : localizeDigits(
                                    context,
                                    bmi!.toStringAsFixed(1),
                                  ),
                            style: TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            _label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                bmi == null
                    ? LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'برای محاسبه، قد و وزن لازم است',
                          en: "Height and weight are required for calculation",
                        ),
                        en: "Height and weight are required for calculation",
                      )
                    : LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'BMI یک شاخص غربالگری است، نه تشخیص پزشکی',
                          en: "BMI is a screening indicator, not a medical diagnosis.",
                        ),
                        en: "BMI is a screening index, not a medical diagnosis",
                      ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BmiGaugePainter extends CustomPainter {
  const _BmiGaugePainter(this.value);
  final double? value;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.74);
    final radius = math.min(size.width * 0.43, size.height * 0.63);
    const stroke = 15.0;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = math.pi;
    const full = math.pi;
    final segments = <(double, double, Color)>[
      (15, 18.5, const Color(0xFF6EA7EB)),
      (18.5, 25, const Color(0xFF50C779)),
      (25, 30, const Color(0xFFF4C85B)),
      (30, 40, const Color(0xFFF38A74)),
    ];
    for (final segment in segments) {
      final a = (segment.$1 - 15) / 25;
      final b = (segment.$2 - 15) / 25;
      canvas.drawArc(
        rect,
        start + full * a,
        full * (b - a),
        false,
        Paint()
          ..color = segment.$3
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt,
      );
    }
    final current = value;
    if (current != null) {
      final normalized = ((current.clamp(15, 40) - 15) / 25).toDouble();
      final angle = start + full * normalized;
      final point = Offset(
        center.dx + math.cos(angle) * (radius - 7),
        center.dy + math.sin(angle) * (radius - 7),
      );
      canvas.drawLine(
        center,
        point,
        Paint()
          ..color = AppColors.textPrimary
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(center, 6, Paint()..color = AppColors.textPrimary);
    }
  }

  @override
  bool shouldRepaint(covariant _BmiGaugePainter oldDelegate) =>
      oldDelegate.value != value;
}

class _WeightTrendCard extends StatelessWidget {
  const _WeightTrendCard({
    required this.latest,
    required this.values,
    required this.onTap,
  });
  final LifeMateHealthObservation? latest;
  final List<LifeMateHealthObservation> values;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latestValue = latest?.valuePrimary;
    double? delta;
    if (values.length >= 2 &&
        values.first.valuePrimary != null &&
        values.last.valuePrimary != null) {
      delta = values.last.valuePrimary! - values.first.valuePrimary!;
    }
    return _SurfaceCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.monitor_weight_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  Spacer(),
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(fa: 'وزن', en: "weight"),
                      en: "weight",
                    ),
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Text(
                latestValue == null
                    ? 'ثبت نشده'
                    : '${localizeDigits(context, latestValue.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), ''))} کیلوگرم',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 12),
              SizedBox(
                height: 78,
                child: values.length < 2
                    ? _MiniEmptyChart()
                    : CustomPaint(
                        painter: _SparklinePainter(
                          values
                              .map((e) => e.valuePrimary ?? 0)
                              .toList(growable: false),
                        ),
                      ),
              ),
              SizedBox(height: 8),
              Text(
                delta == null
                    ? LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'با ثبت‌های بیشتر، روند ۳۰ روزه نمایش داده می‌شود',
                          en: "With more registrations, the 30-day trend is displayed",
                        ),
                        en: "With more registrations, the 30-day trend is displayed",
                      )
                    : '${delta > 0
                          ? '↑'
                          : delta < 0
                          ? '↓'
                          : '•'} ${localizeDigits(context, delta.abs().toStringAsFixed(1))} کیلو در ۳۰ روز',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: delta == null
                      ? AppColors.textSecondary
                      : AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final spread = math.max(0.5, maxValue - minValue);
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final y =
          size.height * 0.82 -
          ((values[index] - minValue) / spread) * size.height * 0.62;
      points.add(Offset(x, y));
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
    for (final point in points) {
      canvas.drawCircle(point, 3.2, Paint()..color = Colors.white);
      canvas.drawCircle(
        point,
        3.2,
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values;
}

class _MiniEmptyChart extends StatelessWidget {
  const _MiniEmptyChart();
  @override
  Widget build(BuildContext context) => Center(
    child: Icon(
      Icons.show_chart_rounded,
      color: Colors.grey.shade300,
      size: 48,
    ),
  );
}

class _VitalCard extends StatelessWidget {
  const _VitalCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        constraints: const BoxConstraints(minHeight: 132),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEEF2EF)),
          boxShadow: [
            BoxShadow(
              color: Color(0x091A382C),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
            ),
            SizedBox(height: 5),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
            SizedBox(height: 9),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'آخرین ثبت',
                    en: "last registration",
                  ),
                  en: "last registration",
                ),
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'ثبت $label',
          en: "Register $label",
        ),
        en: "Register $label",
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: BoxConstraints(minHeight: 78),
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Color(0xFFEEF2EF)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineEvent {
  const _TimelineEvent({
    required this.occurredAt,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  factory _TimelineEvent.fromHealth(LifeMateHealthObservation value) {
    final presentation = _observationPresentation(value);
    return _TimelineEvent(
      occurredAt: value.observedAtUtc.toLocal(),
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: '${presentation.label} ثبت شد',
          en: "${presentation.label} registered",
        ),
        en: "${presentation.label} registered",
      ),
      subtitle: presentation.value,
      icon: presentation.icon,
      color: presentation.color,
    );
  }

  final DateTime occurredAt;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event});
  final _TimelineEvent event;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: event.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(event.icon, color: event.color, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (event.subtitle.isNotEmpty)
                  Text(
                    event.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatAppTime(
                  context,
                  TimeOfDay(
                    hour: event.occurredAt.hour,
                    minute: event.occurredAt.minute,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                formatAppDate(context, event.occurredAt),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ObservationPresentation {
  const _ObservationPresentation({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

_ObservationPresentation _observationPresentation(
  LifeMateHealthObservation value, {
  BuildContext? context,
}) {
  String number(double? input, {int decimals = 1}) {
    if (input == null) return '—';
    final raw = input
        .toStringAsFixed(decimals)
        .replaceFirst(RegExp(r'\.0$'), '');
    return context == null ? raw : localizeDigits(context, raw);
  }

  return switch (value.observationType) {
    'weight' => _ObservationPresentation(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'وزن', en: "weight"),
        en: "weight",
      ),
      value: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: '${number(value.valuePrimary)} کیلوگرم',
          en: "${number(value.valuePrimary)} kg",
        ),
        en: "${number(value.valuePrimary)} kg",
      ),
      icon: Icons.monitor_weight_rounded,
      color: Color(0xFF48B9C7),
    ),
    'height' => _ObservationPresentation(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'قد', en: "height"),
        en: "height",
      ),
      value: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: '${number(value.valuePrimary, decimals: 0)} سانتی‌متر',
          en: "${number(value.valuePrimary, decimals: 0)} cm",
        ),
        en: "${number(value.valuePrimary, decimals: 0)} cm",
      ),
      icon: Icons.height_rounded,
      color: Color(0xFF6EA7EB),
    ),
    'blood_pressure' => _ObservationPresentation(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'فشار خون', en: "blood pressure"),
        en: "blood pressure",
      ),
      value:
          '${number(value.valuePrimary, decimals: 0)}/${number(value.valueSecondary, decimals: 0)} mmHg',
      icon: Icons.water_drop_rounded,
      color: Color(0xFFFF8A4C),
    ),
    'heart_rate' => _ObservationPresentation(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'ضربان قلب', en: "heartbeat"),
        en: "heartbeat",
      ),
      value: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: '${number(value.valuePrimary, decimals: 0)} ضربه/دقیقه',
          en: "${number(value.valuePrimary, decimals: 0)} beats/min",
        ),
        en: "${number(value.valuePrimary, decimals: 0)} beats/min",
      ),
      icon: Icons.favorite_rounded,
      color: Color(0xFFF26C7D),
    ),
    'blood_glucose' => _ObservationPresentation(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'قند خون', en: "blood sugar"),
        en: "blood sugar",
      ),
      value: '${number(value.valuePrimary, decimals: 0)} mg/dL',
      icon: Icons.bloodtype_rounded,
      color: Color(0xFFFF9A58),
    ),
    'sleep_duration' => _ObservationPresentation(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'خواب', en: "sleep"),
        en: "sleep",
      ),
      value: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: '${number(value.valuePrimary)} ساعت',
          en: "${number(value.valuePrimary)} hours",
        ),
        en: "${number(value.valuePrimary)} hours",
      ),
      icon: Icons.bedtime_rounded,
      color: Color(0xFF956CE6),
    ),
    'oxygen_saturation' => _ObservationPresentation(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'اکسیژن خون', en: "blood oxygen"),
        en: "blood oxygen",
      ),
      value: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: '${number(value.valuePrimary, decimals: 0)}٪',
          en: "${number(value.valuePrimary, decimals: 0)}%",
        ),
        en: "${number(value.valuePrimary, decimals: 0)}%",
      ),
      icon: Icons.air_rounded,
      color: Color(0xFF4A9FE0),
    ),
    'body_temperature' => _ObservationPresentation(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'دمای بدن',
          en: "body temperature",
        ),
        en: "body temperature",
      ),
      value: '${number(value.valuePrimary)} °C',
      icon: Icons.thermostat_rounded,
      color: Color(0xFFF07D68),
    ),
    _ => _ObservationPresentation(
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'یادداشت سلامت',
          en: "health note",
        ),
        en: "health note",
      ),
      value: value.note ?? '',
      icon: Icons.notes_rounded,
      color: Color(0xFF8D72D7),
    ),
  };
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.observation, required this.onDelete});
  final LifeMateHealthObservation observation;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final presentation = _observationPresentation(
      observation,
      context: context,
    );
    final time = observation.observedAtUtc.toLocal();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: presentation.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(presentation.icon, color: presentation.color, size: 22),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  presentation.label,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  presentation.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatAppTime(
              context,
              TimeOfDay(hour: time.hour, minute: time.minute),
            ),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          PopupMenuButton<String>(
            tooltip: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'گزینه‌های ثبت',
                en: "Registration options",
              ),
              en: "Registration options",
            ),
            onSelected: (value) {
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'حذف ثبت',
                      en: "Delete registration",
                    ),
                    en: "Delete registration",
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF8),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary.withValues(alpha: 0.7)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function({bool background}) onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color(0xFFFFF4F2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: Color(0xFFB5473E)),
          SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => onRetry(),
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
}

class _ConnectedHealthComingSoon extends StatelessWidget {
  const _ConnectedHealthComingSoon();

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      key: ValueKey('health-gadgets-coming-soon'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'گجت‌ها و اپ‌های سلامت',
                en: "Health gadgets and apps",
              ),
              en: "Health gadgets and apps",
            ),
            subtitle: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'همگام‌سازی خودکار داده‌ها در نسخه‌های بعدی',
                en: "Automatic data synchronization in later versions",
              ),
              en: "Automatic data synchronization in later versions",
            ),
          ),
          SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 126,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 2.1, sigmaY: 2.1),
                    child: Container(
                      color: Color(0xFFF1F8F5),
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _GadgetPreview(
                            icon: Icons.watch_rounded,
                            label: LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'ساعت هوشمند',
                                en: "smart watch",
                              ),
                              en: "smart watch",
                            ),
                          ),
                          _GadgetPreview(
                            icon: Icons.favorite_outline_rounded,
                            label: 'Health Connect',
                          ),
                          _GadgetPreview(
                            icon: Icons.phone_iphone_rounded,
                            label: LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'اپ‌های سلامت',
                                en: "Health apps",
                              ),
                              en: "Health apps",
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(color: Colors.white.withValues(alpha: 0.43)),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_clock_rounded,
                          color: AppColors.primary,
                          size: 29,
                        ),
                        SizedBox(height: 5),
                        Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'به‌زودی',
                              en: "Coming soon",
                            ),
                            en: "soon",
                          ),
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'اتصال به گجت‌ها فعلاً غیرفعال است',
                              en: "Connecting to gadgets is currently disabled",
                            ),
                            en: "Connecting to gadgets is currently disabled",
                          ),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GadgetPreview extends StatelessWidget {
  const _GadgetPreview({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
