from pathlib import Path

path = Path('packages/lifemate_client/lib/src/lifemate_api_client.dart')
text = path.read_text()
old = """    String? recurrenceStartLocalTime,\n    String? instructions,\n    int patientReminderMinutesBefore =\n"""
new = """    String? recurrenceStartLocalTime,\n    String? instructions,\n    String? clientRequestId,\n    int patientReminderMinutesBefore =\n"""
if old not in text:
    raise SystemExit('createTreatmentPlan signature anchor not found')
text = text.replace(old, new, 1)
old = """      );\n    }\n    return _asObject(\n      await _send(\n        'POST',\n        '/api/v1/treatment-plans',\n"""
new = """      );\n    }\n    final idempotencyKey = clientRequestId?.trim().isNotEmpty == true\n        ? clientRequestId!.trim()\n        : createClientRequestId();\n    return _asObject(\n      await _send(\n        'POST',\n        '/api/v1/treatment-plans',\n"""
if old not in text:
    raise SystemExit('createTreatmentPlan body anchor not found')
text = text.replace(old, new, 1)
old = """          'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,\n        },\n      ),\n    );\n  }\n\n  Future<List<Map<String, dynamic>>> getCareEvents({\n"""
new = """          'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,\n        },\n        retryable: true,\n        idempotencyKey: idempotencyKey,\n      ),\n    );\n  }\n\n  Future<List<Map<String, dynamic>>> getCareEvents({\n"""
if old not in text:
    raise SystemExit('createTreatmentPlan send anchor not found')
text = text.replace(old, new, 1)
path.write_text(text)

Path('tools/hotfix/apply_offline832_treatment_create_idempotency.py').unlink()
Path('.github/workflows/offline832-treatment-create-idempotency-patch.yml').unlink()
