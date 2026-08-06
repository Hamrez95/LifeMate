import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../core/utils/persian_date_utils.dart';
import '../widgets/caremate_bottom_nav.dart';
import '../widgets/custom_app_header.dart';
import 'calendar/calendar_screen.dart';
import 'dashboard_screen.dart';
import 'feature_preview_screen.dart';

class CareEventManagementScreen extends StatefulWidget {
  const CareEventManagementScreen({super.key});

  @override
  State<CareEventManagementScreen> createState() =>
      _CareEventManagementScreenState();
}

class _CareEventManagementScreenState extends State<CareEventManagementScreen> {
  int _selectedType = 0;
  bool _loading = true;
  String? _error;
  String? _selectedRelationshipId;
  List<Map<String, dynamic>> _relationships = const [];
  List<Map<String, dynamic>> _doses = const [];
  List<Map<String, dynamic>> _events = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Map<String, dynamic>? get _selectedRelationship {
    for (final relationship in _relationships) {
      if (relationship['id']?.toString() == _selectedRelationshipId) {
        return relationship;
      }
    }
    return null;
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<LifeMateApiClient>();
      final values = await Future.wait([
        api.getCurrentUser(),
        api.getCareRelationships(),
      ]);
      final current = values[0] as Map<String, dynamic>;
      final user = current['user'] as Map<String, dynamic>? ?? const {};
      final currentUserId = user['id']?.toString();
      final relationships = (values[1] as List<Map<String, dynamic>>)
          .where(
            (item) =>
                item['status']?.toString() == 'active' &&
                item['caregiverUserId']?.toString() == currentUserId,
          )
          .toList(growable: false);

      var selectedId = _selectedRelationshipId;
      if (!relationships.any((item) => item['id']?.toString() == selectedId)) {
        selectedId = relationships.isEmpty
            ? null
            : relationships.first['id']?.toString();
      }
      if (!mounted) return;
      setState(() {
        _relationships = relationships;
        _selectedRelationshipId = selectedId;
      });
      await _loadSelectedPatientData();
    } on LifeMateApiException catch (error) {
      _setError(_friendlyError(error));
    } catch (error) {
      debugPrint('CareMate treatment workspace load failed: $error');
      _setError('اطلاعات درمان دریافت نشد. اتصال اینترنت را بررسی کنید.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSelectedPatientData() async {
    final relationship = _selectedRelationship;
    if (relationship == null) {
      if (mounted) {
        setState(() {
          _doses = const [];
          _events = const [];
        });
      }
      return;
    }
    final patientUserId = relationship['patientUserId'].toString();
    final today = DateTime.now();
    final results = await Future.wait([
      context.read<LifeMateApiClient>().getCareRecipientDoseOccurrences(
        patientUserId: patientUserId,
        fromDate: today,
        toDate: today.add(const Duration(days: 7)),
      ),
      context.read<LifeMateApiClient>().getCareRecipientCareEvents(
        patientUserId: patientUserId,
        fromDate: today.subtract(const Duration(days: 1)),
        toDate: today.add(const Duration(days: 30)),
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _doses = results[0];
      _events = results[1];
    });
  }

  Future<void> _selectRelationship(String? id) async {
    if (id == null || id == _selectedRelationshipId) return;
    setState(() {
      _selectedRelationshipId = id;
      _loading = true;
      _error = null;
      _doses = const [];
      _events = const [];
    });
    try {
      await _loadSelectedPatientData();
    } on LifeMateApiException catch (error) {
      _setError(_friendlyError(error));
    } catch (error) {
      debugPrint('CareMate patient data switch failed: $error');
      _setError('برنامه فرد تحت مراقبت دریافت نشد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  void _onNavigationTap(int index) {
    if (index == 2) return;
    final Widget destination = switch (index) {
      0 => const CalendarScreen(),
      4 => const DashboardScreen(),
      _ => CareMateFeaturePreviewScreen(initialIndex: index),
    };
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => destination,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  String _friendlyError(LifeMateApiException error) {
    if (error.isUnauthorized) {
      return 'نشست شما منقضی شده است. دوباره وارد شوید.';
    }
    if (error.code == 'care_access_denied') {
      return 'دسترسی مراقبتی این بیمار فعال نیست.';
    }
    if (error.code == 'route_not_found') {
      return 'بخش ویزیت و تزریق هنوز روی سرور این نسخه فعال نشده است.';
    }
    return 'درخواست انجام نشد. دوباره تلاش کنید.';
  }

  @override
  Widget build(BuildContext context) {
    final relationship = _selectedRelationship;
    final patientName =
        relationship?['patientDisplayName']?.toString() ?? 'فرد تحت مراقبت';

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            CustomAppHeader(
              onNotificationTap: () {},
              onSignOutTap: LifeMateAuth.signOut,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 128),
                  children: [
                    const Text(
                      'افزودن برنامه مراقبتی',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'درمان، ویزیت و تزریق به‌صورت جدا نمایش داده می‌شوند. اطلاعات واقعی فقط در محدوده رضایت بیمار خوانده می‌شود.',
                      style: TextStyle(
                        color: AppColors.secondaryText,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _PatientSelector(
                      relationships: _relationships,
                      selectedId: _selectedRelationshipId,
                      onChanged: _loading ? null : _selectRelationship,
                    ),
                    const SizedBox(height: 16),
                    _TypeSelector(
                      selectedIndex: _selectedType,
                      onChanged: (index) =>
                          setState(() => _selectedType = index),
                    ),
                    const SizedBox(height: 18),
                    if (_error != null) ...[
                      _ErrorCard(message: _error!, onRetry: _refresh),
                      const SizedBox(height: 16),
                    ],
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 80),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (relationship == null)
                      const _NoPatientState()
                    else ...[
                      _PermissionNotice(patientName: patientName),
                      const SizedBox(height: 16),
                      switch (_selectedType) {
                        0 => _AppointmentWorkspace(
                          events: _events
                              .where(
                                (event) =>
                                    event['eventType']?.toString() ==
                                    'appointment',
                              )
                              .toList(growable: false),
                        ),
                        1 => _MedicationWorkspace(doses: _doses),
                        _ => _InjectionWorkspace(
                          events: _events
                              .where(
                                (event) =>
                                    event['eventType']?.toString() ==
                                    'injection',
                              )
                              .toList(growable: false),
                        ),
                      },
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CareMateBottomNav(
        currentIndex: 2,
        onTap: _onNavigationTap,
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.selectedIndex, required this.onChanged});

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.medical_services_rounded, 'ویزیت پزشکی'),
      (Icons.medication_rounded, 'داروی جدید'),
      (Icons.vaccines_rounded, 'تزریقات'),
    ];
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: List.generate(items.length, (index) {
          final selected = selectedIndex == index;
          final item = items[index];
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: item.$2,
              child: InkWell(
                key: ValueKey('caremate-care-type-$index'),
                borderRadius: BorderRadius.circular(17),
                onTap: () => onChanged(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minHeight: 58),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primaryBlue
                        : Colors.transparent,
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
                            : AppColors.secondaryText,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.$2,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? Colors.white
                              : AppColors.secondaryText,
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
    );
  }
}

class _PatientSelector extends StatelessWidget {
  const _PatientSelector({
    required this.relationships,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> relationships;
  final String? selectedId;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: relationships.isEmpty
          ? const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Color(0xFFEAF4FF),
                child: Icon(
                  Icons.person_search_rounded,
                  color: AppColors.primaryBlue,
                ),
              ),
              title: Text('فرد تحت مراقبت انتخاب نشده'),
              subtitle: Text('ابتدا دعوت معتبر بیمار را بپذیرید.'),
            )
          : DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedId,
                isExpanded: true,
                borderRadius: BorderRadius.circular(18),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                items: relationships
                    .map(
                      (relationship) => DropdownMenuItem<String>(
                        value: relationship['id']?.toString(),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Color(0xFFEAF4FF),
                              child: Icon(
                                Icons.person_rounded,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                relationship['patientDisplayName']
                                        ?.toString() ??
                                    'فرد تحت مراقبت',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: onChanged,
              ),
            ),
    );
  }
}

class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice({required this.patientName});

  final String patientName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFE3A0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, color: Color(0xFFC58B00)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'فرم‌ها برای $patientName کامل هستند، اما ثبت یا تغییر درمان توسط CareMate تا اضافه‌شدن مجوز صریح «مدیریت برنامه درمان» غیرفعال است. اطلاعات موجود به‌صورت واقعی و فقط خواندنی نمایش داده می‌شود.',
              style: const TextStyle(height: 1.55, color: Color(0xFF735200)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentWorkspace extends StatelessWidget {
  const _AppointmentWorkspace({required this.events});

  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ReadOnlyForm(
          icon: Icons.medical_services_rounded,
          title: 'فرم ویزیت پزشکی',
          fields: [
            ('نام پزشک', Icons.person_rounded),
            ('تخصص', Icons.workspace_premium_rounded),
            ('دلیل مراجعه', Icons.notes_rounded),
            ('نام مطب / مرکز درمانی', Icons.local_hospital_rounded),
            ('آدرس کامل', Icons.map_rounded),
            ('شماره تماس', Icons.phone_rounded),
            ('تاریخ و ساعت', Icons.schedule_rounded),
            ('یادداشت و مدارک همراه', Icons.description_rounded),
          ],
        ),
        const SizedBox(height: 18),
        _LiveEventList(
          title: 'ویزیت‌های ثبت‌شده',
          emptyText: 'ویزیتی برای ۳۰ روز آینده ثبت نشده است.',
          events: events,
        ),
      ],
    );
  }
}

class _MedicationWorkspace extends StatelessWidget {
  const _MedicationWorkspace({required this.doses});

  final List<Map<String, dynamic>> doses;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ReadOnlyForm(
          icon: Icons.medication_rounded,
          title: 'فرم داروی جدید',
          fields: [
            ('نام دارو', Icons.medication_rounded),
            ('قدرت / غلظت', Icons.science_rounded),
            ('شکل دارویی', Icons.category_rounded),
            ('مقدار مصرف', Icons.straighten_rounded),
            ('دلیل مصرف', Icons.notes_rounded),
            ('ساعت یا چند ساعت مصرف', Icons.schedule_rounded),
            ('روزها و بازه درمان', Icons.date_range_rounded),
            ('منطقه زمانی و مرور نهایی', Icons.public_rounded),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'برنامه واقعی هفت روز آینده',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (doses.isEmpty)
          const _InlineEmpty(text: 'دوز دارویی فعالی در این بازه وجود ندارد.')
        else
          ...doses.map(
            (dose) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DoseTile(dose: dose),
            ),
          ),
      ],
    );
  }
}

class _InjectionWorkspace extends StatelessWidget {
  const _InjectionWorkspace({required this.events});

  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ReadOnlyForm(
          icon: Icons.vaccines_rounded,
          title: 'فرم تزریقات',
          fields: [
            ('نام داروی تزریقی', Icons.medication_liquid_rounded),
            ('دوز یا مقدار', Icons.straighten_rounded),
            ('روش تزریق', Icons.route_rounded),
            ('نام درمانگر / مرکز تزریقات', Icons.health_and_safety_rounded),
            ('آدرس کامل', Icons.map_rounded),
            ('شماره تماس', Icons.phone_rounded),
            ('تاریخ و ساعت', Icons.schedule_rounded),
            ('دستور و نکات همراه', Icons.description_rounded),
          ],
        ),
        const SizedBox(height: 18),
        _LiveEventList(
          title: 'تزریق‌های ثبت‌شده',
          emptyText: 'نوبت تزریقی برای ۳۰ روز آینده ثبت نشده است.',
          events: events,
        ),
      ],
    );
  }
}

class _ReadOnlyForm extends StatelessWidget {
  const _ReadOnlyForm({
    required this.icon,
    required this.title,
    required this.fields,
  });

  final IconData icon;
  final String title;
  final List<(String, IconData)> fields;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.06),
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primaryBlue),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...fields.map(
            (field) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4, end: 4),
                    child: Text(
                      field.$1,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    key: ValueKey<String>(
                      'caremate-readonly-field-${field.$1}',
                    ),
                    width: double.infinity,
                    constraints: BoxConstraints(
                      minHeight:
                          field.$1.contains('آدرس') ||
                              field.$1.contains('یادداشت') ||
                              field.$1.contains('دلیل') ||
                              field.$1.contains('دستور')
                          ? 84
                          : 62,
                    ),
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      13,
                      11,
                      13,
                      11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F9FD),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF4FF),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            field.$2,
                            size: 21,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'ثبت نشده',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppColors.secondaryText.withValues(
                                alpha: 0.82,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 17,
                          color: AppColors.secondaryText.withValues(
                            alpha: 0.62,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.lock_rounded),
              label: const Text('ثبت نیازمند مجوز صریح بیمار'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveEventList extends StatelessWidget {
  const _LiveEventList({
    required this.title,
    required this.emptyText,
    required this.events,
  });

  final String title;
  final String emptyText;
  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (events.isEmpty)
          _InlineEmpty(text: emptyText)
        else
          ...events.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _EventTile(event: event),
            ),
          ),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final isInjection = event['eventType']?.toString() == 'injection';
    final rawDate = event['scheduledLocalDate']?.toString() ?? '';
    final parsedDate = DateTime.tryParse(rawDate);
    final date = parsedDate == null
        ? localizeDigits(context, rawDate.isEmpty ? '----/--/--' : rawDate)
        : formatAppDate(context, parsedDate);
    final rawTime = event['scheduledLocalTime']?.toString() ?? '--:--';
    final time = localizeDigits(
      context,
      rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
    );
    final center = event['centerName']?.toString().trim();
    final address = event['addressLine']?.toString().trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isInjection
                  ? const Color(0xFFFFF0F2)
                  : const Color(0xFFEAF4FF),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              isInjection
                  ? Icons.vaccines_rounded
                  : Icons.medical_services_rounded,
              color: isInjection ? Colors.redAccent : AppColors.primaryBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localizeDigits(
                    context,
                    event['title']?.toString() ??
                        (isInjection ? 'تزریق' : 'ویزیت'),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  '$date  •  $time',
                  textDirection: usesPersianCalendar(context)
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
                if (center != null && center.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    localizeDigits(context, center),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                if (address != null && address.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 15,
                        color: AppColors.secondaryText,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          localizeDigits(context, address),
                          style: const TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DoseTile extends StatelessWidget {
  const _DoseTile({required this.dose});

  final Map<String, dynamic> dose;

  @override
  Widget build(BuildContext context) {
    final time = dose['scheduledLocalTime']?.toString() ?? '--:--';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFEAF4FF),
            child: Icon(Icons.medication_rounded, color: AppColors.primaryBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              localizeDigits(
                context,
                dose['medicationName']?.toString() ?? 'دارو',
              ),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            localizeDigits(
              context,
              time.length >= 5 ? time.substring(0, 5) : time,
            ),
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.secondaryText),
      ),
    );
  }
}

class _NoPatientState extends StatelessWidget {
  const _NoPatientState();

  @override
  Widget build(BuildContext context) {
    return const _InlineEmpty(
      text:
          'برای مشاهده یا آماده‌کردن برنامه، ابتدا یک بیمار را از طریق دعوت و رضایت معتبر متصل کنید.',
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('تلاش دوباره')),
        ],
      ),
    );
  }
}
