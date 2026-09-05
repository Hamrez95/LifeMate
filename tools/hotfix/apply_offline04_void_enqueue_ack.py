from pathlib import Path

# 1) Keep the protected native mutation model out of the web surface entirely.
core_web = Path('packages/lifemate_core/lib/lifemate_core_web.dart')
text = core_web.read_text()
block = """/// Type-only web seam for durable mutation return signatures. The native\n/// implementation contains the protected outbox record and replay metadata;\n/// browser builds cannot construct, persist, inspect or replay that record.\n/// This keeps conditional API signatures compatible without widening the web\n/// PHI surface.\nabstract interface class LifeMateDurableMutation {}\n\n"""
assert block in text, 'core web durable mutation seam anchor changed'
core_web.write_text(text.replace(block, '', 1))

# 2) Shared runtime acknowledgement is void; the protected outbox record stays
# internal to the native execution engine.
native_runtime = Path('packages/lifemate_client/lib/src/shared_offline_runtime_native.dart')
text = native_runtime.read_text()
old = """  Future<LifeMateDurableMutation> enqueueTreatmentEdit({\n    required String mutationId,\n"""
new = """  Future<void> enqueueTreatmentEdit({\n    required String mutationId,\n"""
assert old in text, 'native runtime signature anchor changed'
text = text.replace(old, new, 1)
old = """    _requireOpen();\n    return LifeMateOfflineTreatmentMutation.enqueueEdit(\n      outbox: _outbox,\n"""
new = """    _requireOpen();\n    await LifeMateOfflineTreatmentMutation.enqueueEdit(\n      outbox: _outbox,\n"""
assert old in text, 'native runtime return anchor changed'
text = text.replace(old, new, 1)
native_runtime.write_text(text)

web_runtime = Path('packages/lifemate_client/lib/src/shared_offline_runtime_web.dart')
text = web_runtime.read_text()
old = """  Future<LifeMateDurableMutation> enqueueTreatmentEdit({\n    required String mutationId,\n"""
new = """  Future<void> enqueueTreatmentEdit({\n    required String mutationId,\n"""
assert old in text, 'web runtime signature anchor changed'
text = text.replace(old, new, 1)
old = """  }) => Future<LifeMateDurableMutation>.error(_unsupported());\n"""
new = """  }) => Future<void>.error(_unsupported());\n"""
assert old in text, 'web runtime error anchor changed'
text = text.replace(old, new, 1)
web_runtime.write_text(text)

# 3) Durable API client exposes only completion/failure acknowledgement on both
# platforms. It does not expose a native local-outbox model to UI/shared web code.
native_client = Path('packages/lifemate_client/lib/src/durable_lifemate_api_client.dart')
text = native_client.read_text()
old = """  Future<LifeMateDurableMutation> enqueueOfflineTreatmentPlanEdit({\n    required String clientRequestId,\n"""
new = """  Future<void> enqueueOfflineTreatmentPlanEdit({\n    required String clientRequestId,\n"""
assert old in text, 'native client signature anchor changed'
text = text.replace(old, new, 1)
native_client.write_text(text)

web_client = Path('packages/lifemate_client/lib/src/durable_lifemate_api_client_web.dart')
text = web_client.read_text()
old = """  Future<LifeMateDurableMutation> enqueueOfflineTreatmentPlanEdit({\n    required String clientRequestId,\n"""
new = """  Future<void> enqueueOfflineTreatmentPlanEdit({\n    required String clientRequestId,\n"""
assert old in text, 'web client signature anchor changed'
text = text.replace(old, new, 1)
old = """  }) => Future<LifeMateDurableMutation>.error(\n    UnsupportedError('Protected offline health execution is unavailable on web.'),\n  );\n"""
new = """  }) => Future<void>.error(\n    UnsupportedError('Protected offline health execution is unavailable on web.'),\n  );\n"""
assert old in text, 'web client error anchor changed'
text = text.replace(old, new, 1)
web_client.write_text(text)

# 4) Regression verifies the durable record via the canonical protected outbox,
# not by widening the client acknowledgement type.
test = Path('packages/lifemate_client/test/durable_treatment_edit_enqueue_test.dart')
t = test.read_text()
old = """    final mutation = await api.enqueueOfflineTreatmentPlanEdit(\n      clientRequestId: requestId,\n"""
new = """    await api.enqueueOfflineTreatmentPlanEdit(\n      clientRequestId: requestId,\n"""
assert old in t, 'test enqueue anchor changed'
t = t.replace(old, new, 1)
old = """    expect(mutation.mutationId, requestId);\n    expect(mutation.endpointPath, '/api/v1/treatment-plans/$planId');\n    expect(mutation.expectedRevision, '7');\n    expect(mutation.payload['schedules'], <Map<String, String>>[\n      <String, String>{'dayOfWeek': 'monday', 'localTime': '08:00'},\n      <String, String>{'dayOfWeek': 'monday', 'localTime': '16:00'},\n    ]);\n    expect(await api.pendingMutationCount(), 1);\n\n    final stored = await LifeMateLocalMutationOutbox(store: store).get(\n"""
new = """    expect(await api.pendingMutationCount(), 1);\n\n    final stored = await LifeMateLocalMutationOutbox(store: store).get(\n"""
assert old in t, 'test returned mutation assertions anchor changed'
t = t.replace(old, new, 1)
old = """    expect(stored?.domain, LifeMateMutationDomain.treatment);\n    expect(stored?.sourceKey, planId);\n    expect(stored?.state, LifeMateMutationSyncState.pending);\n"""
new = """    expect(stored?.mutationId, requestId);\n    expect(stored?.domain, LifeMateMutationDomain.treatment);\n    expect(stored?.sourceKey, planId);\n    expect(stored?.endpointPath, '/api/v1/treatment-plans/$planId');\n    expect(stored?.expectedRevision, '7');\n    expect(stored?.payload['schedules'], <Map<String, String>>[\n      <String, String>{'dayOfWeek': 'monday', 'localTime': '08:00'},\n      <String, String>{'dayOfWeek': 'monday', 'localTime': '16:00'},\n    ]);\n    expect(stored?.state, LifeMateMutationSyncState.pending);\n"""
assert old in t, 'test stored mutation anchor changed'
t = t.replace(old, new, 1)
test.write_text(t)

# Self-delete temporary write machinery so the PR diff is product/test only.
Path('tools/hotfix/apply_offline04_void_enqueue_ack.py').unlink()
Path('.github/workflows/offline04-void-enqueue-ack-patch.yml').unlink()
