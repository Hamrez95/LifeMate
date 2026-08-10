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
        _loadError = 'اطلاعات سلامت دریافت نشد. اتصال را بررسی کن.';
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
                ? 'داروی $medicationName مصرف شد'
                : 'مصرف دارو ثبت شد',
            subtitle: plan?['doseText']?.toString() ?? '',
            icon: Icons.medication_rounded,
            color: const Color(0xFF31B99B),
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
            title:
                '${event['title'] ?? (type == 'injection' ? 'تزریق' : 'ویزیت')} انجام شد',
            subtitle: type == 'injection' ? 'تزریق' : 'رویداد مراقبتی',
            icon: type == 'injection'
                ? Icons.vaccines_rounded
                : Icons.event_available_rounded,
            color: type == 'injection'
                ? const Color(0xFFF2A43A)
                : const Color(0xFF5A9EE7),
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
              const SnackBar(content: Text('اطلاعات سلامت ذخیره شد.')),
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
        title: const Text('حذف این ثبت؟'),
        content: const Text('این مورد از تاریخچه سلامت حذف می‌شود.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
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
          const SnackBar(content: Text('حذف انجام نشد. دوباره تلاش کن.')),
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
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: const Icon(
            Icons.monitor_heart_outlined,
            color: AppColors.primary,
            size: 29,
          ),
        ),
        const SizedBox(width: 13),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سلامت من',
                key: ValueKey('health-title'),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'خلاصه وضعیت بدن و علائم حیاتی',
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
              const Icon(
                Icons.event_available_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'خلاصه امروز',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            latest == null
                ? 'هنوز اطلاعاتی ثبت نشده'
                : 'آخرین ثبت: ${formatAppDate(context, latest.observedLocalDate)} • ${_formatClock(latest.observedAtUtc.toLocal())}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.bedtime_rounded,
                  color: const Color(0xFF956CE6),
                  label: 'خواب',
                  value: sleep == null ? '—' : _sleepLabel(sleep.valuePrimary),
                  onTap: () => _openEntry(HealthEntryType.sleep),
                ),
              ),
              _SummaryDivider(),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.favorite_rounded,
                  color: const Color(0xFFF26C7D),
                  label: 'ضربان قلب',
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
                  color: const Color(0xFFFF8A4C),
                  label: 'فشار خون',
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
                  color: const Color(0xFF48B9C7),
                  label: 'وزن',
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
          const _SectionTitle(title: 'علائم حیاتی'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _VitalCard(
                  icon: Icons.bedtime_rounded,
                  color: const Color(0xFF956CE6),
                  label: 'خواب',
                  value: sleep == null
                      ? 'ثبت نشده'
                      : _sleepLabel(sleep.valuePrimary),
                  onTap: () => _openEntry(HealthEntryType.sleep),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _VitalCard(
                  icon: Icons.favorite_rounded,
                  color: const Color(0xFFF26C7D),
                  label: 'ضربان قلب',
                  value: heart == null
                      ? 'ثبت نشده'
                      : '${_number(heart.valuePrimary, decimals: 0)} ضربه/دقیقه',
                  onTap: () => _openEntry(HealthEntryType.heartRate),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _VitalCard(
                  icon: Icons.water_drop_rounded,
                  color: const Color(0xFFFF8A4C),
                  label: 'فشار خون',
                  value: pressure == null
                      ? 'ثبت نشده'
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
      key: const ValueKey('health-quick-log'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            title: 'ثبت سریع',
            trailing: Icon(Icons.bolt_rounded, color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickButton(
                  icon: Icons.notes_rounded,
                  color: const Color(0xFF8D72D7),
                  label: 'یادداشت',
                  onTap: () => _openEntry(HealthEntryType.note),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickButton(
                  icon: Icons.bloodtype_rounded,
                  color: const Color(0xFFFF9A58),
                  label: 'قند خون',
                  onTap: () => _openEntry(HealthEntryType.bloodGlucose),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickButton(
                  icon: Icons.favorite_rounded,
                  color: const Color(0xFF31B99B),
                  label: 'فشار خون',
                  onTap: () => _openEntry(HealthEntryType.bloodPressure),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickButton(
                  icon: Icons.monitor_weight_rounded,
                  color: const Color(0xFF48B9C7),
                  label: 'وزن',
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
          const _SectionTitle(
            title: 'تایم‌لاین سلامت',
            trailing: Icon(Icons.history_rounded, color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            const _EmptyHint(
              icon: Icons.timeline_rounded,
              text:
                  'با ثبت اولین اطلاعات، تایم‌لاین سلامتت از همین‌جا شروع می‌شود.',
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
      key: const ValueKey('health-calendar-history'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: _SectionTitle(
            title: 'تاریخچه سلامت',
            subtitle: 'هر روز را انتخاب کن تا ثبت‌های همان روز را ببینی',
          ),
        ),
        const SizedBox(height: 12),
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
          getDayEventTypes: (day) => _forDay(day).isEmpty
              ? const <String>{}
              : const <String>{'health'},
        ),
        const SizedBox(height: 12),
        _SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 19,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formatAppDate(
                        context,
                        _selectedDate,
                        includeWeekday: true,
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    '${localizeDigits(context, selected.length)} ثبت',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (selected.isEmpty)
                const _EmptyHint(
                  icon: Icons.event_note_rounded,
                  text: 'برای این روز اطلاعات سلامتی ثبت نشده.',
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
    if (minutes == 0) return '${localizeDigits(context, whole)} ساعت';
    return '${localizeDigits(context, whole)} ساعت و ${localizeDigits(context, minutes)} دقیقه';
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
    if (value == null) return hasHeight ? 'وزن را ثبت کن' : 'قد را ثبت کن';
    if (value < 18.5) return 'کمتر از محدوده معمول';
    if (value < 25) return 'محدوده معمول';
    return 'بالاتر از محدوده معمول';
  }

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: InkWell(
        key: const ValueKey('health-bmi-card'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Color(0xFF98A1AA),
                  ),
                  Spacer(),
                  Text(
                    'شاخص توده بدنی (BMI)',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 130,
                child: CustomPaint(
                  painter: _BmiGaugePainter(bmi),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 52),
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
                            style: const TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            _label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
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
                    ? 'برای محاسبه، قد و وزن لازم است'
                    : 'BMI یک شاخص غربالگری است، نه تشخیص پزشکی',
                textAlign: TextAlign.center,
                style: const TextStyle(
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
          padding: const EdgeInsets.all(2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.monitor_weight_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  Spacer(),
                  Text(
                    'وزن',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                latestValue == null
                    ? 'ثبت نشده'
                    : '${localizeDigits(context, latestValue.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), ''))} کیلوگرم',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 78,
                child: values.length < 2
                    ? const _MiniEmptyChart()
                    : CustomPaint(
                        painter: _SparklinePainter(
                          values
                              .map((e) => e.valuePrimary ?? 0)
                              .toList(growable: false),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                delta == null
                    ? 'با ثبت‌های بیشتر، روند ۳۰ روزه نمایش داده می‌شود'
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
          boxShadow: const [
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
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'آخرین ثبت',
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
      label: 'ثبت $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEEF2EF)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
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
      title: '${presentation.label} ثبت شد',
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
      label: 'وزن',
      value: '${number(value.valuePrimary)} کیلوگرم',
      icon: Icons.monitor_weight_rounded,
      color: const Color(0xFF48B9C7),
    ),
    'height' => _ObservationPresentation(
      label: 'قد',
      value: '${number(value.valuePrimary, decimals: 0)} سانتی‌متر',
      icon: Icons.height_rounded,
      color: const Color(0xFF6EA7EB),
    ),
    'blood_pressure' => _ObservationPresentation(
      label: 'فشار خون',
      value:
          '${number(value.valuePrimary, decimals: 0)}/${number(value.valueSecondary, decimals: 0)} mmHg',
      icon: Icons.water_drop_rounded,
      color: const Color(0xFFFF8A4C),
    ),
    'heart_rate' => _ObservationPresentation(
      label: 'ضربان قلب',
      value: '${number(value.valuePrimary, decimals: 0)} ضربه/دقیقه',
      icon: Icons.favorite_rounded,
      color: const Color(0xFFF26C7D),
    ),
    'blood_glucose' => _ObservationPresentation(
      label: 'قند خون',
      value: '${number(value.valuePrimary, decimals: 0)} mg/dL',
      icon: Icons.bloodtype_rounded,
      color: const Color(0xFFFF9A58),
    ),
    'sleep_duration' => _ObservationPresentation(
      label: 'خواب',
      value: '${number(value.valuePrimary)} ساعت',
      icon: Icons.bedtime_rounded,
      color: const Color(0xFF956CE6),
    ),
    'oxygen_saturation' => _ObservationPresentation(
      label: 'اکسیژن خون',
      value: '${number(value.valuePrimary, decimals: 0)}٪',
      icon: Icons.air_rounded,
      color: const Color(0xFF4A9FE0),
    ),
    'body_temperature' => _ObservationPresentation(
      label: 'دمای بدن',
      value: '${number(value.valuePrimary)} °C',
      icon: Icons.thermostat_rounded,
      color: const Color(0xFFF07D68),
    ),
    _ => _ObservationPresentation(
      label: 'یادداشت سلامت',
      value: value.note ?? '',
      icon: Icons.notes_rounded,
      color: const Color(0xFF8D72D7),
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  presentation.label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  presentation.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
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
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          PopupMenuButton<String>(
            tooltip: 'گزینه‌های ثبت',
            onSelected: (value) {
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('حذف ثبت')),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFB5473E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () => onRetry(),
            child: const Text('تلاش دوباره'),
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
      key: const ValueKey('health-gadgets-coming-soon'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            title: 'گجت‌ها و اپ‌های سلامت',
            subtitle: 'همگام‌سازی خودکار داده‌ها در نسخه‌های بعدی',
          ),
          const SizedBox(height: 12),
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
                      color: const Color(0xFFF1F8F5),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _GadgetPreview(
                            icon: Icons.watch_rounded,
                            label: 'ساعت هوشمند',
                          ),
                          _GadgetPreview(
                            icon: Icons.favorite_outline_rounded,
                            label: 'Health Connect',
                          ),
                          _GadgetPreview(
                            icon: Icons.phone_iphone_rounded,
                            label: 'اپ‌های سلامت',
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(color: Colors.white.withValues(alpha: 0.43)),
                  const Center(
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
                          'به‌زودی',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'اتصال به گجت‌ها فعلاً غیرفعال است',
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
