import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../core/widgets/labeled_form_field.dart';

enum CarePlanKind { appointment, injection }

class CareEventForm extends StatefulWidget {
  const CareEventForm({super.key, required this.kind, required this.onCreated});

  final CarePlanKind kind;
  final VoidCallback onCreated;

  @override
  State<CareEventForm> createState() => _CareEventFormState();
}

class _CareEventFormState extends State<CareEventForm> {
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

  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  String _timeZone = 'Asia/Tehran';
  String _administrationRoute = 'intramuscular';
  int _patientReminderMinutesBefore =
      LifeMateReminderLeadTimes.defaultPatientMinutes;
  int _caregiverReminderMinutesBefore =
      LifeMateReminderLeadTimes.defaultCaregiverMinutes;
  String _clientRequestId = LifeMateApiClient.createClientRequestId();
  bool _loadingTimeZone = false;
  bool _busy = false;
  String? _error;

  bool get _isAppointment => widget.kind == CarePlanKind.appointment;

  @override
  void initState() {
    super.initState();
    _loadProfileTimeZone();
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

  Future<void> _loadProfileTimeZone() async {
    if (_loadingTimeZone) return;
    setState(() => _loadingTimeZone = true);
    try {
      final value = await context.read<LifeMateApiClient>().getCurrentUser();
      final profile = value['profile'] as Map<String, dynamic>?;
      final timeZone = profile?['timeZone']?.toString().trim();
      if (mounted && timeZone != null && timeZone.isNotEmpty) {
        setState(() => _timeZone = timeZone);
      }
    } catch (error) {
      debugPrint('WellMate care-event timezone load failed: $error');
    } finally {
      if (mounted) setState(() => _loadingTimeZone = false);
    }
  }

  Future<void> _pickDate() async {
    final value = await showAppDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      title: _isAppointment ? 'تاریخ ویزیت' : 'تاریخ تزریق',
    );
    if (mounted && value != null) setState(() => _date = value);
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (mounted && value != null) setState(() => _time = value);
  }

  String get _dateLabel => formatAppDate(context, _date);

  String get _timeValue =>
      '${_time.hour.toString().padLeft(2, '0')}:'
      '${_time.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<LifeMateApiClient>().createCareEvent(
        clientRequestId: _clientRequestId,
        eventType: _isAppointment ? 'appointment' : 'injection',
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
      );
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: _isAppointment ? 'ویزیت ثبت شد' : 'تزریق ثبت شد',
        message: _isAppointment
            ? 'ویزیت با موفقیت به برنامه اضافه شد.'
            : 'نوبت تزریق با موفقیت به برنامه اضافه شد.',
      );
      _reset();
      widget.onCreated();
    } on LifeMateApiException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } catch (error) {
      debugPrint('WellMate care-event creation failed: $error');
      if (mounted) {
        setState(() => _error = 'ثبت انجام نشد. اتصال اینترنت را بررسی کنید.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    for (final controller in [
      _title,
      _provider,
      _specialty,
      _dose,
      _reason,
      _center,
      _address,
      _phone,
      _instructions,
    ]) {
      controller.clear();
    }
    setState(() {
      _date = DateTime.now();
      _time = TimeOfDay.now();
      _administrationRoute = 'intramuscular';
      _patientReminderMinutesBefore =
          LifeMateReminderLeadTimes.defaultPatientMinutes;
      _caregiverReminderMinutesBefore =
          LifeMateReminderLeadTimes.defaultCaregiverMinutes;
      _clientRequestId = LifeMateApiClient.createClientRequestId();
      _error = null;
    });
  }

  String _friendlyError(LifeMateApiException error) {
    return switch (error.code) {
      'idempotency_key_reused' =>
        'این درخواست قبلاً برای برنامه دیگری استفاده شده است. دوباره تلاش کنید.',
      'invalid_medicationName' => 'نام داروی تزریقی را وارد کنید.',
      'invalid_session' ||
      'session_missing' => 'نشست شما منقضی شده است. دوباره وارد شوید.',
      _ => 'ثبت برنامه انجام نشد. اطلاعات را بررسی و دوباره تلاش کنید.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final title = _isAppointment ? 'افزودن ویزیت' : 'افزودن تزریق';
    final subtitle = _isAppointment
        ? 'پزشک، مرکز درمانی، آدرس و زمان ویزیت را ثبت کنید.'
        : 'داروی تزریقی، دوز، روش، محل و زمان انجام را ثبت کنید.';

    return Form(
      key: _formKey,
      child: ListView(
        key: ValueKey<String>(
          _isAppointment
              ? 'wellmate-appointment-form'
              : 'wellmate-injection-form',
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          MediaQuery.paddingOf(context).bottom + 170,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.darkBlue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 18),
          _Section(
            icon: _isAppointment
                ? Icons.medical_services_rounded
                : Icons.vaccines_rounded,
            title: _isAppointment ? 'مشخصات ویزیت' : 'مشخصات تزریق',
            children: [
              _textField(
                controller: _title,
                label: _isAppointment ? 'عنوان ویزیت' : 'نام داروی تزریقی',
                hint: _isAppointment
                    ? 'مثلاً ویزیت متخصص قلب'
                    : 'مثلاً ویتامین B12',
                icon: _isAppointment
                    ? Icons.event_note_rounded
                    : Icons.medication_liquid_rounded,
                required: true,
              ),
              if (_isAppointment) ...[
                _textField(
                  controller: _provider,
                  label: 'نام پزشک',
                  hint: 'مثلاً دکتر سارا راد',
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
                  hint: 'مثلاً ۱ آمپول یا ۵۰۰ میلی‌گرم',
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
                        child: _RouteLabel('عضلانی'),
                      ),
                      DropdownMenuItem(
                        value: 'subcutaneous',
                        child: _RouteLabel('زیرجلدی'),
                      ),
                      DropdownMenuItem(
                        value: 'intravenous',
                        child: _RouteLabel('وریدی'),
                      ),
                      DropdownMenuItem(
                        value: 'other',
                        child: _RouteLabel('سایر / طبق دستور درمانگر'),
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
                label: _isAppointment ? 'دلیل مراجعه' : 'علت یا دستور تزریق',
                hint: 'توضیح کوتاه؛ برنامه توصیه پزشکی جدید تولید نمی‌کند.',
                icon: Icons.notes_rounded,
                maxLines: 3,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            icon: Icons.location_on_rounded,
            title: 'مرکز و آدرس',
            children: [
              _textField(
                controller: _center,
                label: _isAppointment
                    ? 'نام مطب / کلینیک / بیمارستان'
                    : 'نام مرکز تزریقات / درمانگاه',
                hint: 'مثلاً مرکز درمانی الوند',
                icon: Icons.local_hospital_rounded,
              ),
              _textField(
                controller: _address,
                label: 'آدرس کامل',
                hint: 'شهر، خیابان، کوچه، پلاک و طبقه',
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
            icon: Icons.schedule_rounded,
            title: 'تاریخ و زمان',
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final date = _PickerTile(
                    key: const ValueKey<String>('care-event-date'),
                    label: 'تاریخ',
                    value: _dateLabel,
                    icon: Icons.calendar_month_rounded,
                    onTap: _busy ? null : _pickDate,
                  );
                  final time = _PickerTile(
                    key: const ValueKey<String>('care-event-time'),
                    label: 'ساعت',
                    value: formatAppTime(context, _time),
                    icon: Icons.access_time_rounded,
                    onTap: _busy ? null : _pickTime,
                  );
                  if (constraints.maxWidth < 320) {
                    return Column(
                      children: [date, const SizedBox(height: 10), time],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: date),
                      const SizedBox(width: 10),
                      Expanded(child: time),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              WellMateLabeledField(
                label: 'یادآوری برای خودم',
                icon: Icons.notifications_active_rounded,
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('care-event-patient-reminder-lead'),
                  initialValue: _patientReminderMinutesBefore,
                  isExpanded: true,
                  decoration: wellMateFieldDecoration(),
                  items: [
                    for (final minutes in LifeMateReminderLeadTimes.presets)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text(LifeMateReminderLeadTimes.label(minutes)),
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
                  key: const ValueKey('care-event-caregiver-reminder-lead'),
                  initialValue: _caregiverReminderMinutesBefore,
                  isExpanded: true,
                  decoration: wellMateFieldDecoration(),
                  items: [
                    for (final minutes in LifeMateReminderLeadTimes.presets)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text(LifeMateReminderLeadTimes.label(minutes)),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _caregiverReminderMinutesBefore =
                              value ?? _caregiverReminderMinutesBefore;
                        }),
                ),
              ),
              WellMateLabeledField(
                label: 'منطقه زمانی',
                icon: Icons.public_rounded,
                child: TextFormField(
                  key: const ValueKey<String>('care-event-timezone'),
                  initialValue: _timeZone,
                  enabled: !_busy,
                  textDirection: TextDirection.ltr,
                  decoration: wellMateFieldDecoration(
                    suffixIcon: _loadingTimeZone
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'منطقه زمانی لازم است.'
                      : null,
                  onChanged: (value) => _timeZone = value.trim(),
                ),
              ),
              _textField(
                controller: _instructions,
                label: 'یادداشت و نکات همراه',
                hint: 'مدارک، آزمایش یا نسخه‌ای که باید همراه باشد',
                icon: Icons.description_rounded,
                maxLines: 4,
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _ErrorPanel(message: _error!),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey<String>('care-event-submit'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    _isAppointment
                        ? Icons.event_available_rounded
                        : Icons.add_task_rounded,
                  ),
            label: Text(
              _busy
                  ? 'در حال ثبت...'
                  : (_isAppointment ? 'ثبت ویزیت' : 'ثبت نوبت تزریق'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
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

class _RouteLabel extends StatelessWidget {
  const _RouteLabel(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.darkBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return WellMateLabeledField(
      label: label,
      icon: icon,
      bottomSpacing: 0,
      child: Semantics(
        button: true,
        label: '$label، $value',
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FCFA),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.10),
              ),
            ),
            alignment: Alignment.centerRight,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.darkBlue,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
