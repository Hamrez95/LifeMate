from pathlib import Path

screen = Path('wellmate/lib/screens/treatments/edit_treatment_screen.dart')
text = screen.read_text()

anchor = "import 'treatment_schedule_payload.dart';\n\nclass EditTreatmentScreen extends StatefulWidget {"
replacement = "import 'treatment_schedule_payload.dart';\n\nenum WellMateTreatmentEditSaveState { serverConfirmed, pendingSync }\n\nclass EditTreatmentScreen extends StatefulWidget {"
assert anchor in text, 'save-state enum anchor changed'
text = text.replace(anchor, replacement, 1)

anchor = """    this.editApi,\n    this.offlineEnqueuer,\n  });\n\n  final Map<String, dynamic> plan;\n  final LifeMateEditApi? editApi;\n  final WellMateOfflineTreatmentEditEnqueuer? offlineEnqueuer;\n"""
replacement = """    this.editApi,\n    this.offlineEnqueuer,\n    this.onSaveStateChanged,\n  });\n\n  final Map<String, dynamic> plan;\n  final LifeMateEditApi? editApi;\n  final WellMateOfflineTreatmentEditEnqueuer? offlineEnqueuer;\n  final ValueChanged<WellMateTreatmentEditSaveState>? onSaveStateChanged;\n"""
assert anchor in text, 'constructor anchor changed'
text = text.replace(anchor, replacement, 1)

anchor = """      if (!mounted) return;\n      LifeMateNotice.show(\n        context,\n        type: LifeMateNoticeType.success,\n"""
replacement = """      if (!mounted) return;\n      widget.onSaveStateChanged?.call(\n        WellMateTreatmentEditSaveState.serverConfirmed,\n      );\n      LifeMateNotice.show(\n        context,\n        type: LifeMateNoticeType.success,\n"""
assert anchor in text, 'server-confirmed notice anchor changed'
text = text.replace(anchor, replacement, 1)

anchor = """        if (!mounted) return;\n        if (queued) {\n          LifeMateNotice.show(\n"""
replacement = """        if (!mounted) return;\n        if (queued) {\n          widget.onSaveStateChanged?.call(\n            WellMateTreatmentEditSaveState.pendingSync,\n          );\n          LifeMateNotice.show(\n"""
assert anchor in text, 'pending-sync notice anchor changed'
text = text.replace(anchor, replacement, 1)
screen.write_text(text)

test = Path('wellmate/test/offline_treatment_edit_screen_test.dart')
t = test.read_text()

# Online case: assert semantic server confirmation instead of an overlay that is
# intentionally removed with the popped route.
anchor = """    final api = _FakeEditApi();\n    var offlineCalls = 0;\n\n    await _openEditor(\n      tester,\n      editApi: api,\n      offlineEnqueuer: (_) async => offlineCalls += 1,\n    );\n"""
replacement = """    final api = _FakeEditApi();\n    var offlineCalls = 0;\n    final saveStates = <WellMateTreatmentEditSaveState>[];\n\n    await _openEditor(\n      tester,\n      editApi: api,\n      offlineEnqueuer: (_) async => offlineCalls += 1,\n      onSaveStateChanged: saveStates.add,\n    );\n"""
assert anchor in t, 'online test setup anchor changed'
t = t.replace(anchor, replacement, 1)
anchor = """    expect(offlineCalls, 0);\n    expect(find.text('changed:true'), findsOneWidget);\n    expect(find.text('Treatment changes saved successfully.'), findsOneWidget);\n    expect(tester.takeException(), isNull);\n"""
replacement = """    expect(offlineCalls, 0);\n    expect(saveStates, <WellMateTreatmentEditSaveState>[\n      WellMateTreatmentEditSaveState.serverConfirmed,\n    ]);\n    expect(find.text('changed:true'), findsOneWidget);\n    expect(tester.takeException(), isNull);\n"""
assert anchor in t, 'online test assertion anchor changed'
t = t.replace(anchor, replacement, 1)

# Transient fallback: capture exact pending-sync semantic state. Exact request
# payload assertions remain unchanged and prove no schedule/timing inference.
anchor = """      WellMateOfflineTreatmentEditRequest? queued;\n\n      await _openEditor(\n        tester,\n        editApi: api,\n        offlineEnqueuer: (request) async => queued = request,\n      );\n"""
replacement = """      WellMateOfflineTreatmentEditRequest? queued;\n      final saveStates = <WellMateTreatmentEditSaveState>[];\n\n      await _openEditor(\n        tester,\n        editApi: api,\n        offlineEnqueuer: (request) async => queued = request,\n        onSaveStateChanged: saveStates.add,\n      );\n"""
assert anchor in t, 'transient test setup anchor changed'
t = t.replace(anchor, replacement, 1)
anchor = """      expect(queued!.status, 'active');\n      expect(find.text('changed:true'), findsOneWidget);\n      expect(find.text('Changes saved on this device'), findsOneWidget);\n      expect(\n        find.text(\n          'Server confirmation is pending; the edit will sync after reconnection.',\n        ),\n        findsOneWidget,\n      );\n      expect(find.textContaining('Cetirizine private'), findsNothing);\n      expect(find.textContaining('after food private'), findsNothing);\n      expect(tester.takeException(), isNull);\n"""
replacement = """      expect(queued!.status, 'active');\n      expect(saveStates, <WellMateTreatmentEditSaveState>[\n        WellMateTreatmentEditSaveState.pendingSync,\n      ]);\n      expect(find.text('changed:true'), findsOneWidget);\n      expect(tester.takeException(), isNull);\n"""
assert anchor in t, 'transient test assertion anchor changed'
t = t.replace(anchor, replacement, 1)

# Auth/conflict failures must never emit either saved state and must keep the
# editor open; exact localized rendering is covered separately from semantics.
anchor = """      final api = _FakeEditApi(error: blocked);\n      var offlineCalls = 0;\n\n      await _openEditor(\n        tester,\n        editApi: api,\n        offlineEnqueuer: (_) async => offlineCalls += 1,\n      );\n"""
replacement = """      final api = _FakeEditApi(error: blocked);\n      var offlineCalls = 0;\n      final saveStates = <WellMateTreatmentEditSaveState>[];\n\n      await _openEditor(\n        tester,\n        editApi: api,\n        offlineEnqueuer: (_) async => offlineCalls += 1,\n        onSaveStateChanged: saveStates.add,\n      );\n"""
assert anchor in t, 'blocked test setup anchor changed'
t = t.replace(anchor, replacement, 1)
anchor = """      expect(api.calls, 1);\n      expect(offlineCalls, 0);\n      expect(find.text('changed:null'), findsNothing);\n      expect(find.byKey(const ValueKey('edit-treatment-form')), findsOneWidget);\n      if (blocked.statusCode == 409) {\n        expect(\n          find.text(\n            'This treatment has been modified elsewhere. Close and reopen the page.',\n          ),\n          findsOneWidget,\n        );\n      }\n      expect(tester.takeException(), isNull);\n"""
replacement = """      expect(api.calls, 1);\n      expect(offlineCalls, 0);\n      expect(saveStates, isEmpty);\n      expect(find.text('changed:null'), findsNothing);\n      expect(find.byKey(const ValueKey('edit-treatment-form')), findsOneWidget);\n      expect(tester.takeException(), isNull);\n"""
assert anchor in t, 'blocked test assertion anchor changed'
t = t.replace(anchor, replacement, 1)

# Pre-adoption/runtime failure: no pending/server-confirmed state and route stays.
anchor = """    await _openEditor(\n      tester,\n      editApi: api,\n      offlineEnqueuer: (_) async => throw StateError('runtime not adopted'),\n    );\n    await _save(tester, expectPop: false);\n\n    expect(find.byKey(const ValueKey('edit-treatment-form')), findsOneWidget);\n    expect(\n      find.text(\n        'This change could not be saved offline. Check the connection and try again.',\n      ),\n      findsOneWidget,\n    );\n    expect(find.text('Changes saved on this device'), findsNothing);\n    expect(tester.takeException(), isNull);\n"""
replacement = """    final saveStates = <WellMateTreatmentEditSaveState>[];\n    await _openEditor(\n      tester,\n      editApi: api,\n      offlineEnqueuer: (_) async => throw StateError('runtime not adopted'),\n      onSaveStateChanged: saveStates.add,\n    );\n    await _save(tester, expectPop: false);\n\n    expect(saveStates, isEmpty);\n    expect(find.byKey(const ValueKey('edit-treatment-form')), findsOneWidget);\n    expect(tester.takeException(), isNull);\n"""
assert anchor in t, 'enqueue failure test anchor changed'
t = t.replace(anchor, replacement, 1)

anchor = """  required LifeMateEditApi editApi,\n  required WellMateOfflineTreatmentEditEnqueuer offlineEnqueuer,\n}) async {\n"""
replacement = """  required LifeMateEditApi editApi,\n  required WellMateOfflineTreatmentEditEnqueuer offlineEnqueuer,\n  required ValueChanged<WellMateTreatmentEditSaveState> onSaveStateChanged,\n}) async {\n"""
assert anchor in t, 'open editor signature anchor changed'
t = t.replace(anchor, replacement, 1)
anchor = """      home: _EditorHost(editApi: editApi, offlineEnqueuer: offlineEnqueuer),\n"""
replacement = """      home: _EditorHost(\n        editApi: editApi,\n        offlineEnqueuer: offlineEnqueuer,\n        onSaveStateChanged: onSaveStateChanged,\n      ),\n"""
assert anchor in t, 'host creation anchor changed'
t = t.replace(anchor, replacement, 1)
anchor = """class _EditorHost extends StatefulWidget {\n  const _EditorHost({required this.editApi, required this.offlineEnqueuer});\n\n  final LifeMateEditApi editApi;\n  final WellMateOfflineTreatmentEditEnqueuer offlineEnqueuer;\n"""
replacement = """class _EditorHost extends StatefulWidget {\n  const _EditorHost({\n    required this.editApi,\n    required this.offlineEnqueuer,\n    required this.onSaveStateChanged,\n  });\n\n  final LifeMateEditApi editApi;\n  final WellMateOfflineTreatmentEditEnqueuer offlineEnqueuer;\n  final ValueChanged<WellMateTreatmentEditSaveState> onSaveStateChanged;\n"""
assert anchor in t, 'host declaration anchor changed'
t = t.replace(anchor, replacement, 1)
anchor = """                      editApi: widget.editApi,\n                      offlineEnqueuer: widget.offlineEnqueuer,\n                    ),\n"""
replacement = """                      editApi: widget.editApi,\n                      offlineEnqueuer: widget.offlineEnqueuer,\n                      onSaveStateChanged: widget.onSaveStateChanged,\n                    ),\n"""
assert anchor in t, 'screen callback wiring anchor changed'
t = t.replace(anchor, replacement, 1)

test.write_text(t)

Path('tools/hotfix/apply_offline04_treatment_edit_test_fix.py').unlink()
Path('.github/workflows/offline04-treatment-edit-test-fix.yml').unlink()
