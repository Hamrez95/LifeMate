import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';

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
              final schedules =
                  plan['schedules'] as List<dynamic>? ?? const [];
              final firstTime = schedules.isEmpty
                  ? 'بدون زمان'
                  : (schedules.first as Map<String, dynamic>)['localTime']
                          ?.toString()
                          .substring(0, 5) ??
                      'بدون زمان';
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                color: Colors.white,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor:
                        AppColors.primary.withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.medication_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(
                    medication['name']?.toString() ?? 'دارو',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${plan['doseText'] ?? ''} • هر روز ساعت $firstTime',
                    ),
                  ),
                  trailing: Chip(
                    label: Text(
                      plan['status'] == 'active' ? 'فعال' : 'متوقف',
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
          for (final day in week)
            {'dayOfWeek': day, 'localTime': localTime},
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
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
