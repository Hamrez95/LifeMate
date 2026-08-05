import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import 'add_treatment_screen.dart';

class CarePlanHubScreen extends StatefulWidget {
  const CarePlanHubScreen({required this.onCreated, super.key});

  final VoidCallback onCreated;

  @override
  State<CarePlanHubScreen> createState() => _CarePlanHubScreenState();
}

class _CarePlanHubScreenState extends State<CarePlanHubScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              TabbedAddTreatmentScreen(onCreated: widget.onCreated),
              Padding(
                padding: const EdgeInsets.only(top: 78),
                child: _CareEventForm(
                  kind: _CarePlanKind.appointment,
                  onCreated: widget.onCreated,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 78),
                child: _CareEventForm(
                  kind: _CarePlanKind.injection,
                  onCreated: widget.onCreated,
                ),
              ),
            ],
          ),
        ),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 78,
          child: ColoredBox(color: AppColors.background),
        ),
        Positioned(
          top: 8,
          left: 20,
          right: 20,
          child: _CareTypeSelector(
            selectedIndex: _selectedIndex,
            onChanged: (index) => setState(() => _selectedIndex = index),
          ),
        ),
      ],
    );
  }
}

enum _CarePlanKind { appointment, injection }

class _CareTypeSelector extends StatelessWidget {
  const _CareTypeSelector({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = <(IconData, String)>[
      (Icons.medication_rounded, 'درمان'),
      (Icons.medical_services_rounded, 'ویزیت'),
      (Icons.vaccines_rounded, 'تزریق'),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          children: List.generate(items.length, (index) {
            final item = items[index];
            final selected = selectedIndex == index;
            return Expanded(
              child: Semantics(
                button: true,
                selected: selected,
                label: item.$2,
                child: InkWell(
                  key: ValueKey<String>('wellmate-care-type-$index'),
                  borderRadius: BorderRadius.circular(17),
                  onTap: () => onChanged(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.$1,
                          size: 21,
                          color: selected
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.$2,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: selected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _CareEventForm extends StatefulWidget {
  const _CareEventForm({required this.kind, required this.onCreated});

  final _CarePlanKind kind;
  final VoidCallback onCreated;

  @override
  State<_CareEventForm> createState() => _CareEventFormState();
}

class _CareEventFormState extends State<_CareEventForm> {
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
  String _clientRequestId = LifeMateApiClient.createClientRequestId();
  bool _loadingTimeZone = false;
  bool _busy = false;
  String? _error;

  bool get _isAppointment => widget.kind == _CarePlanKind.appointment;

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
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _isAppointment
                ? 'ویزیت با موفقیت ثبت شد.'
                : 'نوبت تزریق با موفقیت ثبت شد.',
          ),
        ),
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
                DropdownButtonFormField<String>(
                  initialValue: _administrationRoute,
                  isExpanded: true,
                  decoration: _decoration(
                    label: 'روش تزریق',
                    icon: Icons.route_rounded,
                  ),
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
                const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('care-event-timezone'),
                initialValue: _timeZone,
                enabled: !_busy,
                textDirection: TextDirection.ltr,
                decoration: _decoration(
                  label: 'منطقه زمانی',
                  icon: Icons.public_rounded,
                  suffix: _loadingTimeZone
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
              const SizedBox(height: 12),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: !_busy,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textDirection: textDirection,
        decoration: _decoration(label: label, hint: hint, icon: icon),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                  ? '$label را وارد کنید.'
                  : null
            : null,
      ),
    );
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.primary),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8FCFA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.08),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
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
    return Semantics(
      button: true,
      label: '$label، $value',
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FCFA),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 21, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.darkBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
