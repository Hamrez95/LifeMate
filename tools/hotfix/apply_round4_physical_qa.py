from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one exact match, found {count}")
    write(path, text.replace(old, new, 1))


def regex_once(path: str, pattern: str, replacement: str) -> None:
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"{path}: expected one regex match, found {count}")
    write(path, updated)


# Shared edit client: status-only transition that preserves the canonical event payload.
replace_once(
    "packages/lifemate_client/lib/src/lifemate_edit_api.dart",
    """  Future<Map<String, dynamic>> getCareEvent({required String eventId}) async =>\n      _object(await _request('GET', '/api/v1/care-events/$eventId'));\n\n""",
    """  Future<Map<String, dynamic>> getCareEvent({required String eventId}) async =>\n      _object(await _request('GET', '/api/v1/care-events/$eventId'));\n\n  Future<Map<String, dynamic>> updateCareEventStatus({\n    required String eventId,\n    required String status,\n  }) async {\n    final event = await getCareEvent(eventId: eventId);\n    final eventType =\n        event['eventType']?.toString().trim().toLowerCase() == 'injection'\n        ? 'injection'\n        : 'appointment';\n    final title = event['title']?.toString().trim() ?? '';\n    final scheduledLocalDate = DateTime.tryParse(\n      event['scheduledLocalDate']?.toString() ?? '',\n    );\n    if (scheduledLocalDate == null) {\n      throw const FormatException('Care event is missing scheduledLocalDate.');\n    }\n\n    return updateCareEvent(\n      eventId: eventId,\n      version: int.tryParse(event['version']?.toString() ?? '') ?? 1,\n      eventType: eventType,\n      title: title,\n      providerName: _emptyToNull(event['providerName']?.toString()),\n      specialty: _emptyToNull(event['specialty']?.toString()),\n      medicationName: eventType == 'injection'\n          ? (_emptyToNull(event['medicationName']?.toString()) ?? title)\n          : null,\n      doseText: _emptyToNull(event['doseText']?.toString()),\n      administrationRoute: _emptyToNull(\n        event['administrationRoute']?.toString(),\n      ),\n      reason: _emptyToNull(event['reason']?.toString()),\n      instructions: _emptyToNull(event['instructions']?.toString()),\n      centerName: _emptyToNull(event['centerName']?.toString()),\n      addressLine: _emptyToNull(event['addressLine']?.toString()),\n      phoneNumber: _emptyToNull(event['phoneNumber']?.toString()),\n      scheduledLocalDate: scheduledLocalDate,\n      scheduledLocalTime:\n          event['scheduledLocalTime']?.toString().trim() ?? '00:00',\n      timeZone: event['timeZone']?.toString().trim().isNotEmpty == true\n          ? event['timeZone'].toString().trim()\n          : 'Asia/Tehran',\n      patientReminderMinutesBefore:\n          int.tryParse(event['patientReminderMinutesBefore']?.toString() ?? '') ??\n          30,\n      caregiverReminderMinutesBefore:\n          int.tryParse(\n            event['caregiverReminderMinutesBefore']?.toString() ?? '',\n          ) ??\n          60,\n      status: status,\n    );\n  }\n\n""",
)

# Home: keep a single fixed countdown, but retain injection as a legitimate next item.
replace_once(
    "wellmate/lib/screens/home/home_screen_content.dart",
    """              child: countdownItems.isEmpty\n                  ? _TreatmentTimerPlaceholder(\n                      hasTreatmentPlans: _hasTreatmentPlans,\n                      onAction: _hasTreatmentPlans\n                          ? widget.onOpenTreatments\n                          : widget.onAddTreatment,\n                      font: font,\n                    )\n                  : LayoutBuilder(\n                      builder: (context, constraints) {\n                        final cardWidth = countdownItems.length > 1\n                            ? constraints.maxWidth * 0.92\n                            : constraints.maxWidth;\n                        return SingleChildScrollView(\n                          key: const ValueKey('home-countdown-carousel'),\n                          scrollDirection: Axis.horizontal,\n                          physics: const BouncingScrollPhysics(),\n                          child: Row(\n                            children: [\n                              for (\n                                var index = 0;\n                                index < countdownItems.length;\n                                index += 1\n                              ) ...[\n                                SizedBox(\n                                  width: cardWidth,\n                                  child: _buildNextOccurrenceCard(\n                                    item: countdownItems[index],\n                                    font: font,\n                                    isPersian: isPersian,\n                                  ),\n                                ),\n                                if (index < countdownItems.length - 1)\n                                  const SizedBox(width: 12),\n                              ],\n                            ],\n                          ),\n                        );\n                      },\n                    ),\n""",
    """              child: countdownItems.isEmpty\n                  ? _TreatmentTimerPlaceholder(\n                      hasTreatmentPlans: _hasTreatmentPlans,\n                      onAction: _hasTreatmentPlans\n                          ? widget.onOpenTreatments\n                          : widget.onAddTreatment,\n                      font: font,\n                    )\n                  : _buildNextOccurrenceCard(\n                      item: countdownItems.first,\n                      font: font,\n                      isPersian: isPersian,\n                    ),\n""",
)
replace_once(
    "wellmate/lib/screens/home/home_screen_content.dart",
    """  int limit = 4,\n""",
    """  int limit = 1,\n""",
)
replace_once(
    "wellmate/lib/screens/home/home_screen_content.dart",
    """  int _calculateSecondsLeft(ScheduleItemModel item) {\n""",
    """  Future<void> _reportCareEventStatus(\n    ScheduleItemModel item,\n    String status,\n  ) async {\n    if (item.type == 'medicine' || _submitting.contains(item.id)) return;\n    final eventId = item.seriesId ?? item.id;\n    if (eventId.isEmpty) return;\n\n    // The current recurrence contract stores status on the series row. Never\n    // silently complete/cancel an entire recurring series from one occurrence.\n    if (item.seriesId != null && item.id != item.seriesId) {\n      if (mounted) {\n        ScaffoldMessenger.of(context).showSnackBar(\n          const SnackBar(\n            content: Text(\n              'ثبت وضعیت یک نوبت تکرارشونده از این کارت هنوز پشتیبانی نمی‌شود.',\n            ),\n            behavior: SnackBarBehavior.floating,\n          ),\n        );\n      }\n      return;\n    }\n\n    setState(() => _submitting.add(item.id));\n    try {\n      final result = await LifeMateEditApi.fromEnvironment().updateCareEventStatus(\n        eventId: eventId,\n        status: status,\n      );\n      if (!mounted) return;\n      final normalized = (result['status'] ?? status).toString().toLowerCase();\n      final updated = item.copyWith(\n        isDone: normalized == 'completed' || normalized == 'cancelled',\n        status: normalized,\n        version: result['version'] is int\n            ? result['version'] as int\n            : item.version + 1,\n      );\n      setState(() {\n        final index = scheduleList.indexWhere((value) => value.id == item.id);\n        if (index >= 0) scheduleList[index] = updated;\n        _countdownOccurrences = _countdownOccurrences\n            .where((value) => value.id != item.id)\n            .toList(growable: false);\n      });\n      ScaffoldMessenger.of(context).showSnackBar(\n        SnackBar(\n          content: Text(\n            status == 'completed'\n                ? '${item.title} به عنوان انجام‌شده ثبت شد.'\n                : '${item.title} به عنوان انجام‌نشده ثبت شد.',\n          ),\n          behavior: SnackBarBehavior.floating,\n        ),\n      );\n      await _fetchScheduleFromBackend();\n    } catch (error) {\n      debugPrint('WellMate care event status report failed: $error');\n      if (mounted) {\n        ScaffoldMessenger.of(context).showSnackBar(\n          const SnackBar(\n            content: Text('ثبت وضعیت انجام نشد؛ دوباره تلاش کنید.'),\n            behavior: SnackBarBehavior.floating,\n          ),\n        );\n      }\n    } finally {\n      if (mounted) setState(() => _submitting.remove(item.id));\n    }\n  }\n\n  int _calculateSecondsLeft(ScheduleItemModel item) {\n""",
)
replace_once(
    "wellmate/lib/screens/home/home_screen_content.dart",
    """                                    onTaken:\n                                        item.type == 'medicine' &&\n                                            missed &&\n                                            !_submitting.contains(item.id)\n                                        ? () => _reportStatus(item, 'taken')\n                                        : null,\n""",
    """                                    onTaken:\n                                        item.type == 'medicine' &&\n                                            missed &&\n                                            !_submitting.contains(item.id)\n                                        ? () => _reportStatus(item, 'taken')\n                                        : null,\n                                    onCompleted:\n                                        item.type != 'medicine' &&\n                                            missed &&\n                                            !_submitting.contains(item.id)\n                                        ? () => _reportCareEventStatus(\n                                            item,\n                                            'completed',\n                                          )\n                                        : null,\n                                    onNotCompleted:\n                                        item.type != 'medicine' &&\n                                            missed &&\n                                            !_submitting.contains(item.id)\n                                        ? () => _reportCareEventStatus(\n                                            item,\n                                            'cancelled',\n                                          )\n                                        : null,\n""",
)

# Today schedule: use care-event semantics instead of medication wording.
replace_once(
    "wellmate/lib/screens/home/soft_schedule_card.dart",
    """  final VoidCallback? onTaken;\n\n""",
    """  final VoidCallback? onTaken;\n  final VoidCallback? onCompleted;\n  final VoidCallback? onNotCompleted;\n\n""",
)
replace_once(
    "wellmate/lib/screens/home/soft_schedule_card.dart",
    """    this.onTaken,\n  }) : super(key: key);\n""",
    """    this.onTaken,\n    this.onCompleted,\n    this.onNotCompleted,\n  }) : super(key: key);\n""",
)
regex_once(
    "wellmate/lib/screens/home/soft_schedule_card.dart",
    r"                  if \(isMissed\) \.\.\.\[\n                    const SizedBox\(height: 12\),\n                    GestureDetector\(.*?\n                    \),\n                  \],",
    """                  if (isMissed) ...[\n                    const SizedBox(height: 12),\n                    if (item.type == 'medicine')\n                      GestureDetector(\n                        onTap: onTaken,\n                        child: Container(\n                          padding: const EdgeInsets.symmetric(\n                            vertical: 6,\n                            horizontal: 16,\n                          ),\n                          decoration: BoxDecoration(\n                            color: Colors.red.shade600,\n                            borderRadius: BorderRadius.circular(8),\n                          ),\n                          child: Text(\n                            'مصرف کردم',\n                            style: font.copyWith(\n                              color: Colors.white,\n                              fontSize: 12,\n                              fontWeight: FontWeight.bold,\n                            ),\n                          ),\n                        ),\n                      )\n                    else\n                      Wrap(\n                        spacing: 8,\n                        runSpacing: 8,\n                        children: [\n                          GestureDetector(\n                            onTap: onCompleted,\n                            child: Container(\n                              padding: const EdgeInsets.symmetric(\n                                vertical: 6,\n                                horizontal: 16,\n                              ),\n                              decoration: BoxDecoration(\n                                color: Colors.red.shade600,\n                                borderRadius: BorderRadius.circular(8),\n                              ),\n                              child: Text(\n                                'انجام شد',\n                                style: font.copyWith(\n                                  color: Colors.white,\n                                  fontSize: 12,\n                                  fontWeight: FontWeight.bold,\n                                ),\n                              ),\n                            ),\n                          ),\n                          GestureDetector(\n                            onTap: onNotCompleted,\n                            child: Container(\n                              padding: const EdgeInsets.symmetric(\n                                vertical: 6,\n                                horizontal: 16,\n                              ),\n                              decoration: BoxDecoration(\n                                color: Colors.white,\n                                borderRadius: BorderRadius.circular(8),\n                                border: Border.all(color: Colors.red.shade300),\n                              ),\n                              child: Text(\n                                'انجام نشد',\n                                style: font.copyWith(\n                                  color: Colors.red.shade700,\n                                  fontSize: 12,\n                                  fontWeight: FontWeight.bold,\n                                ),\n                              ),\n                            ),\n                          ),\n                        ],\n                      ),\n                  ],""",
)

# Header popup: care events now have an active red "انجام شد" action, no check icon.
regex_once(
    "wellmate/lib/core/widgets/wellmate_app_header.dart",
    r"          if \(isMedicine\)\n            GestureDetector\(.*?\n            \),\n        \],",
    """          GestureDetector(\n            onTap: () async {\n              final reporter = onMissedMedicationTaken;\n              if (reporter == null) return;\n              final success = await reporter(item);\n              if (success && context.mounted) {\n                context.read<MedicationProvider>().markAsDone(item.id);\n              }\n            },\n            child: Container(\n              padding: const EdgeInsets.symmetric(\n                horizontal: 12,\n                vertical: 8,\n              ),\n              decoration: BoxDecoration(\n                color: Colors.red.shade600,\n                borderRadius: BorderRadius.circular(8),\n              ),\n              child: Text(\n                isMedicine ? 'مصرف کردم' : 'انجام شد',\n                style: AppTextStyles.caption(\n                  context,\n                ).copyWith(color: Colors.white, fontWeight: FontWeight.bold),\n              ),\n            ),\n          ),\n        ],""",
)

# Notification provider snapshot should mark care events completed, not taken.
replace_once(
    "wellmate/lib/providers/medication_provider.dart",
    """    _scheduleItems = List<ScheduleItemModel>.of(_scheduleItems)\n      ..[index] = _scheduleItems[index].copyWith(isDone: true, status: 'taken');\n""",
    """    final item = _scheduleItems[index];\n    _scheduleItems = List<ScheduleItemModel>.of(_scheduleItems)\n      ..[index] = item.copyWith(\n        isDone: true,\n        status: item.type == 'medicine' ? 'taken' : 'completed',\n      );\n""",
)

# Header action handler: medication reports a dose; visit/injection completes the real care event.
regex_once(
    "wellmate/lib/screens/home/home_screen.dart",
    r"  Future<bool> _reportMissedDoseFromHeader\(ScheduleItemModel item\) async \{.*?\n  \}\n\n  void _onItemTapped",
    """  Future<bool> _reportMissedItemFromHeader(ScheduleItemModel item) async {\n    try {\n      if (item.type == 'medicine') {\n        await context.read<LifeMateApiClient>().reportDose(\n          occurrenceId: item.id,\n          clientRequestId: LifeMateApiClient.createClientRequestId(),\n          version: item.version,\n          status: 'taken',\n          occurredAtUtc: DateTime.now().toUtc(),\n        );\n      } else {\n        final eventId = item.seriesId ?? item.id;\n        if (item.seriesId != null && item.id != item.seriesId) {\n          if (mounted) {\n            ScaffoldMessenger.of(context).showSnackBar(\n              const SnackBar(\n                content: Text(\n                  'ثبت وضعیت یک نوبت تکرارشونده از اعلان‌ها هنوز پشتیبانی نمی‌شود.',\n                ),\n              ),\n            );\n          }\n          return false;\n        }\n        await LifeMateEditApi.fromEnvironment().updateCareEventStatus(\n          eventId: eventId,\n          status: 'completed',\n        );\n      }\n      if (!mounted) return true;\n      setState(() {\n        _calendarRevision++;\n        _homeRevision++;\n      });\n      ScaffoldMessenger.of(context).showSnackBar(\n        SnackBar(\n          content: Text(\n            item.type == 'medicine'\n                ? '${item.title} به عنوان مصرف‌شده ثبت شد.'\n                : '${item.title} به عنوان انجام‌شده ثبت شد.',\n          ),\n        ),\n      );\n      return true;\n    } on LifeMateApiException catch (error) {\n      if (!mounted) return false;\n      final message = error.code == 'stale_dose_occurrence' ||\n              error.code == 'stale_care_event'\n          ? 'وضعیت برنامه تغییر کرده است؛ صفحه تازه‌سازی شد.'\n          : 'ثبت وضعیت انجام نشد؛ دوباره تلاش کنید.';\n      setState(() {\n        _calendarRevision++;\n        _homeRevision++;\n      });\n      ScaffoldMessenger.of(\n        context,\n      ).showSnackBar(SnackBar(content: Text(message)));\n      return false;\n    } catch (_) {\n      if (mounted) {\n        ScaffoldMessenger.of(context).showSnackBar(\n          const SnackBar(\n            content: Text('ثبت وضعیت انجام نشد؛ اتصال را بررسی کنید.'),\n          ),\n        );\n      }\n      return false;\n    }\n  }\n\n  void _onItemTapped""",
)
replace_once(
    "wellmate/lib/screens/home/home_screen.dart",
    """                onMissedMedicationTaken: _reportMissedDoseFromHeader,\n""",
    """                onMissedMedicationTaken: _reportMissedItemFromHeader,\n""",
)

# Women calendar: remove only the first duplicate overview card. Leave the lower calendar/ring and all following content untouched.
replace_once(
    "wellmate/lib/screens/women_calendar/women_companion_screen.dart",
    """            const SizedBox(height: 14),\n            _CycleOverviewCard(estimate: estimate),\n            const SizedBox(height: 14),\n            WomenCalendarMonthCard(\n""",
    """            const SizedBox(height: 14),\n            WomenCalendarMonthCard(\n""",
)
regex_once(
    "wellmate/lib/screens/women_calendar/women_companion_screen.dart",
    r"\nclass _CycleOverviewCard extends StatelessWidget \{.*?\n\}\n\nclass _CycleRing extends StatelessWidget",
    "\nclass _CycleRing extends StatelessWidget",
)

# Shared client regression: status-only care event update does GET + preserving PATCH.
replace_once(
    "packages/lifemate_client/test/lifemate_edit_api_test.dart",
    """  test('maps stale care event response to LifeMateApiException', () async {\n""",
    """  test('status-only care event update preserves event fields', () async {\n    final requests = <http.Request>[];\n    final api = LifeMateEditApi(\n      baseUri: Uri.parse('https://api.example.test/functions/v1/lifemate-api'),\n      accessToken: () => 'token',\n      httpClient: MockClient((request) async {\n        requests.add(request);\n        if (request.method == 'GET') {\n          return http.Response(\n            jsonEncode({\n              'id': 'event-1',\n              'eventType': 'appointment',\n              'title': 'چکاپ زنان',\n              'providerName': 'سارا راد',\n              'centerName': 'مرکز الوند',\n              'scheduledLocalDate': '2026-08-08',\n              'scheduledLocalTime': '18:30',\n              'timeZone': 'Asia/Tehran',\n              'patientReminderMinutesBefore': 30,\n              'caregiverReminderMinutesBefore': 60,\n              'version': 3,\n              'status': 'missed',\n            }),\n            200,\n          );\n        }\n        return http.Response(\n          jsonEncode({'id': 'event-1', 'status': 'completed', 'version': 4}),\n          200,\n        );\n      }),\n    );\n\n    final result = await api.updateCareEventStatus(\n      eventId: 'event-1',\n      status: 'completed',\n    );\n\n    expect(result['status'], 'completed');\n    expect(requests, hasLength(2));\n    expect(requests.first.method, 'GET');\n    expect(requests.last.method, 'PATCH');\n    final body = jsonDecode(requests.last.body) as Map<String, dynamic>;\n    expect(body['version'], 3);\n    expect(body['title'], 'چکاپ زنان');\n    expect(body['providerName'], 'سارا راد');\n    expect(body['centerName'], 'مرکز الوند');\n    expect(body['status'], 'completed');\n  });\n\n  test('maps stale care event response to LifeMateApiException', () async {\n""",
)

# Countdown regression: fixed single next card, injection still becomes next when earlier items are done.
replace_once(
    "wellmate/test/home_injection_timeline_test.dart",
    """  test('countdown keeps injection when an earlier appointment also exists', () {\n    final date = DateTime(2026, 8, 17);\n    final items = [\n      ScheduleItemModel(\n        id: 'visit-1',\n        title: 'چکاپ',\n        time: '18:30',\n        dosage: '',\n        type: 'appointment',\n        frequency: 'ویزیت',\n        startDate: date,\n      ),\n      ScheduleItemModel(\n        id: 'dose-1',\n        title: 'دارو',\n        time: '21:00',\n        dosage: '۱ عدد',\n        type: 'medicine',\n        frequency: 'طبق برنامه',\n        startDate: date,\n      ),\n      ScheduleItemModel(\n        id: 'inj-1',\n        title: 'B12',\n        time: '21:30',\n        dosage: '۱ آمپول',\n        type: 'injection',\n        frequency: 'تزریق',\n        startDate: date,\n      ),\n    ];\n\n    final countdown = selectHomeCountdownItems(\n      items,\n      DateTime(2026, 8, 17, 17),\n    );\n    expect(countdown.map((item) => item.id), ['visit-1', 'dose-1', 'inj-1']);\n  });\n""",
    """  test('countdown stays single and injection is eligible when it is next', () {\n    final date = DateTime(2026, 8, 17);\n    final items = [\n      ScheduleItemModel(\n        id: 'visit-1',\n        title: 'چکاپ',\n        time: '18:30',\n        dosage: '',\n        type: 'appointment',\n        frequency: 'ویزیت',\n        startDate: date,\n      ),\n      ScheduleItemModel(\n        id: 'dose-1',\n        title: 'دارو',\n        time: '21:00',\n        dosage: '۱ عدد',\n        type: 'medicine',\n        frequency: 'طبق برنامه',\n        startDate: date,\n      ),\n      ScheduleItemModel(\n        id: 'inj-1',\n        title: 'B12',\n        time: '21:30',\n        dosage: '۱ آمپول',\n        type: 'injection',\n        frequency: 'تزریق',\n        startDate: date,\n      ),\n    ];\n\n    final first = selectHomeCountdownItems(\n      items,\n      DateTime(2026, 8, 17, 17),\n    );\n    expect(first.map((item) => item.id), ['visit-1']);\n\n    final injectionNext = selectHomeCountdownItems(\n      [\n        items[0].copyWith(status: 'completed', isDone: true),\n        items[1].copyWith(status: 'taken', isDone: true),\n        items[2],\n      ],\n      DateTime(2026, 8, 17, 19),\n    );\n    expect(injectionNext.map((item) => item.id), ['inj-1']);\n  });\n\n  test('home countdown UI is fixed rather than a carousel', () {\n    final source = File(\n      'lib/screens/home/home_screen_content.dart',\n    ).readAsStringSync();\n    expect(source, isNot(contains('home-countdown-carousel')));\n    expect(source, contains('item: countdownItems.first'));\n  });\n""",
)
replace_once(
    "wellmate/test/home_injection_timeline_test.dart",
    """import 'package:flutter_test/flutter_test.dart';\n""",
    """import 'dart:io';\n\nimport 'package:flutter_test/flutter_test.dart';\n""",
)

# Header notification regression: red care button says انجام شد, is tappable, and has no check icon.
replace_once(
    "wellmate/test/missed_notification_bell_test.dart",
    """    await _pumpHeader(tester, provider);\n    await tester.tap(find.byIcon(Icons.notifications_none_rounded));\n    await tester.pumpAndSettle();\n\n    expect(find.text('اعلان‌های انجام‌نشده'), findsOneWidget);\n    expect(find.text('ویزیت دکتر قلب'), findsOneWidget);\n    expect(find.text('انجام نشد'), findsOneWidget);\n    expect(find.text('مصرف کردم'), findsNothing);\n""",
    """    var completed = false;\n    await _pumpHeader(\n      tester,\n      provider,\n      reporter: (item) async {\n        completed = item.id == 'visit-1';\n        return true;\n      },\n    );\n    await tester.tap(find.byIcon(Icons.notifications_none_rounded));\n    await tester.pumpAndSettle();\n\n    expect(find.text('اعلان‌های انجام‌نشده'), findsOneWidget);\n    expect(find.text('ویزیت دکتر قلب'), findsOneWidget);\n    expect(find.text('انجام شد'), findsOneWidget);\n    expect(find.text('انجام نشد'), findsNothing);\n    expect(find.text('مصرف کردم'), findsNothing);\n    expect(find.byIcon(Icons.check_rounded), findsNothing);\n    await tester.tap(find.text('انجام شد'));\n    await tester.pumpAndSettle();\n    expect(completed, isTrue);\n    expect(provider.missedItems, isEmpty);\n""",
)
replace_once(
    "wellmate/test/missed_notification_bell_test.dart",
    """    expect(find.text('مصرف کردم'), findsOneWidget);\n    expect(find.text('انجام نشد'), findsOneWidget);\n""",
    """    expect(find.text('مصرف کردم'), findsOneWidget);\n    expect(find.text('انجام شد'), findsOneWidget);\n    expect(find.text('انجام نشد'), findsNothing);\n""",
)
replace_once(
    "wellmate/test/missed_notification_bell_test.dart",
    """Future<void> _pumpHeader(\n  WidgetTester tester,\n  MedicationProvider medicationProvider,\n) async {\n""",
    """Future<void> _pumpHeader(\n  WidgetTester tester,\n  MedicationProvider medicationProvider, {\n  MissedMedicationReporter? reporter,\n}) async {\n""",
)
replace_once(
    "wellmate/test/missed_notification_bell_test.dart",
    """        home: Scaffold(body: WellMateAppHeader(onProfileTap: () {})),\n""",
    """        home: Scaffold(\n          body: WellMateAppHeader(\n            onProfileTap: () {},\n            onMissedMedicationTaken: reporter,\n          ),\n        ),\n""",
)

# Direct widget semantics for overdue visit actions.
new_test = ROOT / "wellmate/test/home_visit_action_semantics_test.dart"
new_test.write_text(
    """import 'package:flutter/material.dart';\nimport 'package:flutter_test/flutter_test.dart';\nimport 'package:wellmate/models/schedule_item_model.dart';\nimport 'package:wellmate/screens/home/soft_schedule_card.dart';\n\nvoid main() {\n  testWidgets('missed visit uses done/not-done wording and both actions work', (\n    tester,\n  ) async {\n    var completed = 0;\n    var notCompleted = 0;\n    final item = ScheduleItemModel(\n      id: 'visit-1',\n      title: 'چکاپ زنان',\n      time: '18:30',\n      dosage: 'سارا راد • مرکز الوند',\n      type: 'appointment',\n      status: 'missed',\n      frequency: 'ویزیت',\n    );\n\n    await tester.pumpWidget(\n      MaterialApp(\n        locale: const Locale('fa'),\n        home: Scaffold(\n          body: SoftScheduleCard(\n            item: item,\n            index: 0,\n            font: const TextStyle(),\n            assetPath: 'assets/icons/stethoscope.png',\n            isMissed: true,\n            onCompleted: () => completed++,\n            onNotCompleted: () => notCompleted++,\n          ),\n        ),\n      ),\n    );\n\n    expect(find.text('مصرف کردم'), findsNothing);\n    expect(find.text('انجام شد'), findsOneWidget);\n    expect(find.text('انجام نشد'), findsOneWidget);\n\n    await tester.tap(find.text('انجام شد'));\n    await tester.tap(find.text('انجام نشد'));\n    expect(completed, 1);\n    expect(notCompleted, 1);\n  });\n}\n""",
    encoding="utf-8",
)

# Women regression: only the duplicate top overview is removed; the existing lower content remains.
replace_once(
    "wellmate/test/women_companion_experience_test.dart",
    """  testWidgets(\n    'women dashboard puts large cycle then calendar before mood',\n""",
    """  testWidgets(\n    'women dashboard removes only the duplicate top cycle overview',\n""",
)
replace_once(
    "wellmate/test/women_companion_experience_test.dart",
    """      expect(\n        find.byKey(const ValueKey('women-cycle-overview-large')),\n        findsOneWidget,\n      );\n      expect(find.text('تقویم و ثبت دوره'), findsNothing);\n""",
    """      expect(\n        find.byKey(const ValueKey('women-cycle-overview-large')),\n        findsNothing,\n      );\n      expect(find.text('تقویم و ثبت دوره'), findsNothing);\n      expect(find.text('فاز قاعدگی'), findsOneWidget);\n""",
)

print('Round 4 physical QA patch applied successfully.')
