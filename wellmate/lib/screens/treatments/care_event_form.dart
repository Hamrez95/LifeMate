import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../core/utils/care_time_picker.dart';
import '../../core/widgets/labeled_form_field.dart';

enum CarePlanKind { appointment, injection }

class CareEventForm extends StatefulWidget {
  const CareEventForm({
    super.key,
    required this.kind,
    required this.onCreated,
    this.initialDraft,
  });

  final CarePlanKind kind;
  final VoidCallback onCreated;
  final CareEventReuseDraft? initialDraft;

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
  final _repeatInterval = TextEditingController(text: '1');
  final _repeatCount = TextEditingController();

  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  String _timeZone = 'Asia/Tehran';
  String _administrationRoute = 'intramuscular';
  bool _repeatEnabled = false;
  RecurrenceUnit _repeatUnit = RecurrenceUnit.month;
  DateTime? _repeatEndDate;
  final Set<int> _repeatWeekdays = <int>{};
  int _patientReminderMinutesBefore =
      LifeMateReminderLeadTimes.defaultPatientMinutes;
  int _caregiverReminderMinutesBefore =
      LifeMateReminderLeadTimes.defaultCaregiverMinutes;
  String _clientRequestId = LifeMateApiClient.createClientRequestId();
  bool _loadingTimeZone = false;
  bool _busy = false;
  String? _error;
  List<LifeMateHistoryUsage> _historyUsages = const [];
  bool _historyLoading = false;
  bool _historyUnavailable = false;

  bool get _isAppointment => widget.kind == CarePlanKind.appointment;

  @override
  void initState() {
    super.initState();
    _applyInitialDraft(widget.initialDraft);
    _title.addListener(_onHistoryQueryChanged);
    _provider.addListener(_onHistoryQueryChanged);
    _center.addListener(_onHistoryQueryChanged);
    _loadProfileTimeZone();
    _loadPersonalHistory();
  }

  @override
  void dispose() {
    _title.removeListener(_onHistoryQueryChanged);
    _provider.removeListener(_onHistoryQueryChanged);
    _center.removeListener(_onHistoryQueryChanged);
    _title.dispose();
    _provider.dispose();
    _specialty.dispose();
    _dose.dispose();
    _reason.dispose();
    _center.dispose();
    _address.dispose();
    _phone.dispose();
    _instructions.dispose();
    _repeatInterval.dispose();
    _repeatCount.dispose();
    super.dispose();
  }

  void _applyInitialDraft(CareEventReuseDraft? draft) {
    if (draft == null) return;
    _title.text = draft.title;
    _provider.text = draft.providerName ?? '';
    _specialty.text = draft.specialty ?? '';
    _dose.text = draft.doseText ?? '';
    _reason.text = draft.reason ?? '';
    _center.text = draft.centerName ?? '';
    _address.text = draft.addressLine ?? '';
    _phone.text = draft.phoneNumber ?? '';
    _instructions.text = draft.instructions ?? '';
    _administrationRoute = draft.administrationRoute ?? 'intramuscular';
    _timeZone = draft.timeZone;
    _patientReminderMinutesBefore = draft.patientReminderMinutesBefore;
    _caregiverReminderMinutesBefore = draft.caregiverReminderMinutesBefore;
    final recurrence = draft.recurrence;
    _repeatEnabled = recurrence.enabled;
    if (recurrence.enabled) {
      _repeatUnit = recurrence.unit;
      _repeatInterval.text = recurrence.interval.toString();
      _repeatEndDate = recurrence.endDate;
      _repeatWeekdays
        ..clear()
        ..addAll(recurrence.weekdays);
      if (recurrence.maxOccurrences != null) {
        _repeatCount.text = recurrence.maxOccurrences.toString();
      }
    }
  }

  void _onHistoryQueryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPersonalHistory() async {
    if (_historyLoading) return;
    setState(() {
      _historyLoading = true;
      _historyUnavailable = false;
    });
    final usages = <LifeMateHistoryUsage>[];
    try {
      final api = context.read<LifeMateApiClient>();
      final now = DateTime.now();
      final eventsById = <String, Map<String, dynamic>>{};
      for (var window = 0; window < 6; window += 1) {
        final to = now.subtract(Duration(days: window * 30));
        final from = to.subtract(const Duration(days: 30));
        final events = await api.getCareEvents(fromDate: from, toDate: to);
        for (final event in events) {
          final id = event['id']?.toString() ?? event.toString();
          eventsById[id] = event;
        }
      }
      for (final event in eventsById.values) {
        final usedAt = DateTime.tryParse(event['updatedAtUtc']?.toString() ?? '') ??
            DateTime.tryParse(event['scheduledAtUtc']?.toString() ?? '') ??
            DateTime.tryParse(event['scheduledLocalDate']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final eventType = event['eventType']?.toString().toLowerCase();
        void add(LifeMateHistorySuggestionKind kind, dynamic raw, {String? context}) {
          final value = raw?.toString().trim() ?? '';
          if (value.isEmpty) return;
          usages.add(LifeMateHistoryUsage(
            kind: kind,
            value: value,
            usedAt: usedAt,
            context: context,
          ));
        }
        add(LifeMateHistorySuggestionKind.center, event['centerName']);
        if (eventType == 'appointment') {
          add(
            LifeMateHistorySuggestionKind.doctor,
            event['providerName'],
            context: event['specialty']?.toString(),
          );
          add(LifeMateHistorySuggestionKind.careAction, event['title']);
        } else if (eventType == 'injection') {
          add(
            LifeMateHistorySuggestionKind.injection,
            event['medicationName'] ?? event['title'],
            context: event['doseText']?.toString(),
          );
        }
      }
      final plans = await api.getTreatmentPlans();
      for (final plan in plans) {
        final medication = plan['medication'];
        if (medication is! Map) continue;
        final name = medication['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        usages.add(LifeMateHistoryUsage(
          kind: LifeMateHistorySuggestionKind.medication,
          value: name,
          usedAt: DateTime.tryParse(plan['updatedAtUtc']?.toString() ?? '') ??
              DateTime.tryParse(plan['startDate']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
          context: plan['doseText']?.toString(),
        ));
      }
      if (!mounted) return;
      setState(() => _historyUsages = List.unmodifiable(usages));
    } catch (error) {
      debugPrint('WellMate personal history suggestions unavailable: $error');
      if (mounted) setState(() => _historyUnavailable = true);
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  List<LifeMateHistorySuggestion> _historySuggestions(
    TextEditingController controller,
    LifeMateHistorySuggestionKind kind,
  ) => rankLifeMateHistorySuggestions(
    history: _historyUsages,
    query: controller.text,
    kind: kind,
  );

  Future<void> _loadProfileTimeZone() async {
    if (_loadingTimeZone) return;
    setState(() => _loadingTimeZone = true);
    try {
      final value = await context.read<LifeMateApiClient>().getCurrentUser();
      final profile = value['profile'] as Map<String, dynamic>?;
      final timeZone = profile?['timeZone']?.toString().trim();
      if (mounted && timeZone != null && timeZone.isNotEmpty && widget.initialDraft == null) {
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
      firstDate: DateTime.now().subtract(Duration(days: 1)),
      lastDate: DateTime.now().add(Duration(days: 3650)),
      title: _isAppointment
          ? LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'تاریخ ویزیت',
                en: "Date of visit",
              ),
              en: "Date of visit",
            )
          : LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'تاریخ تزریق',
                en: "Date of injection",
              ),
              en: "Date of injection",
            ),
    );
    if (mounted && value != null) setState(() => _date = value);
  }

  Future<void> _pickTime() async {
    final value = await showCareTimePicker(
      context: context,
      initialTime: _time,
      title: _isAppointment
          ? LifeMateRuntimeLocale.select(fa: 'ساعت ویزیت', en: 'Visit time')
          : LifeMateRuntimeLocale.select(fa: 'ساعت تزریق', en: 'Injection time'),
    );
    if (mounted && value != null) setState(() => _time = value);
  }

  String get _dateLabel => formatAppDate(context, _date);

  String get _timeValue =>
      '${_time.hour.toString().padLeft(2, '0')}:'
      '${_time.minute.toString().padLeft(2, '0')}';

  RecurrenceRule? _recurrenceRule() {
    if (!_repeatEnabled) return const RecurrenceRule.none();
    final interval = LifeMateNumbers.tryParseInt(_repeatInterval.text);
    if (interval == null || interval < 1 || interval > 365) {
      setState(
        () => _error = LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'فاصله تکرار باید یک عدد بین ۱ تا ۳۶۵ باشد.',
            en: "The repetition interval must be a number between 1 and 365.",
          ),
          en: "The repetition interval must be a number between 1 and 365.",
        ),
      );
      return null;
    }
    final weekdays = _repeatUnit == RecurrenceUnit.week
        ? (_repeatWeekdays.isEmpty ? <int>{_date.weekday} : _repeatWeekdays)
        : const <int>{};
    final countText = _repeatCount.text.trim();
    final maxOccurrences = countText.isEmpty
        ? null
        : LifeMateNumbers.tryParseInt(countText);
    if (maxOccurrences != null &&
        (maxOccurrences < 1 || maxOccurrences > 1000)) {
      setState(
        () => _error = LifeMateRuntimeLocale.select(
          fa: 'تعداد تکرار باید بین ۱ تا ۱۰۰۰ باشد.',
          en: 'Repeat count must be between 1 and 1000.',
        ),
      );
      return null;
    }
    if (countText.isNotEmpty && maxOccurrences == null) {
      setState(
        () => _error = LifeMateRuntimeLocale.select(
          fa: 'تعداد تکرار معتبر وارد کنید.',
          en: 'Enter a valid repeat count.',
        ),
      );
      return null;
    }
    final draft = RecurrenceRule(
      enabled: true,
      unit: _repeatUnit,
      interval: interval,
      weekdays: weekdays,
      endDate: _repeatEndDate,
      maxOccurrences: maxOccurrences,
    );
    return RecurrenceRule(
      enabled: true,
      unit: _repeatUnit,
      interval: interval,
      weekdays: weekdays,
      endDate: draft.persistenceEndDate(_date),
      maxOccurrences: maxOccurrences,
    );
  }

  Future<void> _pickRepeatEndDate() async {
    final value = await showAppDatePicker(
      context: context,
      initialDate: _repeatEndDate ?? _date.add(Duration(days: 180)),
      firstDate: _date,
      lastDate: _date.add(Duration(days: 3650)),
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'پایان تکرار',
          en: "End of repetition",
        ),
        en: "End of repetition",
      ),
    );
    if (mounted && value != null) setState(() => _repeatEndDate = value);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final recurrence = _recurrenceRule();
    if (recurrence == null) return;

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
        recurrence: recurrence,
        patientReminderMinutesBefore: _patientReminderMinutesBefore,
        caregiverReminderMinutesBefore: _caregiverReminderMinutesBefore,
      );
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: _isAppointment
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'ویزیت ثبت شد',
                  en: "Appointment saved",
                ),
                en: "Appointment saved",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تزریق ثبت شد',
                  en: "Injection saved",
                ),
                en: "Injection saved",
              ),
        message: _isAppointment
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'ویزیت با موفقیت به برنامه اضافه شد.',
                  en: "The visit has been successfully added to the program.",
                ),
                en: "The visit has been successfully added to the program.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'نوبت تزریق با موفقیت به برنامه اضافه شد.',
                  en: "The injection appointment has been successfully added to the program.",
                ),
                en: "The injection appointment has been successfully added to the program.",
              ),
      );
      _reset();
      widget.onCreated();
    } on LifeMateApiException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } catch (error) {
      debugPrint('WellMate care-event creation failed: $error');
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ثبت انجام نشد. اتصال اینترنت را بررسی کنید.',
              en: "Registration failed. Check your internet connection.",
            ),
            en: "Registration failed. Check your internet connection.",
          ),
        );
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
      _repeatEnabled = false;
      _repeatUnit = RecurrenceUnit.month;
      _repeatInterval.text = '1';
      _repeatCount.clear();
      _repeatEndDate = null;
      _repeatWeekdays.clear();
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
      'idempotency_key_reused' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'این درخواست قبلاً برای برنامه دیگری استفاده شده است. دوباره تلاش کنید.',
          en: "This request has already been used for another application. Try again.",
        ),
        en: "This request has already been used for another application. Try again.",
      ),
      'invalid_medicationName' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'نام داروی تزریقی را وارد کنید.',
          en: "Enter the name of the injectable drug.",
        ),
        en: "Enter the name of the injectable drug.",
      ),
      'invalid_session' || 'session_missing' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'نشست شما منقضی شده است. دوباره وارد شوید.',
          en: "Your session has expired. Sign in again.",
        ),
        en: "Your session has expired. Sign in again.",
      ),
      _ => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'ثبت برنامه انجام نشد. اطلاعات را بررسی و دوباره تلاش کنید.',
          en: "Could not save the schedule. Check the information and try again.",
        ),
        en: "Could not save the schedule. Check the information and try again.",
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final title = _isAppointment
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'افزودن ویزیت',
              en: "Add a visit",
            ),
            en: "Add a visit",
          )
        : LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'افزودن تزریق',
              en: "Add injection",
            ),
            en: "Add injection",
          );
    final subtitle = _isAppointment
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'پزشک، مرکز درمانی، آدرس و زمان ویزیت را ثبت کنید.',
              en: "Record the doctor, treatment center, address and time of visit.",
            ),
            en: "Record the doctor, treatment center, address and time of visit.",
          )
        : LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'داروی تزریقی، دوز، روش، محل و زمان انجام را ثبت کنید.',
              en: "Record the injection drug, dose, method, place and time of administration.",
            ),
            en: "Record the injection drug, dose, method, place and time of administration.",
          );

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
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.darkBlue,
            ),
          ),
          SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: AppColors.textSecondary, height: 1.55),
          ),
          SizedBox(height: 18),
          _Section(
            icon: _isAppointment
                ? Icons.medical_services_rounded
                : Icons.vaccines_rounded,
            title: _isAppointment
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'مشخصات ویزیت',
                      en: "Visit details",
                    ),
                    en: "Visit details",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'مشخصات تزریق',
                      en: "Injection specifications",
                    ),
                    en: "Injection specifications",
                  ),
            children: [
              _textField(
                controller: _title,
                label: _isAppointment
                    ? LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'عنوان ویزیت',
                          en: "The title of the visit",
                        ),
                        en: "The title of the visit",
                      )
                    : LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'نام داروی تزریقی',
                          en: "The name of the injectable drug",
                        ),
                        en: "The name of the injectable drug",
                      ),
                hint: _isAppointment
                    ? LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'مثلاً ویزیت متخصص قلب',
                          en: "For example, a visit to a cardiologist",
                        ),
                        en: "For example, a visit to a cardiologist",
                      )
                    : LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'مثلاً ویتامین B12',
                          en: "For example, vitamin B12",
                        ),
                        en: "For example, vitamin B12",
                      ),
                icon: _isAppointment
                    ? Icons.event_note_rounded
                    : Icons.medication_liquid_rounded,
                required: true,
                historyKind: _isAppointment
                    ? LifeMateHistorySuggestionKind.careAction
                    : LifeMateHistorySuggestionKind.injection,
              ),
              if (_isAppointment) ...[
                _textField(
                  controller: _provider,
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'نام پزشک',
                      en: "Doctor's name",
                    ),
                    en: "Doctor's name",
                  ),
                  hint: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'مثلاً دکتر سارا راد',
                      en: "For example, Dr. Sarah Rudd",
                    ),
                    en: "For example, Dr. Sarah Rudd",
                  ),
                  icon: Icons.person_rounded,
                  required: true,
                  historyKind: LifeMateHistorySuggestionKind.doctor,
                ),
                _textField(
                  controller: _specialty,
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'تخصص',
                      en: "Expertise",
                    ),
                    en: "Expertise",
                  ),
                  hint: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'مثلاً متخصص قلب و عروق',
                      en: "For example, a cardiologist",
                    ),
                    en: "For example, a cardiologist",
                  ),
                  icon: Icons.workspace_premium_rounded,
                ),
              ] else ...[
                _textField(
                  controller: _dose,
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'دوز یا مقدار تزریق',
                      en: "Dose or amount of injection",
                    ),
                    en: "Dose or amount of injection",
                  ),
                  hint: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'مثلاً ۱ آمپول یا ۵۰۰ میلی‌گرم',
                      en: "For example, 1 ampoule or 500 mg",
                    ),
                    en: "For example, 1 ampoule or 500 mg",
                  ),
                  icon: Icons.straighten_rounded,
                  required: true,
                ),
                WellMateLabeledField(
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'روش تزریق',
                      en: "Injection method",
                    ),
                    en: "Injection method",
                  ),
                  icon: Icons.route_rounded,
                  child: DropdownButtonFormField<String>(
                    initialValue: _administrationRoute,
                    isExpanded: true,
                    decoration: wellMateFieldDecoration(),
                    items: [
                      DropdownMenuItem(
                        value: 'intramuscular',
                        child: _RouteLabel(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'عضلانی',
                              en: "muscular",
                            ),
                            en: "muscular",
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'subcutaneous',
                        child: _RouteLabel(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'زیرجلدی',
                              en: "Undercover",
                            ),
                            en: "Undercover",
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'intravenous',
                        child: _RouteLabel(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'وریدی',
                              en: "vein",
                            ),
                            en: "vein",
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'other',
                        child: _RouteLabel(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'سایر / طبق دستور درمانگر',
                              en: "Other / according to the therapist's instructions",
                            ),
                            en: "Other / according to the therapist's instructions",
                          ),
                        ),
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
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'تزریق توسط / نام درمانگر',
                      en: "Injection by / name of therapist",
                    ),
                    en: "Injection by / name of therapist",
                  ),
                  hint: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'اختیاری',
                      en: "optional",
                    ),
                    en: "optional",
                  ),
                  icon: Icons.health_and_safety_rounded,
                ),
              ],
              _textField(
                controller: _reason,
                label: _isAppointment
                    ? LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'دلیل مراجعه',
                          en: "Reason for referral",
                        ),
                        en: "Reason for referral",
                      )
                    : LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'علت یا دستور تزریق',
                          en: "Cause or order of injection",
                        ),
                        en: "Cause or order of injection",
                      ),
                hint: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'توضیح کوتاه؛ برنامه توصیه پزشکی جدید تولید نمی‌کند.',
                    en: "short description; The program does not generate new medical recommendations.",
                  ),
                  en: "short description; The program does not generate new medical recommendations.",
                ),
                icon: Icons.notes_rounded,
                maxLines: 3,
              ),
            ],
          ),
          SizedBox(height: 16),
          _Section(
            icon: Icons.location_on_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'مرکز و آدرس',
                en: "Center and address",
              ),
              en: "Center and address",
            ),
            children: [
              _textField(
                controller: _center,
                label: _isAppointment
                    ? LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'نام مطب / کلینیک / بیمارستان',
                          en: "Name of office/clinic/hospital",
                        ),
                        en: "Name of office/clinic/hospital",
                      )
                    : LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'نام مرکز تزریقات / درمانگاه',
                          en: "Name of the injection center/clinic",
                        ),
                        en: "Name of the injection center/clinic",
                      ),
                hint: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'مثلاً مرکز درمانی الوند',
                    en: "For example, Elvand Medical Center",
                  ),
                  en: "For example, Elvand Medical Center",
                ),
                icon: Icons.local_hospital_rounded,
                historyKind: LifeMateHistorySuggestionKind.center,
              ),
              _textField(
                controller: _address,
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'آدرس کامل',
                    en: "Full address",
                  ),
                  en: "Full address",
                ),
                hint: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'شهر، خیابان، کوچه، پلاک و طبقه',
                    en: "City, street, alley, number plate and floor",
                  ),
                  en: "City, street, alley, number plate and floor",
                ),
                icon: Icons.map_rounded,
                maxLines: 3,
              ),
              _textField(
                controller: _phone,
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'شماره تماس مرکز',
                    en: "Center contact number",
                  ),
                  en: "Center contact number",
                ),
                hint: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'اختیاری',
                    en: "optional",
                  ),
                  en: "optional",
                ),
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
          SizedBox(height: 16),
          _Section(
            icon: Icons.schedule_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'تاریخ و زمان',
                en: "date and time",
              ),
              en: "date and time",
            ),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final date = _PickerTile(
                    key: ValueKey<String>('care-event-date'),
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(fa: 'تاریخ', en: "date"),
                      en: "date",
                    ),
                    value: _dateLabel,
                    icon: Icons.calendar_month_rounded,
                    onTap: _busy ? null : _pickDate,
                  );
                  final time = _PickerTile(
                    key: ValueKey<String>('care-event-time'),
                    label: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(fa: 'ساعت', en: "hour"),
                      en: "hour",
                    ),
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
              SizedBox(height: 16),
              SwitchListTile.adaptive(
                key: ValueKey('care-event-repeat-enabled'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'تکرار برنامه',
                      en: "Repeat program",
                    ),
                    en: "Repeat program",
                  ),
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'برای چکاپ یا تزریق دوره‌ای، مثل هر ۶ ماه',
                      en: "For periodic checkups or injections, such as every 6 months",
                    ),
                    en: "For periodic checkups or injections, such as every 6 months",
                  ),
                ),
                value: _repeatEnabled,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _repeatEnabled = value),
              ),
              if (_repeatEnabled) ...[
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('care-event-repeat-interval'),
                        controller: _repeatInterval,
                        keyboardType: TextInputType.number,
                        inputFormatters: const [
                          LifeMateLocaleDigitInputFormatter(),
                        ],
                        textDirection: TextDirection.ltr,
                        decoration: wellMateFieldDecoration(
                          hint: LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'مثلاً ۶',
                              en: "For example, 6",
                            ),
                            en: "For example, 6",
                          ),
                        ),
                        validator: (value) {
                          final parsed = LifeMateNumbers.tryParseInt(value);
                          return parsed != null && parsed >= 1 && parsed <= 365
                              ? null
                              : LifeMateRuntimeLocale.select(
                                  fa: LifeMateRuntimeLocale.select(
                                    fa: '۱ تا ۳۶۵',
                                    en: "1 to 365",
                                  ),
                                  en: "1 to 365",
                                );
                        },
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<RecurrenceUnit>(
                        key: ValueKey('care-event-repeat-unit'),
                        initialValue: _repeatUnit,
                        decoration: wellMateFieldDecoration(),
                        items: [
                          DropdownMenuItem(
                            value: RecurrenceUnit.day,
                            child: Text(
                              LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'روز',
                                  en: "day",
                                ),
                                en: "day",
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: RecurrenceUnit.week,
                            child: Text(
                              LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'هفته',
                                  en: "week",
                                ),
                                en: "week",
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: RecurrenceUnit.month,
                            child: Text(
                              LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'ماه',
                                  en: "Month",
                                ),
                                en: "Month",
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: RecurrenceUnit.year,
                            child: Text(
                              LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'سال',
                                  en: "year",
                                ),
                                en: "year",
                              ),
                            ),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(
                                () => _repeatUnit = value ?? _repeatUnit,
                              ),
                      ),
                    ),
                  ],
                ),
                if (_repeatUnit == RecurrenceUnit.week) ...[
                  SizedBox(height: 12),
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'روزهای هفته',
                        en: "days of the week",
                      ),
                      en: "days of the week",
                    ),
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final day in <(int, String)>[
                        (
                          DateTime.saturday,
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'ش',
                              en: "Sat",
                            ),
                            en: "Sat",
                          ),
                        ),
                        (
                          DateTime.sunday,
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'ی',
                              en: "Sun",
                            ),
                            en: "Sun",
                          ),
                        ),
                        (
                          DateTime.monday,
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'د',
                              en: "Mon",
                            ),
                            en: "Mon",
                          ),
                        ),
                        (
                          DateTime.tuesday,
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'س',
                              en: "Tue",
                            ),
                            en: "Tue",
                          ),
                        ),
                        (
                          DateTime.wednesday,
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'چ',
                              en: "Wed",
                            ),
                            en: "Wed",
                          ),
                        ),
                        (
                          DateTime.thursday,
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'پ',
                              en: "Thu",
                            ),
                            en: "Thu",
                          ),
                        ),
                        (
                          DateTime.friday,
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'ج',
                              en: "Fri",
                            ),
                            en: "Fri",
                          ),
                        ),
                      ])
                        FilterChip(
                          label: Text(day.$2),
                          selected: _repeatWeekdays.contains(day.$1),
                          onSelected: _busy
                              ? null
                              : (selected) => setState(() {
                                  if (selected) {
                                    _repeatWeekdays.add(day.$1);
                                  } else {
                                    _repeatWeekdays.remove(day.$1);
                                  }
                                }),
                        ),
                    ],
                  ),
                ],
                SizedBox(height: 12),
                _PickerTile(
                  key: ValueKey('care-event-repeat-end'),
                  label: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'پایان تکرار',
                      en: "End of repetition",
                    ),
                    en: "End of repetition",
                  ),
                  value: _repeatEndDate == null
                      ? LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'بدون تاریخ پایان',
                            en: "No end date",
                          ),
                          en: "No end date",
                        )
                      : formatAppDate(context, _repeatEndDate!),
                  icon: Icons.event_repeat_rounded,
                  onTap: _busy ? null : _pickRepeatEndDate,
                ),
                if (_repeatEndDate != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _repeatEndDate = null),
                      icon: Icon(Icons.close_rounded, size: 18),
                      label: Text(
                        LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'بدون تاریخ پایان',
                            en: "No end date",
                          ),
                          en: "No end date",
                        ),
                      ),
                    ),
                  ),
                SizedBox(height: 8),
                WellMateLabeledField(
                  label: LifeMateRuntimeLocale.select(
                    fa: 'پایان بعد از تعداد دفعات',
                    en: 'End after occurrences',
                  ),
                  icon: Icons.pin_rounded,
                  helperText: LifeMateRuntimeLocale.select(
                    fa: 'اگر هم تاریخ پایان و هم تعداد را وارد کنید، هرکدام زودتر برسد اعمال می‌شود.',
                    en: 'If both are set, the earlier end boundary is used.',
                  ),
                  child: TextFormField(
                    key: ValueKey('care-event-repeat-count'),
                    controller: _repeatCount,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [LifeMateLocaleDigitInputFormatter()],
                    textDirection: TextDirection.ltr,
                    decoration: wellMateFieldDecoration(
                      hint: LifeMateRuntimeLocale.select(
                        fa: 'مثلاً ۵',
                        en: 'For example, 5',
                      ),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return null;
                      final parsed = LifeMateNumbers.tryParseInt(text);
                      return parsed != null && parsed >= 1 && parsed <= 1000
                          ? null
                          : LifeMateRuntimeLocale.select(
                              fa: '۱ تا ۱۰۰۰',
                              en: '1 to 1000',
                            );
                    },
                  ),
                ),
              ],
              SizedBox(height: 16),
              WellMateLabeledField(
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'یادآوری برای خودم',
                    en: "A reminder to myself",
                  ),
                  en: "A reminder to myself",
                ),
                icon: Icons.notifications_active_rounded,
                child: DropdownButtonFormField<int>(
                  key: ValueKey('care-event-patient-reminder-lead'),
                  initialValue: _patientReminderMinutesBefore,
                  isExpanded: true,
                  decoration: wellMateFieldDecoration(),
                  items: [
                    for (final minutes in LifeMateReminderLeadTimes.presets)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text(
                          localizeDigits(
                            context,
                            LifeMateReminderLeadTimes.label(minutes),
                          ),
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
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'یادآوری برای مراقب',
                    en: "Reminder for caregivers",
                  ),
                  en: "Reminder for caregivers",
                ),
                icon: Icons.family_restroom_rounded,
                child: DropdownButtonFormField<int>(
                  key: ValueKey('care-event-caregiver-reminder-lead'),
                  initialValue: _caregiverReminderMinutesBefore,
                  isExpanded: true,
                  decoration: wellMateFieldDecoration(),
                  items: [
                    for (final minutes in LifeMateReminderLeadTimes.presets)
                      DropdownMenuItem(
                        value: minutes,
                        child: Text(
                          localizeDigits(
                            context,
                            LifeMateReminderLeadTimes.label(minutes),
                          ),
                        ),
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
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'منطقه زمانی',
                    en: "time zone",
                  ),
                  en: "time zone",
                ),
                icon: Icons.public_rounded,
                child: TextFormField(
                  key: ValueKey<String>('care-event-timezone'),
                  initialValue: _timeZone,
                  enabled: !_busy,
                  textDirection: TextDirection.ltr,
                  decoration: wellMateFieldDecoration(
                    suffixIcon: _loadingTimeZone
                        ? Padding(
                            padding: EdgeInsets.all(13),
                            child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'منطقه زمانی لازم است.',
                            en: "Time zone is required.",
                          ),
                          en: "Time zone is required.",
                        )
                      : null,
                  onChanged: (value) => _timeZone = value.trim(),
                ),
              ),
              _textField(
                controller: _instructions,
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'یادداشت و نکات همراه',
                    en: "Notes and accompanying notes",
                  ),
                  en: "Notes and accompanying notes",
                ),
                hint: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'مدارک، آزمایش یا نسخه‌ای که باید همراه باشد',
                    en: "Documents, tests or prescriptions that must be accompanied",
                  ),
                  en: "Documents, tests or prescriptions that must be accompanied",
                ),
                icon: Icons.description_rounded,
                maxLines: 4,
              ),
            ],
          ),
          if (_error != null) ...[
            SizedBox(height: 14),
            _ErrorPanel(message: _error!),
          ],
          SizedBox(height: 18),
          FilledButton.icon(
            key: ValueKey<String>('care-event-submit'),
            style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(54),
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? SizedBox.square(
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
                  ? LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'در حال ثبت...',
                        en: "Registering...",
                      ),
                      en: "Registering...",
                    )
                  : (_isAppointment
                        ? LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'ثبت ویزیت',
                              en: "Register a visit",
                            ),
                            en: "Register a visit",
                          )
                        : LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'ثبت نوبت تزریق',
                              en: "Registration of injection appointments",
                            ),
                            en: "Registration of injection appointments",
                          )),
              style: TextStyle(fontWeight: FontWeight.w900),
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
    LifeMateHistorySuggestionKind? historyKind,
  }) {
    return WellMateLabeledField(
      label: label,
      icon: icon,
      required: required,
      child: Builder(
        builder: (context) {
          final suggestions = historyKind == null
              ? const <LifeMateHistorySuggestion>[]
              : _historySuggestions(controller, historyKind);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: controller,
                enabled: !_busy,
                maxLines: maxLines,
                keyboardType: keyboardType,
                inputFormatters: const [LifeMateLocaleDigitInputFormatter()],
                textDirection: textDirection,
                decoration: wellMateFieldDecoration(hint: hint),
                validator: required
                    ? (value) => value == null || value.trim().isEmpty
                          ? LifeMateRuntimeLocale.select(
                              fa: '$label را وارد کنید.',
                              en: 'Enter $label.',
                            )
                          : null
                    : null,
              ),
              if (historyKind != null && _historyLoading) ...[
                SizedBox(height: 6),
                LinearProgressIndicator(minHeight: 2),
              ] else if (suggestions.isNotEmpty) ...[
                SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final suggestion in suggestions)
                      ActionChip(
                        key: ValueKey(
                          'history-suggestion-${historyKind!.name}-${suggestion.value}',
                        ),
                        label: Text(
                          '${suggestion.value} · ${suggestion.usageCount}×',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: _busy
                            ? null
                            : () {
                                controller.value = TextEditingValue(
                                  text: suggestion.value,
                                  selection: TextSelection.collapsed(
                                    offset: suggestion.value.length,
                                  ),
                                );
                              },
                      ),
                  ],
                ),
              ] else if (historyKind != null &&
                  _historyUnavailable &&
                  normalizeLifeMateHistoryText(controller.text).length >= 2) ...[
                SizedBox(height: 6),
                Text(
                  LifeMateRuntimeLocale.select(
                    fa: 'پیشنهادهای سوابق فعلاً در دسترس نیست؛ می‌توانید آزادانه تایپ کنید.',
                    en: 'History suggestions are unavailable; you can keep typing freely.',
                  ),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          );
        },
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
        label: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: '$label، $value',
            en: "$label, $value",
          ),
          en: "$label, $value",
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: 58),
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: Color(0xFFF8FCFA),
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
              style: TextStyle(
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
