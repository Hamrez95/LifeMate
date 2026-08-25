import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';
import '../../core/widgets/labeled_form_field.dart';
import 'care_event_form.dart';

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
  Map<String, dynamic>? _loadedEvent;

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
          _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'اطلاعات ویزیت یا تزریق دریافت نشد.',
              en: "Visit or injection information was not received.",
            ),
            en: "Visit or injection information was not received.",
          );
        });
      }
    }
  }

  void _hydrate(Map<String, dynamic> event) {
    _loadedEvent = Map<String, dynamic>.from(event);
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

  Future<void> _reuseFromHistory() async {
    final source = _loadedEvent;
    if (source == null || _busy) return;
    final draft = CareEventReuseDraft.fromHistory(source);
    final kind = draft.eventType == 'injection'
        ? CarePlanKind.injection
        : CarePlanKind.appointment;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            title: Text(
              LifeMateRuntimeLocale.select(
                fa: 'ثبت دوباره',
                en: 'Register again',
              ),
            ),
          ),
          body: SafeArea(
            child: CareEventForm(
              kind: kind,
              initialDraft: draft,
              onCreated: () => Navigator.of(routeContext).pop(),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final value = await showAppDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
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
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: _isAppointment
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'ویزیت به‌روزرسانی شد',
                  en: "The visit has been updated",
                ),
                en: "The visit has been updated",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تزریق به‌روزرسانی شد',
                  en: "Injection updated",
                ),
                en: "Injection updated",
              ),
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تغییرات با موفقیت ذخیره شد.',
            en: "Changes saved successfully.",
          ),
          en: "Changes saved successfully.",
        ),
      );
      Navigator.of(context).pop(true);
    } on LifeMateApiException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } catch (error) {
      debugPrint('WellMate care event update failed: $error');
      if (mounted) {
        setState(
          () => _error = LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ذخیره تغییرات انجام نشد. اتصال را بررسی کنید.',
              en: "Failed to save changes. Check the connection.",
            ),
            en: "Failed to save changes. Check the connection.",
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(LifeMateApiException error) {
    return switch (error.code) {
      'stale_care_event' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'این برنامه در جای دیگری تغییر کرده است. صفحه را ببندید و دوباره باز کنید.',
          en: "This program has changed elsewhere. Close and reopen the page.",
        ),
        en: "This program has changed elsewhere. Close and reopen the page.",
      ),
      'care_event_not_found' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'این ویزیت یا تزریق دیگر وجود ندارد.',
          en: "There is no more visit or injection.",
        ),
        en: "There is no more visit or injection.",
      ),
      'invalid_medicationName' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'نام داروی تزریقی را وارد کنید.',
          en: "Enter the name of the injectable drug.",
        ),
        en: "Enter the name of the injectable drug.",
      ),
      'network_unavailable' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'اتصال اینترنت برای ذخیره تغییرات در دسترس نیست.',
          en: "Internet connection is not available to save changes.",
        ),
        en: "Internet connection is not available to save changes.",
      ),
      'session_missing' || 'invalid_session' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'نشست شما منقضی شده است. دوباره وارد شوید.',
          en: "Your session has expired. Sign in again.",
        ),
        en: "Your session has expired. Sign in again.",
      ),
      _ => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'اطلاعات واردشده معتبر نیست یا ذخیره انجام نشد.',
          en: "The information entered is not valid or could not be saved.",
        ),
        en: "The information entered is not valid or could not be saved.",
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final screenTitle = _isAppointment
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ویرایش ویزیت',
              en: "Edit visit",
            ),
            en: "Edit visit",
          )
        : LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ویرایش تزریق',
              en: "Edit injection",
            ),
            en: "Edit injection",
          );
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
        actions: [
          TextButton.icon(
            key: const ValueKey('reuse-care-event-action'),
            onPressed: _loading || _loadedEvent == null ? null : _reuseFromHistory,
            icon: const Icon(Icons.replay_rounded),
            label: Text(
              LifeMateRuntimeLocale.select(fa: 'ثبت دوباره', en: 'Reuse'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? Center(child: CircularProgressIndicator())
            : _error != null && _title.text.isEmpty
            ? _LoadError(message: _error!, onRetry: _load)
            : Form(
                key: _formKey,
                child: ListView(
                  key: ValueKey('edit-care-event-form'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 36),
                  children: [
                    if (_wasMissed)
                      Container(
                        margin: EdgeInsets.only(bottom: 16),
                        padding: EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.orange.shade100),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: Colors.orange,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                LifeMateRuntimeLocale.select(
                                  fa: LifeMateRuntimeLocale.select(
                                    fa: 'زمان این برنامه گذشته است. می‌توانید تاریخ و ساعت جدید تعیین کنید یا وضعیت آن را تغییر دهید.',
                                    en: "The time for this program has passed. You can set a new date and time or change its status.",
                                  ),
                                  en: "The time for this program has passed. You can set a new date and time or change its status.",
                                ),
                                style: TextStyle(height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    _Section(
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
                      icon: _isAppointment
                          ? Icons.medical_services_rounded
                          : Icons.vaccines_rounded,
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
                          icon: Icons.event_note_rounded,
                          required: true,
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
                                fa: 'نام پزشک',
                                en: "Doctor's name",
                              ),
                              en: "Doctor's name",
                            ),
                            icon: Icons.person_rounded,
                            required: true,
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
                                fa: 'مثلاً ۱ آمپول',
                                en: "For example, 1 ampoule",
                              ),
                              en: "For example, 1 ampoule",
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
                                  child: Text(
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
                                  child: Text(
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
                                  child: Text(
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
                                  child: Text(
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
                              fa: 'توضیح کوتاه',
                              en: "short explanation",
                            ),
                            en: "short explanation",
                          ),
                          icon: Icons.notes_rounded,
                          maxLines: 3,
                        ),
                        WellMateLabeledField(
                          label: LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'وضعیت',
                              en: "status",
                            ),
                            en: "status",
                          ),
                          icon: Icons.task_alt_rounded,
                          bottomSpacing: 0,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('edit-care-event-status'),
                            initialValue: _status,
                            decoration: wellMateFieldDecoration(),
                            items: [
                              DropdownMenuItem(
                                value: 'scheduled',
                                child: Text(
                                  LifeMateRuntimeLocale.select(
                                    fa: LifeMateRuntimeLocale.select(
                                      fa: 'برنامه‌ریزی‌شده',
                                      en: "planned",
                                    ),
                                    en: "planned",
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'completed',
                                child: Text(
                                  LifeMateRuntimeLocale.select(
                                    fa: LifeMateRuntimeLocale.select(
                                      fa: 'انجام‌شده',
                                      en: "done",
                                    ),
                                    en: "done",
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'cancelled',
                                child: Text(
                                  LifeMateRuntimeLocale.select(
                                    fa: LifeMateRuntimeLocale.select(
                                      fa: 'لغوشده',
                                      en: "canceled",
                                    ),
                                    en: "canceled",
                                  ),
                                ),
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
                    SizedBox(height: 16),
                    _Section(
                      title: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'مرکز و آدرس',
                          en: "Center and address",
                        ),
                        en: "Center and address",
                      ),
                      icon: Icons.location_on_rounded,
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
                              fa: 'نام مرکز',
                              en: "Name of the center",
                            ),
                            en: "Name of the center",
                          ),
                          icon: Icons.local_hospital_rounded,
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
                              fa: 'شهر، خیابان و پلاک',
                              en: "City, street and number plate",
                            ),
                            en: "City, street and number plate",
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
                      title: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'تاریخ، زمان و یادآوری',
                          en: "Date, time and reminder",
                        ),
                        en: "Date, time and reminder",
                      ),
                      icon: Icons.schedule_rounded,
                      children: [
                        _PickerField(
                          label: LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'تاریخ',
                              en: "date",
                            ),
                            en: "date",
                          ),
                          value: formatAppDate(context, _date),
                          icon: Icons.calendar_month_rounded,
                          onTap: _busy ? null : _pickDate,
                        ),
                        _PickerField(
                          label: LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'ساعت',
                              en: "hour",
                            ),
                            en: "hour",
                          ),
                          value: formatAppTime(context, _time),
                          icon: Icons.access_time_rounded,
                          onTap: _busy ? null : _pickTime,
                          ltr: true,
                        ),
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
                          label: LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'یادآوری برای مراقب',
                              en: "Reminder for caregivers",
                            ),
                            en: "Reminder for caregivers",
                          ),
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
                          label: LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'منطقه زمانی',
                              en: "time zone",
                            ),
                            en: "time zone",
                          ),
                          icon: Icons.public_rounded,
                          child: TextFormField(
                            initialValue: _timeZone,
                            enabled: !_busy,
                            textDirection: TextDirection.ltr,
                            decoration: wellMateFieldDecoration(),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
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
                              fa: 'مدارک، آزمایش یا نسخه موردنیاز',
                              en: "Required documents, tests or prescriptions",
                            ),
                            en: "Required documents, tests or prescriptions",
                          ),
                          icon: Icons.description_rounded,
                          maxLines: 4,
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      SizedBox(height: 14),
                      Container(
                        padding: EdgeInsets.all(14),
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
                    SizedBox(height: 20),
                    FilledButton.icon(
                      key: ValueKey('save-care-event-edit'),
                      style: FilledButton.styleFrom(
                        minimumSize: Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: _busy ? null : _save,
                      icon: _busy
                          ? SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(Icons.save_rounded),
                      label: Text(
                        _busy
                            ? LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'در حال ذخیره...',
                                  en: "Saving...",
                                ),
                                en: "Saving...",
                              )
                            : LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'ذخیره تغییرات',
                                  en: "Save changes",
                                ),
                                en: "Save changes",
                              ),
                        style: TextStyle(fontWeight: FontWeight.w900),
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
        inputFormatters: const [LifeMateLocaleDigitInputFormatter()],
        textDirection: textDirection,
        decoration: wellMateFieldDecoration(hint: hint),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                  ? LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: '$label را وارد کنید.',
                        en: "Enter $label.",
                      ),
                      en: "Enter $label.",
                    )
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
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 52, color: AppColors.primary),
            SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded),
              label: Text(
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
      ),
    );
  }
}
