from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    if new in text:
        return
    if old not in text:
        raise SystemExit(f'expected snippet not found: {path}')
    write(path, text.replace(old, new, 1))


def replace_between(path: str, start: str, end: str, replacement: str) -> None:
    text = read(path)
    if replacement.strip() in text:
        return
    a = text.find(start)
    if a < 0:
        raise SystemExit(f'start marker missing: {path}: {start}')
    b = text.find(end, a)
    if b < 0:
        raise SystemExit(f'end marker missing: {path}: {end}')
    write(path, text[:a] + replacement + text[b:])


# Stable idempotency identity must survive an uncertain online response and be
# reused by the durable replay instead of generating a second logical action.
replace_once(
    'packages/lifemate_client/lib/src/lifemate_api_client.dart',
    '''  Future<Map<String, dynamic>> createWomenCalendarEpisode({
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
  }) async => _asObject(
    await _send(
      'POST',
      '/api/v1/women-calendar/episodes',
      body: {
        'startedOn': _date(startedOn),
        'endedOn': endedOn == null ? null : _date(endedOn),
        'privateNotes': _emptyToNull(privateNotes),
      },
    ),
  );
''',
    '''  Future<Map<String, dynamic>> createWomenCalendarEpisode({
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
    String? clientRequestId,
  }) async => _asObject(
    await _send(
      'POST',
      '/api/v1/women-calendar/episodes',
      body: {
        'startedOn': _date(startedOn),
        'endedOn': endedOn == null ? null : _date(endedOn),
        'privateNotes': _emptyToNull(privateNotes),
      },
      retryable: true,
      idempotencyKey: clientRequestId,
    ),
  );
''',
)
replace_once(
    'packages/lifemate_client/lib/src/lifemate_api_client.dart',
    '''  Future<Map<String, dynamic>> updateWomenCalendarEpisode({
    required String episodeId,
    required int version,
    required DateTime startedOn,
    required DateTime? endedOn,
    String? privateNotes,
  }) async => _asObject(
    await _send(
      'PATCH',
      '/api/v1/women-calendar/episodes/$episodeId',
      body: {
        'version': version,
        'startedOn': _date(startedOn),
        'endedOn': endedOn == null ? null : _date(endedOn),
        'privateNotes': _emptyToNull(privateNotes),
      },
    ),
  );
''',
    '''  Future<Map<String, dynamic>> updateWomenCalendarEpisode({
    required String episodeId,
    required int version,
    required DateTime startedOn,
    required DateTime? endedOn,
    String? privateNotes,
    String? clientRequestId,
  }) async => _asObject(
    await _send(
      'PATCH',
      '/api/v1/women-calendar/episodes/$episodeId',
      body: {
        'version': version,
        'startedOn': _date(startedOn),
        'endedOn': endedOn == null ? null : _date(endedOn),
        'privateNotes': _emptyToNull(privateNotes),
      },
      retryable: true,
      idempotencyKey: clientRequestId,
    ),
  );
''',
)

# Expose only the already-adopted canonical namespace. This contains no health
# values and lets an offline mutation use the runtime adopted during bootstrap
# without a second network capabilities lookup after connectivity is lost.
replace_once(
    'packages/lifemate_client/lib/src/durable_lifemate_api_client.dart',
    '''  String? _sharedRuntimeLegacyAccountId;

  @override
''',
    '''  String? _sharedRuntimeLegacyAccountId;

  LifeMateOfflineNamespace? get activeOfflineNamespace =>
      _activeSharedRuntime()?.namespace;

  @override
''',
)

screen = 'wellmate/lib/screens/women_calendar/women_calendar_screen.dart'
replace_once(
    screen,
    "import 'women_calendar_month_card.dart';\n",
    "import 'women_calendar_month_card.dart';\n"
    "import 'women_episode_dashboard_loader.dart';\n"
    "import 'women_episode_offline_bridge.dart';\n"
    "import 'women_episode_offline_policy.dart';\n",
)
replace_once(
    screen,
    '''      final dashboard = await api.getWomenCalendarDashboard(
        fromDate: now.subtract(const Duration(days: 89)),
        toDate: now,
      );
''',
    '''      final dashboard = await WomenEpisodeDashboardLoader(api).load(
        fromDate: now.subtract(const Duration(days: 89)),
        toDate: now,
      );
''',
)

create_method = r'''  Future<void> _createEpisode() async {
    if (_saving) return;
    final draft = await _showEpisodeEditor();
    if (draft == null) return;
    setState(() => _saving = true);
    final api = context.read<LifeMateApiClient>();
    final clientRequestId = LifeMateApiClient.createClientRequestId();
    try {
      await api.createWomenCalendarEpisode(
        startedOn: draft.startedOn,
        endedOn: draft.endedOn,
        privateNotes: draft.privateNotes,
        clientRequestId: clientRequestId,
      );
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: LifeMateRuntimeLocale.select(fa: 'دوره ثبت شد', en: 'Period saved'),
        message: LifeMateRuntimeLocale.select(
          fa: 'بازه دوره و یادداشت خصوصی ذخیره شد.',
          en: 'Period dates and private note were saved.',
        ),
      );
      await _load();
      await widget.onProfileChanged?.call();
    } on LifeMateApiException catch (error) {
      if (WomenEpisodeOfflinePolicy.canQueueAfter(error)) {
        WomenEpisodeOfflineBridge? offline;
        try {
          offline = await WomenEpisodeOfflineBridge.open(apiClient: api);
          await offline.enqueueCreate(
            mutationId: clientRequestId,
            startedOn: draft.startedOn,
            endedOn: draft.endedOn,
            privateNotes: draft.privateNotes,
          );
          if (!mounted) return;
          setState(() {
            _episodes = <Map<String, dynamic>>[
              ..._episodes,
              <String, dynamic>{
                'startedOn': _dateKey(draft.startedOn),
                'endedOn': draft.endedOn == null ? null : _dateKey(draft.endedOn!),
                'privateNotes': draft.privateNotes?.trim(),
                'localMutationId': clientRequestId,
                'version': 0,
                'pendingSync': true,
                'serverConfirmed': false,
              },
            ];
          });
          LifeMateNotice.show(
            context,
            type: LifeMateNoticeType.success,
            title: LifeMateRuntimeLocale.select(
              fa: 'روی این دستگاه ذخیره شد',
              en: 'Saved on this device',
            ),
            message: LifeMateRuntimeLocale.select(
              fa: 'این ثبت خصوصی است و بعد از اتصال دوباره همگام می‌شود.',
              en: 'This private period entry will sync after reconnection.',
            ),
          );
          return;
        } on UnsupportedError {
          // Web deliberately has no protected PHI persistence.
        } on LifeMateApiException {
          // Protected identity/runtime unavailable; preserve the original error.
        } on StateError {
          // Protected runtime unavailable; preserve the original error.
        } finally {
          offline?.close();
        }
      }
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: LifeMateRuntimeLocale.select(
          fa: 'ثبت دوره انجام نشد',
          en: 'Period could not be saved',
        ),
        message: error.code == 'women_calendar_episode_overlap'
            ? LifeMateRuntimeLocale.select(
                fa: 'این بازه با یک ثبت قبلی هم‌پوشانی دارد.',
                en: 'This range overlaps an existing period entry.',
              )
            : LifeMateRuntimeLocale.select(
                fa: 'تغییرات ثبت دوره ذخیره نشد.',
                en: 'Period changes were not saved.',
              ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

'''
replace_between(screen, '  Future<void> _createEpisode() async {\n', '  Future<void> _finishPeriodToday() async {\n', create_method)

finish_method = r'''  Future<void> _finishPeriodToday() async {
    final episode = _openEpisode;
    if (episode == null || _saving) return;
    final startedOn = DateTime.parse(episode['startedOn'].toString());
    final endedOn = DateTime.now();
    final localMutationId = episode['localMutationId']?.toString().trim();
    final canonicalId = episode['id']?.toString().trim();
    setState(() => _saving = true);
    final api = context.read<LifeMateApiClient>();
    try {
      if (localMutationId != null &&
          localMutationId.isNotEmpty &&
          (canonicalId == null || canonicalId.isEmpty)) {
        WomenEpisodeOfflineBridge? offline;
        try {
          offline = await WomenEpisodeOfflineBridge.open(apiClient: api);
          await offline.coalescePendingCreate(
            mutationId: localMutationId,
            startedOn: startedOn,
            endedOn: endedOn,
            privateNotes: episode['privateNotes']?.toString(),
          );
          if (!mounted) return;
          _replaceEpisodeLocally(episode, <String, dynamic>{
            ...episode,
            'endedOn': _dateKey(endedOn),
            'pendingSync': true,
            'serverConfirmed': false,
          });
          _showEpisodePendingNotice();
          return;
        } finally {
          offline?.close();
        }
      }

      if (canonicalId == null || canonicalId.isEmpty) {
        throw StateError('Canonical Women episode ID is unavailable.');
      }
      final clientRequestId = LifeMateApiClient.createClientRequestId();
      try {
        await api.updateWomenCalendarEpisode(
          episodeId: canonicalId,
          version: episode['version'] is int ? episode['version'] as int : 1,
          startedOn: startedOn,
          endedOn: endedOn,
          privateNotes: episode['privateNotes']?.toString(),
          clientRequestId: clientRequestId,
        );
      } on LifeMateApiException catch (error) {
        if (!WomenEpisodeOfflinePolicy.canQueueAfter(error)) rethrow;
        WomenEpisodeOfflineBridge? offline;
        try {
          offline = await WomenEpisodeOfflineBridge.open(apiClient: api);
          await offline.enqueueUpdate(
            mutationId: clientRequestId,
            episodeId: canonicalId,
            version: episode['version'] is int ? episode['version'] as int : 1,
            startedOn: startedOn,
            endedOn: endedOn,
            privateNotes: episode['privateNotes']?.toString(),
          );
        } catch (_) {
          rethrow;
        } finally {
          offline?.close();
        }
        if (!mounted) return;
        _replaceEpisodeLocally(episode, <String, dynamic>{
          ...episode,
          'endedOn': _dateKey(endedOn),
          'localMutationId': clientRequestId,
          'pendingSync': true,
          'serverConfirmed': false,
        });
        _showEpisodePendingNotice();
        return;
      }
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: LifeMateRuntimeLocale.select(
          fa: 'پایان دوره ثبت شد',
          en: 'Period end saved',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: 'پایان دوره برای امروز ذخیره شد.',
          en: 'The period end was saved for today.',
        ),
      );
      await _load();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      _showEpisodeWriteError(error);
      await _load();
    } on StateError {
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: LifeMateRuntimeLocale.select(
          fa: 'ثبت دوره انجام نشد',
          en: 'Period could not be saved',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: 'ثبت محلی هنوز در حال همگام‌سازی است. دوباره تلاش کن.',
          en: 'The local entry is still syncing. Try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

'''
replace_between(screen, '  Future<void> _finishPeriodToday() async {\n', '  Future<void> _editEpisode(Map<String, dynamic> episode) async {\n', finish_method)

edit_method = r'''  Future<void> _editEpisode(Map<String, dynamic> episode) async {
    if (_saving) return;
    final draft = await _showEpisodeEditor(episode: episode);
    if (draft == null) return;
    if (draft.deleteRequested) {
      await _deleteEpisode(episode);
      return;
    }
    final localMutationId = episode['localMutationId']?.toString().trim();
    final canonicalId = episode['id']?.toString().trim();
    setState(() => _saving = true);
    final api = context.read<LifeMateApiClient>();
    try {
      if (localMutationId != null &&
          localMutationId.isNotEmpty &&
          (canonicalId == null || canonicalId.isEmpty)) {
        WomenEpisodeOfflineBridge? offline;
        try {
          offline = await WomenEpisodeOfflineBridge.open(apiClient: api);
          await offline.coalescePendingCreate(
            mutationId: localMutationId,
            startedOn: draft.startedOn,
            endedOn: draft.endedOn,
            privateNotes: draft.privateNotes,
          );
          if (!mounted) return;
          _replaceEpisodeLocally(episode, <String, dynamic>{
            ...episode,
            'startedOn': _dateKey(draft.startedOn),
            'endedOn': draft.endedOn == null ? null : _dateKey(draft.endedOn!),
            'privateNotes': draft.privateNotes?.trim(),
            'pendingSync': true,
            'serverConfirmed': false,
          });
          _showEpisodePendingNotice();
          return;
        } finally {
          offline?.close();
        }
      }
      if (canonicalId == null || canonicalId.isEmpty) {
        throw StateError('Canonical Women episode ID is unavailable.');
      }
      final clientRequestId = LifeMateApiClient.createClientRequestId();
      try {
        await api.updateWomenCalendarEpisode(
          episodeId: canonicalId,
          version: episode['version'] is int ? episode['version'] as int : 1,
          startedOn: draft.startedOn,
          endedOn: draft.endedOn,
          privateNotes: draft.privateNotes,
          clientRequestId: clientRequestId,
        );
      } on LifeMateApiException catch (error) {
        if (!WomenEpisodeOfflinePolicy.canQueueAfter(error)) rethrow;
        WomenEpisodeOfflineBridge? offline;
        try {
          offline = await WomenEpisodeOfflineBridge.open(apiClient: api);
          await offline.enqueueUpdate(
            mutationId: clientRequestId,
            episodeId: canonicalId,
            version: episode['version'] is int ? episode['version'] as int : 1,
            startedOn: draft.startedOn,
            endedOn: draft.endedOn,
            privateNotes: draft.privateNotes,
          );
        } catch (_) {
          rethrow;
        } finally {
          offline?.close();
        }
        if (!mounted) return;
        _replaceEpisodeLocally(episode, <String, dynamic>{
          ...episode,
          'startedOn': _dateKey(draft.startedOn),
          'endedOn': draft.endedOn == null ? null : _dateKey(draft.endedOn!),
          'privateNotes': draft.privateNotes?.trim(),
          'localMutationId': clientRequestId,
          'pendingSync': true,
          'serverConfirmed': false,
        });
        _showEpisodePendingNotice();
        return;
      }
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: LifeMateRuntimeLocale.select(
          fa: 'ثبت دوره اصلاح شد',
          en: 'Period entry updated',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: 'تغییرات تاریخچه دوره ذخیره شد.',
          en: 'Period history changes were saved.',
        ),
      );
      await _load();
      await widget.onProfileChanged?.call();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      _showEpisodeWriteError(error);
      await _load();
    } on StateError {
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: LifeMateRuntimeLocale.select(
          fa: 'ویرایش انجام نشد',
          en: 'Edit could not be saved',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: 'ثبت محلی وارد مرحله همگام‌سازی شده و فعلاً قابل تغییر نیست.',
          en: 'This local entry has begun syncing and cannot be changed yet.',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

'''
replace_between(screen, '  Future<void> _editEpisode(Map<String, dynamic> episode) async {\n', '  Future<void> _deleteEpisode(Map<String, dynamic> episode) async {\n', edit_method)

# Local-only pending creates may be safely cancelled only while replay has not
# started. The bridge validates that invariant before removing the outbox item.
replace_once(
    screen,
    '''    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await context.read<LifeMateApiClient>().deleteWomenCalendarEpisode(
        episodeId: episode['id'].toString(),
      );
''',
    '''    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final localMutationId = episode['localMutationId']?.toString().trim();
    final canonicalId = episode['id']?.toString().trim();
    try {
      if (localMutationId != null &&
          localMutationId.isNotEmpty &&
          (canonicalId == null || canonicalId.isEmpty)) {
        WomenEpisodeOfflineBridge? offline;
        try {
          offline = await WomenEpisodeOfflineBridge.open(
            apiClient: context.read<LifeMateApiClient>(),
          );
          await offline.cancelPendingCreate(mutationId: localMutationId);
        } finally {
          offline?.close();
        }
        if (!mounted) return;
        setState(() => _episodes = _episodes.where((item) => !identical(item, episode)).toList(growable: false));
        return;
      }
      if (canonicalId == null || canonicalId.isEmpty) {
        throw StateError('Canonical Women episode ID is unavailable.');
      }
      await context.read<LifeMateApiClient>().deleteWomenCalendarEpisode(
        episodeId: canonicalId,
      );
''',
)

# Add compact helpers before the editor. They expose pending/conflict state in
# user feedback without placing PHI in logs or analytics.
replace_once(
    screen,
    '''  Future<_EpisodeDraft?> _showEpisodeEditor({
''',
    '''  void _replaceEpisodeLocally(
    Map<String, dynamic> current,
    Map<String, dynamic> replacement,
  ) {
    setState(() {
      _episodes = _episodes
          .map((item) => identical(item, current) ? replacement : item)
          .toList(growable: false);
    });
  }

  void _showEpisodePendingNotice() {
    LifeMateNotice.show(
      context,
      type: LifeMateNoticeType.success,
      title: LifeMateRuntimeLocale.select(
        fa: 'روی این دستگاه ذخیره شد',
        en: 'Saved on this device',
      ),
      message: LifeMateRuntimeLocale.select(
        fa: 'این تغییر خصوصی است و پس از اتصال دوباره همگام می‌شود.',
        en: 'This private change will sync after reconnection.',
      ),
    );
  }

  void _showEpisodeWriteError(LifeMateApiException error) {
    LifeMateNotice.show(
      context,
      type: LifeMateNoticeType.error,
      title: LifeMateRuntimeLocale.select(
        fa: 'ثبت دوره انجام نشد',
        en: 'Period could not be saved',
      ),
      message: error.code == 'stale_women_calendar_episode'
          ? LifeMateRuntimeLocale.select(
              fa: 'این ثبت تغییر کرده است؛ اطلاعات تازه شد و می‌توانی دوباره تلاش کنی.',
              en: 'This entry changed on the server. Refresh and try again.',
            )
          : error.code == 'women_calendar_episode_overlap'
          ? LifeMateRuntimeLocale.select(
              fa: 'این بازه با یک ثبت قبلی هم‌پوشانی دارد.',
              en: 'This range overlaps an existing period entry.',
            )
          : LifeMateRuntimeLocale.select(
              fa: 'تغییرات ثبت دوره ذخیره نشد.',
              en: 'Period changes were not saved.',
            ),
    );
  }

  Future<_EpisodeDraft?> _showEpisodeEditor({
''',
)

# Test the exact request identity contract at the client boundary.
test_path = 'packages/lifemate_client/test/women_calendar_api_client_test.dart'
replace_once(
    test_path,
    '''        privateNotes: '  یادداشت خصوصی اصلاح‌شده  ',
      );

      expect(observed.method, 'PATCH');
''',
    '''        privateNotes: '  یادداشت خصوصی اصلاح‌شده  ',
        clientRequestId: 'women-episode-update-0001',
      );

      expect(observed.method, 'PATCH');
''',
)
replace_once(
    test_path,
    '''      expect(observed.headers['authorization'], 'Bearer access-token');
      expect(jsonDecode(observed.body), {
''',
    '''      expect(observed.headers['authorization'], 'Bearer access-token');
      expect(observed.headers['idempotency-key'], 'women-episode-update-0001');
      expect(jsonDecode(observed.body), {
''',
)

# A create must use the caller-provided identity too.
text = read(test_path)
marker = "void main() {\n"
if "women calendar episode create reuses caller idempotency identity" not in text:
    insertion = r'''  test('women calendar episode create reuses caller idempotency identity', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': 'episode-created',
            'startedOn': '2026-09-06',
            'endedOn': null,
            'privateNotes': null,
            'version': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.createWomenCalendarEpisode(
      startedOn: DateTime(2026, 9, 6),
      clientRequestId: 'women-episode-create-0001',
    );

    expect(observed.method, 'POST');
    expect(observed.url.path, '/api/v1/women-calendar/episodes');
    expect(observed.headers['idempotency-key'], 'women-episode-create-0001');
  });

'''
    write(test_path, text.replace(marker, marker + insertion, 1))
