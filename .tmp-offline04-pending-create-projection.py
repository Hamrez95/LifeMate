from pathlib import Path

native = Path('packages/lifemate_client/lib/src/shared_offline_runtime_native.dart')
text = native.read_text()
anchor = """  Future<int> pendingMutationCount() async {
    _requireOpen();
    await importLegacyPending();
    final mutations = await _outbox.list(namespace: _localNamespace);
    return mutations.where(_isPendingForReplay).length;
  }

"""
addition = anchor + """  /// Returns only locally pending bounded treatment-create payloads from the
  /// canonical protected Person-scoped outbox. This is projection input for
  /// native UI continuity; it does not synthesize server IDs or occurrence
  /// confirmation and never reads another Person namespace.
  Future<List<Map<String, dynamic>>> pendingTreatmentCreates() async {
    _requireOpen();
    await importLegacyPending();
    final mutations = await _outbox.list(namespace: _localNamespace);
    final values = <Map<String, dynamic>>[];
    for (final mutation in mutations) {
      if (mutation.domain != LifeMateMutationDomain.treatment ||
          mutation.method != 'POST' ||
          mutation.endpointPath != '/api/v1/treatment-plans' ||
          !mutation.sourceKey.startsWith('pending-treatment-create:') ||
          !_isPendingForReplay(mutation)) {
        continue;
      }
      values.add(<String, dynamic>{
        ...mutation.payload,
        'clientRequestId': mutation.mutationId,
        'pendingSync': true,
        'createdAtUtc': mutation.createdAtUtc.toIso8601String(),
      });
    }
    return List<Map<String, dynamic>>.unmodifiable(values);
  }

"""
if anchor not in text:
    raise SystemExit('native pendingMutationCount anchor missing')
native.write_text(text.replace(anchor, addition, 1))

client = Path('packages/lifemate_client/lib/src/durable_lifemate_api_client.dart')
text = client.read_text()
anchor = """  Future<void> enqueueOfflineTreatmentPlanCreate({
"""
method = """  Future<List<Map<String, dynamic>>> pendingOfflineTreatmentPlanCreates() async {
    final runtime = _activeSharedRuntime();
    if (runtime == null) {
      throw StateError(
        'Canonical shared offline runtime must be adopted before treatment projection reads.',
      );
    }
    return runtime.pendingTreatmentCreates();
  }

"""
if anchor not in text:
    raise SystemExit('durable client create anchor missing')
client.write_text(text.replace(anchor, method + anchor, 1))

web = Path('packages/lifemate_client/lib/src/durable_lifemate_api_client_web.dart')
text = web.read_text()
anchor = """  Future<void> enqueueOfflineTreatmentPlanCreate({
"""
method = """  Future<List<Map<String, dynamic>>> pendingOfflineTreatmentPlanCreates() =>
      Future<List<Map<String, dynamic>>>.error(
        UnsupportedError(
          'Protected offline health execution is unavailable on web.',
        ),
      );

"""
if anchor not in text:
    raise SystemExit('web create anchor missing')
web.write_text(text.replace(anchor, method + anchor, 1))

test = Path('packages/lifemate_client/test/durable_treatment_create_enqueue_test.dart')
text = test.read_text()
anchor = """    expect(stored?.payload['recurrenceStartLocalTime'], isNull);

    final otherPerson = LifeMateLocalNamespace(
"""
replacement = """    expect(stored?.payload['recurrenceStartLocalTime'], isNull);

    final pendingCreates = await api.pendingOfflineTreatmentPlanCreates();
    expect(pendingCreates, hasLength(1));
    expect(pendingCreates.single['clientRequestId'], requestId);
    expect(pendingCreates.single['medicationId'], medicationId);
    expect(pendingCreates.single['doseText'], '1 tablet');
    expect(pendingCreates.single['pendingSync'], isTrue);
    expect(pendingCreates.single['schedules'], <Map<String, String>>[
      <String, String>{'dayOfWeek': 'monday', 'localTime': '08:00'},
      <String, String>{'dayOfWeek': 'wednesday', 'localTime': '16:00'},
    ]);

    final otherPerson = LifeMateLocalNamespace(
"""
if anchor not in text:
    raise SystemExit('test anchor missing')
text = text.replace(anchor, replacement, 1)

anchor2 = """  test('treatment create enqueue fails before canonical runtime adoption', () {
"""
test2 = """  test('pending treatment create projection fails before runtime adoption', () {
    final api = DurableLifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'token',
      accountId: () => legacyAccountId,
    );

    expect(api.pendingOfflineTreatmentPlanCreates(), throwsStateError);
    api.close();
  });

"""
if anchor2 not in text:
    raise SystemExit('second test anchor missing')
test.write_text(text.replace(anchor2, test2 + anchor2, 1))
