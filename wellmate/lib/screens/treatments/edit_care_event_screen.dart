import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../core/widgets/labeled_form_field.dart';

class EditCareEventScreen extends StatefulWidget {
  const EditCareEventScreen({super.key, required this.eventId, this.editApi});

  final String eventId;
  final LifeMateEditApi? editApi;

  @override
  State<EditCareEventScreen> createState() => _EditCareEventScreenState();
}

class _EditCareEventScreenState extends State<EditCareEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _provider = TextEditingController();
  final _specialty = TextEditingController();
  final _dose = TextEditingController();
  final _reason = TextEditingController();
  final _center = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _instructions = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _eventType = 'appointment';
  String _status = 'scheduled';
  String _administrationRoute = 'intramuscular';
  String _timeZone = 'Asia/Tehran';
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  int _patientReminderMinutesBefore =
      LifeMateReminderLeadTimes.defaultPatientMinutes;
  int _caregiverReminderMinutesBefore =
      LifeMateReminderLeadTimes.defaultCaregiverMinutes;
  int _version = 1;
  bool _wasMissed = false;

  LifeMateEditApi get _api =>
      widget.editApi ?? LifeMateEditApi.fromEnvironment();

  bool get _isAppointment => _eventType == 'appointment';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _provider.dispose();
    _specialty.dispose();
    _dose.dispose();
    _reason.dispose();
    _center.dispose();
    _address.dispose();
    _phone.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final event = await _api.getCareEvent(eventId: widget.eventId);
      if (!mounted) return;
      _hydrate(event);
      setState(() => _loading = false);
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    } catch (error) {
      debugPrint('WellMate care event edit load failed: $error');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'اطلاعات ویزیت یا تزریق دریافت نشد.';
        });
      }
    }
  }

  void _hydrate(Map<String, dynamic> event) {
    _eventType = event['eventType']?.toString().toLowerCase() == 'injection'
        ? 'injection'
        : 'appointment';
    final rawStatus = event['status']?.toString().toLowerCase() ?? 'scheduled';
    _wasMissed = rawStatus == 'missed';
    _status = switch (rawStatus) {
      'completed' => 'completed',
      'cancelled' || 'canceled' => 'cancelled',
      _ => 'scheduled',
    };
    _title.text = event['title']?.toString() ?? '';
    _provider.text = event['providerName']?.toString() ?? '';
    _specialty.text = event['specialty']?.toString() ?? '';
    _dose.text = event['doseText']?.toString() ?? '';
    _reason.text = event['reason']?.toString() ?? '';
    _center.text = event['centerName']?.toString() ?? '';
    _address.text = event['addressLine']?.toString() ?? '';
    _phone.text = event['phoneNumber']?.toString() ?? '';
    _instructions.text = event['instructions']?.toString() ?? '';
    _administrationRoute =
        event['administrationRoute']?.toString().trim().isNotEmpty == true
        ? event['administrationRoute'].toString()
        : 'intramuscular';
    _timeZone = event['timeZone']?.toString().trim().isNotEmpty == true
        ? event['timeZone'].toString()
        : 'Asia/Tehran';
    _date =
        DateTime.tryParse(event['scheduledLocalDate']?.toString() ?? '') ??
        DateTime.now();
    final parts =
        event['scheduledLocalTime']?.toString().split(':') ?? const [];
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (hour != null && minute != null) {
      _time = TimeOfDay(hour: hour, minute: minute);
    }
    _patientReminderMinutesBefore = LifeMateReminderLeadTimes.normalize(
      event['patientReminderMinutesBefore'],
      fallback: LifeMateReminderLeadTimes.defaultPatientMinutes,
    );
    _caregiverReminderMinutesBefore = LifeMateReminderLeadTimes.normalize(
      event['caregiverReminderMinutesBefore'],
      fallback: LifeMateReminderLeadTimes.defaultCaregiverMinutes,
    );
    _version = int.tryParse(event['version']?.toString() ?? '') ?? 1;
  }

  Future<void> _pickDate() async {
    final value = await showAppDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      title: _isAppointment ? 'تاریخ ویزیت' : 'تاریخ تزریق',
    );
    if (value != null && mounted) setState(() => _date = value);
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null && mounted) setState(() => _time = value);
  }

  String get _timeValue =>
      '${_time.hour.toString().padLeft(2, '0')}:'
      '${_time.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.updateCareEvent(
        eventId: widget.eventId,
        version: _version,
        eventType: _eventType,
        title: _title.text,
        providerName: _provider.text,
        specialty: _isAppointment ? _specialty.text : null,
        medicationName: _isAppointment ? null : _title.text,
        doseText: _isAppointment ? null : _dose.text,
        administrationRoute: _isAppointment ? null : _administrationRoute,
        reason: _reason.text,
        instructions: _instructions.text,
        centerName: _center.text,
        addressLine: _address.text,
        phoneNumber: _phone.text,
        scheduledLocalDate: _date,
        scheduledLocalTime: _timeValue,
        timeZone: _timeZone,
        patientReminderMinutesBefore: _patientReminderMinutesBefore,
        caregiverReminderMinutesBefore: _caregiverReminderMinutesBefore,
        status: _status,
      );
      _version =
          int.tryParse(result['version']?.toString() ?? '') ?? _version + 1;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _isAppointment
                ? 'تغییرات ویزیت ذخیره شد.'
                : 'تغییرات تزریق ذخیره شد.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on LifeMateApiException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } catch (error) {
      debugPrint('WellMate care event update failed: $error');
      if (mounted) {
        setState(
          () => _error = 'ذخیره تغییرات انجام نشد. اتصال را بررسی کنید.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(LifeMateApiException error) {
    return switch (error.code) {
      'stale_care_event' =>
        'این برنامه در جای دیگری تغییر کرده است. صفحه را ببندید و دوباره باز کنید.',
      'care_event_not_found' => 'این ویزیت یا تزریق دیگر وجود ندارد.',
      'invalid_medicationName' => 'نام داروی تزریقی را وارد کنید.',
      'network_unavailable' =>
        'اتصال اینترنت برای ذخیره تغییرات در دسترس نیست.',
      'session_missing' ||
      'invalid_session' => 'نشست شما منقضی شده است. دوباره وارد شوید.',
      _ => 'اطلاعات واردشده معتبر نیست یا ذخیره انجام نشد.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final screenTitle = _isAppointment ? 'ویرایش ویزیت' : 'ویرایش تزریق';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          screenTitle,
          style: const TextStyle(
            color: AppColors.darkBlue,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _title.text.isEmpty
            ? _LoadError(message: _error!, onRetry: _load)
            : Form(
                key: _formKey,
                child: ListView(
                  key: const ValueKey('edit-care-event-form'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                  children: [
                    if (_wasMissed)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.orange.shade100),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: Colors.orange,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'زمان این برنامه گذشته است. می‌توانید تاریخ و ساعت جدید تعیین کنید یا وضعیت آن را تغییر دهید.',
                                style: TextStyle(height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    _Section(
                      title: _isAppointment ? 'مشخصات ویزیت' : 'مشخصات تزریق',
                      icon: _isAppointment
                          ? Icons.medical_services_rounded
                          : Icons.vaccines_rounded,
                      children: [
                        _textField(
                          controller: _title,
                          label: _isAppointment
                              ? 'عنوان ویزیت'
                              : 'نام داروی تزریقی',
                          hint: _isAppointment
                              ? 'مثلاً ویزیت متخصص قلب'
                              : 'مثلاً ویتامین B12',
                          icon: Icons.event_note_rounded,
                          required: true,
                        ),
                        if (_isAppointment) ...[
                          _textField(
                            controller: _provider,
                            label: 'نام پزشک',
                            hint: 'نام پزشک',
                            icon: Icons.person_rounded,
                            required: true,
                          ),
                          _textField(
                            controller: _specialty,
                            label: 'تخصص',
                            hint: 'مثلاً متخصص قلب و عروق',
                            icon: Icons.workspace_premium_rounded,
                          ),
                        ] else ...[
                          _textField(
                            controller: _dose,
                            label: 'دوز یا مقدار تزریق',
                            hint: 'مثلاً ۱ آمپول',
                            icon: Icons.straighten_rounded,
                            required: true,
                          ),
                          WellMateLabeledField(
                            label: 'روش تزریق',
                            icon: Icons.route_rounded,
                            child: DropdownButtonFormField<String>(
                              initialValue: _administrationRoute,
                              isExpanded: true,
                              decoration: wellMateFieldDecoration(),
                              items: const [
                                DropdownMenuItem(
                                  value: 'intramuscular',
                                  child: Text('عضلانی'),
                                ),
                                DropdownMenuItem(
                                  value: 'subcutaneous',
                                  child: Text('زیرجلدی'),
                                ),
                                DropdownMenuItem(
                                  value: 'intravenous',
                                  child: Text('وریدی'),
                                ),
                                DropdownMenuItem(
                                  value: 'other',
                                  child: Text('سایر / طبق دستور درمانگر'),
                                ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(
                                      () => _administrationRoute =
                                          value ?? _administrationRoute,
                                    ),
                            ),
                          ),
                          _textField(
                            controller: _provider,
                            label: 'تزریق توسط / نام درمانگر',
                            hint: 'اختیاری',
                            icon: Icons.health_and_safety_rounded,
                          ),
                        ],
                        _textField(
                          controller: _reason,
                          label: _isAppointment
                              ? 'دلیل مراجعه'
                              : 'علت یا دستور تزریق',
                          hint: 'توضیح کوتاه',
                          icon: Icons.notes_rounded,
                          maxLines: 3,
                        ),
                        WellMateLabeledField(
                          label: 'وضعیت',
                          icon: Icons.task_alt_rounded,
                          bottomSpacing: 0,
                          child: DropdownButtonFormField<String>(
                            key: const ValueKey('edit-care-event-status'),
                            initialValue: _status,
                            decoration: wellMateFieldDecoration(),
                            items: const [
                              DropdownMenuItem(
                                value: 'scheduled',
                                child: Text('برنامه‌ریزی‌شده'),
                              ),
                              DropdownMenuItem(
                                value: 'completed',
                                child: Text('انجام‌شده'),
                              ),
                              DropdownMenuItem(
                                value: 'cancelled',
                                child: Text('لغوشده'),
                              ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(
                                    () => _status = value ?? _status,
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      title: 'مرکز و آدرس',
                      icon: Icons.location_on_rounded,
                      children: [
                        _textField(
                          controller: _center,
                          label: _isAppointment
                              ? 'نام مطب / کلینیک / بیمارستان'
                              : 'نام مرکز تزریقات / درمانگاه',
                          hint: 'نام مرکز',
                          icon: Icons.local_hospital_rounded,
                        ),
                        _textField(
                          controller: _address,
                          label: 'آدرس کامل',
                          hint: 'شهر، خیابان و پلاک',
                          icon: Icons.map_rounded,
                          maxLines: 3,
                        ),
                        _textField(
                          controller: _phone,
                          label: 'شماره تماس مرکز',
                          hint: 'اختیاری',
                          icon: Icons.phone_rounded,
                          keyboardType: TextInputType.phone,
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      title: 'تاریخ، زمان و یادآوری',
                      icon: Icons.schedule_rounded,
                      children: [
                        _PickerField(
                          label: 'تاریخ',
                          value: formatAppDate(context, _date),
                          icon: Icons.calendar_month_rounded,
                          onTap: _busy ? null : _pickDate,
                        ),
                        _PickerField(
                          label: 'ساعت',
                          value: formatAppTime(context, _time),
                          icon: Icons.access_time_rounded,
                          onTap: _busy ? null : _pickTime,
                          ltr: true,
                        ),
                        WellMateLabeledField(
                          label: 'یادآوری برای خودم',
                          icon: Icons.notifications_active_rounded,
                          child: DropdownButtonFormField<int>(
                            initialValue: _patientReminderMinutesBefore,
                            isExpanded: true,
                            decoration: wellMateFieldDecoration(),
                            items: [
                              for (final value
                                  in LifeMateReminderLeadTimes.presets)
                                DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    LifeMateReminderLeadTimes.label(value),
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(() {
                                    _patientReminderMinutesBefore =
                                        value ?? _patientReminderMinutesBefore;
                                  }),
                          ),
                        ),
                        WellMateLabeledField(
                          label: 'یادآوری برای مراقب',
                          icon: Icons.family_restroom_rounded,
                          child: DropdownButtonFormField<int>(
                            initialValue: _caregiverReminderMinutesBefore,
                            isExpanded: true,
                            decoration: wellMateFieldDecoration(),
                            items: [
                              for (final value
                                  in LifeMateReminderLeadTimes.presets)
                                DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    LifeMateReminderLeadTimes.label(value),
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(() {
                                    _caregiverReminderMinutesBefore =
                                        value ??
                                        _caregiverReminderMinutesBefore;
                                  }),
                          ),
                        ),
                        WellMateLabeledField(
                          label: 'منطقه زمانی',
                          icon: Icons.public_rounded,
                          child: TextFormField(
                            initialValue: _timeZone,
                            enabled: !_busy,
                            textDirection: TextDirection.ltr,
                            decoration: wellMateFieldDecoration(),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'منطقه زمانی لازم است.'
                                : null,
                            onChanged: (value) => _timeZone = value.trim(),
                          ),
                        ),
                        _textField(
                          controller: _instructions,
                          label: 'یادداشت و نکات همراه',
                          hint: 'مدارک، آزمایش یا نسخه موردنیاز',
                          icon: Icons.description_rounded,
                          maxLines: 4,
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const ValueKey('save-care-event-edit'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: _busy ? null : _save,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        _busy ? 'در حال ذخیره...' : 'ذخیره تغییرات',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextDirection? textDirection,
  }) {
    return WellMateLabeledField(
      label: label,
      icon: icon,
      required: required,
      child: TextFormField(
        controller: controller,
        enabled: !_busy,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textDirection: textDirection,
        decoration: wellMateFieldDecoration(hint: hint),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                  ? '$label را وارد کنید.'
                  : null
            : null,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.darkBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.ltr = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    return WellMateLabeledField(
      label: label,
      icon: icon,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: InputDecorator(
          decoration: wellMateFieldDecoration(),
          child: Text(
            value,
            textDirection: ltr ? TextDirection.ltr : null,
            style: const TextStyle(
              color: AppColors.darkBlue,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 52,
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('تلاش دوباره'),
            ),
          ],
        ),
      ),
    );
  }
}
