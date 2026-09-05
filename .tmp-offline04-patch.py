from pathlib import Path

screen = Path('wellmate/lib/screens/treatments/add_treatment_screen.dart')
text = screen.read_text()
import_anchor = "import 'treatment_recurrence_editor.dart';\n"
import_line = "import 'offline_treatment_create.dart';\n"
if import_line not in text:
    if import_anchor not in text:
        raise SystemExit('add-treatment import anchor missing')
    text = text.replace(import_anchor, import_line + import_anchor, 1)

old = """      await api.createTreatmentPlan(
        medicationId: medication['id'].toString(),
        doseText: _dose.text,
        instructions: _instructions.text,
        startDate: _startDate,
        endDate: _endDate,
        timeZone: _timeZone,
        schedules: schedules,
        recurrence: _recurrenceSelection.rule(endDate: _endDate),
        recurrenceStartLocalTime: _recurrenceSelection.anchorLocalTime,
        patientReminderMinutesBefore: _patientReminderMinutesBefore,
        caregiverReminderMinutesBefore: _caregiverReminderMinutesBefore,
      );
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: LifeMateRuntimeLocale.select(
          fa: 'درمان ثبت شد',
          en: 'Treatment was recorded',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: 'برنامه درمان ذخیره شد و نوبت‌های آینده به‌صورت خودکار ساخته می‌شوند.',
          en: 'The treatment plan was saved and future occurrences will be generated automatically.',
        ),
      );
"""
new = """      final clientRequestId = LifeMateApiClient.createClientRequestId();
      final offlineRequest = WellMateOfflineTreatmentCreateRequest(
        clientRequestId: clientRequestId,
        medicationId: medication['id'].toString(),
        doseText: _dose.text,
        instructions: _instructions.text,
        startDate: _startDate,
        endDate: _endDate,
        timeZone: _timeZone,
        schedules: schedules,
        patientReminderMinutesBefore: _patientReminderMinutesBefore,
        caregiverReminderMinutesBefore: _caregiverReminderMinutesBefore,
      );
      var pendingSync = false;
      try {
        await api.createTreatmentPlan(
          medicationId: offlineRequest.medicationId,
          doseText: offlineRequest.doseText,
          instructions: offlineRequest.instructions,
          startDate: offlineRequest.startDate,
          endDate: offlineRequest.endDate,
          timeZone: offlineRequest.timeZone,
          schedules: offlineRequest.schedules,
          recurrence: _recurrenceSelection.rule(endDate: _endDate),
          recurrenceStartLocalTime: _recurrenceSelection.anchorLocalTime,
          patientReminderMinutesBefore:
              offlineRequest.patientReminderMinutesBefore,
          caregiverReminderMinutesBefore:
              offlineRequest.caregiverReminderMinutesBefore,
          clientRequestId: clientRequestId,
        );
      } on LifeMateApiException catch (error) {
        if (_recurrenceSelection.enabled ||
            !canQueueTreatmentCreateOffline(error)) {
          rethrow;
        }
        final queued = await tryQueueTreatmentCreateOffline(
          context,
          offlineRequest,
        );
        if (!queued) rethrow;
        pendingSync = true;
      }
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: pendingSync ? LifeMateNoticeType.info : LifeMateNoticeType.success,
        title: LifeMateRuntimeLocale.select(
          fa: pendingSync ? 'درمان روی این دستگاه ذخیره شد' : 'درمان ثبت شد',
          en: pendingSync
              ? 'Treatment saved on this device'
              : 'Treatment was recorded',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: pendingSync
              ? 'تأیید سرور هنوز انجام نشده است؛ پس از اتصال، برنامه درمان همگام‌سازی می‌شود.'
              : 'برنامه درمان ذخیره شد و نوبت‌های آینده به‌صورت خودکار ساخته می‌شوند.',
          en: pendingSync
              ? 'Server confirmation is pending; the treatment plan will sync after reconnection.'
              : 'The treatment plan was saved and future occurrences will be generated automatically.',
        ),
      );
"""
if old not in text:
    raise SystemExit('target create block not found')
screen.write_text(text.replace(old, new, 1))

client = Path('packages/lifemate_client/lib/src/lifemate_api_client.dart')
text = client.read_text()
old_sig = """    int caregiverReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultCaregiverMinutes,
  }) async {
"""
new_sig = """    int caregiverReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultCaregiverMinutes,
    String? clientRequestId,
  }) async {
"""
if old_sig not in text:
    raise SystemExit('createTreatmentPlan signature not found')
text = text.replace(old_sig, new_sig, 1)
old_send = """          'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getCareEvents({
"""
new_send = """          'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
        },
        idempotencyKey: clientRequestId,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getCareEvents({
"""
if old_send not in text:
    raise SystemExit('createTreatmentPlan send block not found')
client.write_text(text.replace(old_send, new_send, 1))
