from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    if new in text:
        return
    if old not in text:
        raise SystemExit(f'expected snippet not found: {path}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')

replace_once(
    'packages/lifemate_client/lib/src/women_episode_offline_outbox.dart',
    '''  Future<void> enqueueUpdate({
''',
    '''  Future<void> cancelPendingCreate({required String mutationId}) async {
    _requireOpen();
    final current = await _outbox.get(
      namespace: _namespace,
      mutationId: mutationId,
    );
    if (current == null ||
        current.domain != LifeMateMutationDomain.womenHealth ||
        current.sourceKey != 'women-episode-create:${current.mutationId}' ||
        current.method != 'POST' ||
        current.endpointPath != _createEndpoint ||
        current.expectedRevision != null ||
        current.timeZone != _timeZone ||
        current.state != LifeMateMutationSyncState.pending ||
        current.errorClass != LifeMateMutationErrorClass.none ||
        current.attemptCount != 0 ||
        current.nextAttemptAtUtc != null) {
      throw StateError(
        'Only an untouched pending Women episode create can be cancelled.',
      );
    }
    await _outbox.acknowledge(
      namespace: _namespace,
      mutationId: current.mutationId,
    );
  }

  Future<void> enqueueUpdate({
''',
)

replace_once(
    'wellmate/lib/screens/women_calendar/women_episode_offline_bridge_native.dart',
    '''  Future<void> enqueueUpdate({
''',
    '''  Future<void> cancelPendingCreate({required String mutationId}) =>
      _outbox.cancelPendingCreate(mutationId: mutationId);

  Future<void> enqueueUpdate({
''',
)
replace_once(
    'wellmate/lib/screens/women_calendar/women_episode_offline_bridge_web.dart',
    '''  Future<void> enqueueUpdate({
''',
    '''  Future<void> cancelPendingCreate({required String mutationId}) =>
      throw UnsupportedError(
        'Protected Women episode persistence is unavailable on web.',
      );

  Future<void> enqueueUpdate({
''',
)

# Prefer the namespace already adopted by DurableLifeMateApiClient before doing
# a capabilities request. This is what keeps mutation fallback usable after a
# device that was online loses connectivity during the session.
path = 'wellmate/lib/screens/women_calendar/women_episode_offline_bridge_native.dart'
target = ROOT / path
text = target.read_text(encoding='utf-8')
old = '''    final capabilities = await apiClient.getCapabilities();
    final personId = capabilities.selfPersonId?.trim();
    final accountId = capabilities.accountId.trim();
    if (personId == null || personId.isEmpty || accountId.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 409,
        code: 'identity_person_mapping_missing',
        message: 'The LifeMate person mapping is unavailable.',
      );
    }

    final config = AppConfig.fromEnvironment();
    final localNamespace = LifeMateLocalNamespace(
      environmentId: config.apiBaseUri.toString(),
      accountId: accountId,
      personId: personId,
    );
'''
new = '''    final config = AppConfig.fromEnvironment();
    LifeMateLocalNamespace? localNamespace;
    if (apiClient is DurableLifeMateApiClient) {
      final active = apiClient.activeOfflineNamespace;
      if (active != null) {
        localNamespace = LifeMateLocalNamespace(
          environmentId: active.environmentId,
          accountId: active.accountId,
          personId: active.personId,
        );
      }
    }
    if (localNamespace == null) {
      final capabilities = await apiClient.getCapabilities();
      final personId = capabilities.selfPersonId?.trim();
      final accountId = capabilities.accountId.trim();
      if (personId == null || personId.isEmpty || accountId.isEmpty) {
        throw const LifeMateApiException(
          statusCode: 409,
          code: 'identity_person_mapping_missing',
          message: 'The LifeMate person mapping is unavailable.',
        );
      }
      localNamespace = LifeMateLocalNamespace(
        environmentId: config.apiBaseUri.toString(),
        accountId: accountId,
        personId: personId,
      );
    }
'''
if new not in text:
    if old not in text:
        raise SystemExit(f'identity snippet not found: {path}')
    text = text.replace(old, new, 1)
    target.write_text(text, encoding='utf-8')

# Projection tests lock no-fabricated-ID and conflict/rejected behavior.
test_path = ROOT / 'packages/lifemate_client/test/women_episode_offline_outbox_test.dart'
text = test_path.read_text(encoding='utf-8')
if "projection exposes pending create without fabricating a server id" not in text:
    insert = r'''

  test('projection exposes pending create without fabricating a server id', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final adapter = WomenEpisodeOfflineOutbox.forTesting(
      store: store,
      namespace: owner,
      timeZone: 'Asia/Tehran',
    );
    addTearDown(() {
      adapter.close();
      store.close();
    });

    await adapter.enqueueCreate(
      mutationId: 'women-episode-client-0100',
      startedOn: DateTime(2026, 9, 6),
      privateNotes: 'private',
      createdAtUtc: DateTime.utc(2026, 9, 6, 7),
    );
    final projected = await adapter.project(const <Map<String, dynamic>>[]);

    expect(projected, hasLength(1));
    expect(projected.single.containsKey('id'), isFalse);
    expect(projected.single['localMutationId'], 'women-episode-client-0100');
    expect(projected.single['pendingSync'], isTrue);
    expect(projected.single['serverConfirmed'], isFalse);
    expect(projected.single.containsKey('relationshipId'), isFalse);
  });

  test('projection overlays pending update but preserves canonical id', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final adapter = WomenEpisodeOfflineOutbox.forTesting(
      store: store,
      namespace: owner,
      timeZone: 'Asia/Tehran',
    );
    addTearDown(() {
      adapter.close();
      store.close();
    });

    await adapter.enqueueUpdate(
      mutationId: 'women-episode-client-0101',
      episodeId: 'episode_101',
      version: 3,
      startedOn: DateTime(2026, 9, 2),
      endedOn: DateTime(2026, 9, 5),
      privateNotes: 'local edit',
      createdAtUtc: DateTime.utc(2026, 9, 6, 7),
    );
    final projected = await adapter.project(<Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'episode_101',
        'startedOn': '2026-09-01',
        'endedOn': null,
        'privateNotes': 'server',
        'version': 3,
      },
    ]);

    expect(projected.single['id'], 'episode_101');
    expect(projected.single['startedOn'], '2026-09-02');
    expect(projected.single['endedOn'], '2026-09-05');
    expect(projected.single['privateNotes'], 'local edit');
    expect(projected.single['pendingSync'], isTrue);
    expect(projected.single['serverConfirmed'], isFalse);
  });

  test('conflict projection keeps canonical episode and surfaces conflict', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
    );
    final adapter = WomenEpisodeOfflineOutbox.forTesting(
      store: store,
      namespace: owner,
      timeZone: 'Asia/Tehran',
    );
    final outbox = LifeMateLocalMutationOutbox(store: store);
    addTearDown(() {
      adapter.close();
      store.close();
    });

    await adapter.enqueueUpdate(
      mutationId: 'women-episode-client-0102',
      episodeId: 'episode_102',
      version: 2,
      startedOn: DateTime(2026, 9, 2),
      privateNotes: 'local edit',
      createdAtUtc: DateTime.utc(2026, 9, 6, 7),
    );
    await outbox.markConflict(
      namespace: owner,
      mutationId: 'women-episode-client-0102',
    );
    final projected = await adapter.project(<Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'episode_102',
        'startedOn': '2026-09-01',
        'endedOn': null,
        'privateNotes': 'server wins until resolution',
        'version': 3,
      },
    ]);

    expect(projected.single['startedOn'], '2026-09-01');
    expect(projected.single['privateNotes'], 'server wins until resolution');
    expect(projected.single['syncConflict'], isTrue);
    expect(projected.single['serverConfirmed'], isTrue);
  });

  test('pending create cancellation is fail closed after replay begins', () async {
    final store = LifeMateLocalHealthStore.forTesting(
      database: sqlite3.openInMemory(),
      keyBytes: key,
      now: () => DateTime.utc(2026, 9, 6, 8),
    );
    final adapter = WomenEpisodeOfflineOutbox.forTesting(
      store: store,
      namespace: owner,
      timeZone: 'Asia/Tehran',
    );
    final outbox = LifeMateLocalMutationOutbox(
      store: store,
      now: () => DateTime.utc(2026, 9, 6, 8),
    );
    addTearDown(() {
      adapter.close();
      store.close();
    });

    await adapter.enqueueCreate(
      mutationId: 'women-episode-client-0103',
      startedOn: DateTime(2026, 9, 6),
    );
    await outbox.markRetry(
      namespace: owner,
      mutationId: 'women-episode-client-0103',
      errorClass: LifeMateMutationErrorClass.transport,
    );
    await expectLater(
      adapter.cancelPendingCreate(mutationId: 'women-episode-client-0103'),
      throwsStateError,
    );
    expect(
      await outbox.get(
        namespace: owner,
        mutationId: 'women-episode-client-0103',
      ),
      isNotNull,
    );
  });
'''
    closing = text.rfind('\n}')
    if closing < 0:
        raise SystemExit('test closing brace not found')
    text = text[:closing] + insert + text[closing:]
    test_path.write_text(text, encoding='utf-8')
