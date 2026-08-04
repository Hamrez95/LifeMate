import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';

class TreatmentsScreen extends StatefulWidget {
  const TreatmentsScreen({super.key, required this.refreshToken});

  final int refreshToken;

  @override
  State<TreatmentsScreen> createState() => _TreatmentsScreenState();
}

class _TreatmentsScreenState extends State<TreatmentsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _plans = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TreatmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final plans = await context.read<LifeMateApiClient>().getTreatmentPlans();
      if (mounted) setState(() => _plans = plans);
    } catch (error) {
      debugPrint('WellMate treatment list failed: $error');
      if (mounted) setState(() => _error = 'برنامه‌های درمانی دریافت نشدند.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
        children: [
          const Text(
            'درمان‌های من',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text('برنامه‌های فعال مستقیماً از حساب شما دریافت می‌شوند.'),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _MessageCard(
              icon: Icons.cloud_off_rounded,
              message: _error!,
              actionLabel: 'تلاش دوباره',
              onAction: _load,
            )
          else if (_plans.isEmpty)
            const _MessageCard(
              icon: Icons.medication_liquid_rounded,
              message:
                  'هنوز درمانی ثبت نشده است. از تب «افزودن درمان» اولین برنامه را بسازید.',
            )
          else
            ..._plans.map((plan) {
              final medication =
                  plan['medication'] as Map<String, dynamic>? ?? const {};
              final schedules = plan['schedules'] as List<dynamic>? ?? const [];
              final rawTime = schedules.isEmpty
                  ? ''
                  : (schedules.first as Map<String, dynamic>)['localTime']
                            ?.toString() ??
                        '';
              final firstTime = localizeDigits(
                context,
                rawTime.length >= 5 ? rawTime.substring(0, 5) : 'بدون زمان',
              );
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                color: Colors.white,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.medication_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(
                    localizeDigits(
                      context,
                      medication['name']?.toString() ?? 'دارو',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      localizeDigits(
                        context,
                        '${plan['doseText'] ?? ''} • هر روز ساعت $firstTime',
                      ),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          plan['status'] == 'active' ? 'فعال' : 'متوقف',
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _TreatmentDetailsScreen(plan: plan),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class AddTreatmentScreen extends StatefulWidget {
  const AddTreatmentScreen({super.key, required this.onCreated});

  final VoidCallback onCreated;

  @override
  State<AddTreatmentScreen> createState() => _AddTreatmentScreenState();
}

class _AddTreatmentScreenState extends State<AddTreatmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _strength = TextEditingController();
  final _dose = TextEditingController();
  final _instructions = TextEditingController();
  TimeOfDay _time = TimeOfDay.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _strength.dispose();
    _dose.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null && mounted) setState(() => _time = value);
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.read<LifeMateApiClient>();
      final medication = await api.createMedication(
        name: _name.text,
        strengthText: _strength.text,
        form: 'tablet',
      );
      final localTime =
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
      const week = [
        'sunday',
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
      ];
      await api.createTreatmentPlan(
        medicationId: medication['id'].toString(),
        doseText: _dose.text,
        instructions: _instructions.text,
        startDate: DateTime.now(),
        timeZone: 'Asia/Tehran',
        schedules: [
          for (final day in week) {'dayOfWeek': day, 'localTime': localTime},
        ],
      );
      if (!mounted) return;
      _name.clear();
      _strength.clear();
      _dose.clear();
      _instructions.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('درمان ثبت شد و برنامه امروز به‌روزرسانی می‌شود.'),
        ),
      );
      widget.onCreated();
    } on LifeMateApiException catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error));
      }
    } catch (error) {
      debugPrint('WellMate treatment creation failed: $error');
      if (mounted) {
        setState(() => _error = 'ثبت درمان انجام نشد. اتصال را بررسی کنید.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeLabel =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'افزودن درمان روزانه',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'نسخه MVP یک برنامه روزانه می‌سازد؛ بعداً می‌توانید الگوهای پیچیده‌تر اضافه کنید.',
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'نام دارو',
                prefixIcon: Icon(Icons.medication_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value?.trim().isNotEmpty ?? false)
                  ? null
                  : 'نام دارو را وارد کنید.',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _strength,
              decoration: const InputDecoration(
                labelText: 'قدرت دارو (اختیاری)',
                hintText: 'مثلاً ۵۰ میلی‌گرم',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _dose,
              decoration: const InputDecoration(
                labelText: 'مقدار مصرف',
                hintText: 'مثلاً یک قرص',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value?.trim().isNotEmpty ?? false)
                  ? null
                  : 'مقدار مصرف را وارد کنید.',
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _busy ? null : _pickTime,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'زمان مصرف روزانه',
                  prefixIcon: Icon(Icons.schedule_rounded),
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  timeLabel,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 17),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _instructions,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'توضیحات (اختیاری)',
                hintText: 'مثلاً بعد از غذا',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_task_rounded),
                label: const Text('ثبت درمان'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _friendlyError(LifeMateApiException error) {
    switch (error.code) {
      case 'invalid_medication':
      case 'invalid_name':
        return 'مشخصات دارو معتبر نیست.';
      case 'invalid_treatment_plan':
      case 'schedule_required':
        return 'برنامه درمان معتبر نیست.';
      default:
        return error.isUnauthorized
            ? 'نشست شما منقضی شده است؛ دوباره وارد شوید.'
            : 'ثبت درمان انجام نشد. دوباره تلاش کنید.';
    }
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(icon, size: 48, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _TreatmentDetailsScreen extends StatelessWidget {
  const _TreatmentDetailsScreen({required this.plan});

  final Map<String, dynamic> plan;

  @override
  Widget build(BuildContext context) {
    final medication = plan['medication'] as Map<String, dynamic>? ?? const {};
    final schedules = plan['schedules'] as List<dynamic>? ?? const [];
    final status = plan['status']?.toString() ?? 'unknown';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'بازگشت',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'جزئیات درمان',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: AppColors.darkBlue,
                      ),
                    ),
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.medication_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowDark.withValues(alpha: 0.55),
                          blurRadius: 18,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _localizedText(
                                  context,
                                  medication['name'],
                                  fallback: 'دارو',
                                ),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.darkBlue,
                                ),
                              ),
                            ),
                            Chip(
                              label: Text(
                                status == 'active' ? 'فعال' : 'متوقف',
                              ),
                              side: BorderSide.none,
                              backgroundColor: status == 'active'
                                  ? AppColors.primary.withValues(alpha: 0.12)
                                  : Colors.grey.shade100,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _TreatmentInfoRow(
                          icon: Icons.science_outlined,
                          label: 'قدرت دارو',
                          value: _localizedText(
                            context,
                            medication['strengthText'],
                          ),
                        ),
                        _TreatmentInfoRow(
                          icon: Icons.medication_liquid_rounded,
                          label: 'مقدار مصرف',
                          value: _localizedText(context, plan['doseText']),
                        ),
                        _TreatmentInfoRow(
                          icon: Icons.notes_rounded,
                          label: 'دستور مصرف',
                          value: _localizedText(context, plan['instructions']),
                        ),
                        _TreatmentInfoRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'تاریخ شروع',
                          value: _localizedDate(context, plan['startDate']),
                        ),
                        _TreatmentInfoRow(
                          icon: Icons.event_busy_outlined,
                          label: 'تاریخ پایان',
                          value: _localizedDate(
                            context,
                            plan['endDate'],
                            fallback: 'بدون پایان',
                          ),
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'زمان‌های مصرف',
                    style: AppTextStyles.heading(
                      context,
                    ).copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  if (schedules.isEmpty)
                    const _MessageCard(
                      icon: Icons.schedule_rounded,
                      message: 'زمانی برای این درمان ثبت نشده است.',
                    )
                  else
                    ...schedules.map((schedule) {
                      final value = schedule as Map<String, dynamic>;
                      final rawTime = value['localTime']?.toString() ?? '';
                      final time = rawTime.length >= 5
                          ? rawTime.substring(0, 5)
                          : _text(rawTime);
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const Icon(
                            Icons.schedule_rounded,
                            color: AppColors.primary,
                          ),
                          title: Text(
                            localizeDigits(context, time),
                            textDirection: TextDirection.ltr,
                          ),
                          subtitle: Text(
                            _weekdayLabel(value['dayOfWeek']?.toString()),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.amber.shade100),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.construction_rounded, color: Colors.amber),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'نمایش جزئیات از Backend واقعی انجام می‌شود. API ویرایش یا توقف درمان هنوز در این نسخه ارائه نشده است.',
                            style: TextStyle(height: 1.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: null,
                      icon: Icon(Icons.edit_outlined),
                      label: Text('ویرایش درمان — در دست توسعه'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TreatmentInfoRow extends StatelessWidget {
  const _TreatmentInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 21, color: AppColors.primaryBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }
}

String _text(dynamic value, {String fallback = 'ثبت نشده'}) {
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

String _weekdayLabel(String? value) => switch (value) {
  'saturday' => 'شنبه',
  'sunday' => 'یکشنبه',
  'monday' => 'دوشنبه',
  'tuesday' => 'سه‌شنبه',
  'wednesday' => 'چهارشنبه',
  'thursday' => 'پنجشنبه',
  'friday' => 'جمعه',
  _ => value ?? 'روز ثبت نشده',
};
