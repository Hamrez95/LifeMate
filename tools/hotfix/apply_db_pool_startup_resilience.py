from pathlib import Path
import re


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f"anchor not found in {path}: {old[:160]!r}")
    file.write_text(text.replace(old, new, 1))


def regex_once(path: str, pattern: str, replacement: str) -> None:
    file = Path(path)
    text = file.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"pattern count {count} in {path}: {pattern}")
    file.write_text(updated)


edge = Path("supabase/functions/lifemate-api")
(edge / "database_client.ts").write_text(
    '''import postgres from "postgres";

export type LifeMateSql = ReturnType<typeof postgres>;

const clients = new Map<string, LifeMateSql>();

/// Every Edge isolate shares one deliberately small postgres.js pool across all
/// LifeMate stores. Five independent max=2 pools previously allowed a normal
/// application startup to exhaust the direct database connection allowance.
export function getLifeMateSql(databaseUrl: string): LifeMateSql {
  const existing = clients.get(databaseUrl);
  if (existing) return existing;

  const client = postgres(databaseUrl, {
    max: 1,
    idle_timeout: 5,
    connect_timeout: 10,
    prepare: false,
  });
  clients.set(databaseUrl, client);
  return client;
}

export function isPostgresUnavailable(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const value = error as Record<string, unknown>;
  const code = String(value.code ?? "");
  const message = String(value.message ?? "");
  return code === "53300" ||
    code === "57P03" ||
    code.startsWith("08") ||
    /too many clients|remaining connection slots|connection (?:refused|terminated|closed)|database system is starting up/i
      .test(message);
}

export async function closeLifeMateSqlClientsForTest(): Promise<void> {
  const current = [...clients.values()];
  clients.clear();
  await Promise.all(current.map((client) => client.end({ timeout: 1 })));
}
'''
)
(edge / "database_client_test.ts").write_text(
    '''import {
  assert,
  assertStrictEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  closeLifeMateSqlClientsForTest,
  getLifeMateSql,
  isPostgresUnavailable,
} from "./database_client.ts";

Deno.test("database stores reuse one bounded client per Edge isolate", async () => {
  const url = "postgres://user:password@127.0.0.1:5432/lifemate_test";
  assertStrictEquals(getLifeMateSql(url), getLifeMateSql(url));
  await closeLifeMateSqlClientsForTest();
});

Deno.test("connection exhaustion is returned as retryable unavailability", () => {
  assert(isPostgresUnavailable({ code: "53300", message: "too many clients" }));
  assert(
    isPostgresUnavailable({
      message:
        "remaining connection slots are reserved for roles with the SUPERUSER attribute",
    }),
  );
  assert(!isPostgresUnavailable({ code: "23505", message: "duplicate key" }));
});
'''
)

module_imports = {
    "database.ts": 'import { getLifeMateSql, type LifeMateSql } from "./database_client.ts";\n',
    "care_events.ts": 'import { getLifeMateSql, type LifeMateSql } from "./database_client.ts";\n',
    "profile.ts": 'import { getLifeMateSql } from "./database_client.ts";\n',
    "edit_store.ts": 'import { getLifeMateSql } from "./database_client.ts";\n',
    "women_calendar.ts": 'import { getLifeMateSql } from "./database_client.ts";\n',
}
pool_pattern = (
    r"  const sql = postgres\(databaseUrl, \{\n"
    r"    max: 2,\n"
    r"    idle_timeout: 20,\n"
    r"    connect_timeout: 10,\n"
    r"    prepare: false,\n"
    r"  \}\);"
)
for filename, replacement in module_imports.items():
    path = str(edge / filename)
    replace_once(path, 'import postgres from "postgres";\n', replacement)
    regex_once(path, pool_pattern, "  const sql = getLifeMateSql(databaseUrl);")

for filename in ("database.ts", "care_events.ts"):
    replace_once(
        str(edge / filename),
        'type Sql = ReturnType<typeof postgres>;\n',
        "type Sql = LifeMateSql;\n",
    )

index_path = str(edge / "index.ts")
replace_once(
    index_path,
    'import { type AuthUser, createLifeMateDatabase } from "./database.ts";\n',
    'import { type AuthUser, createLifeMateDatabase } from "./database.ts";\n'
    'import { isPostgresUnavailable } from "./database_client.ts";\n',
)
replace_once(
    index_path,
    "  const identity = await db.requireIdentity(auth);\n\n",
    '''  const identity = await db.requireIdentity(auth);

  if (request.method === "GET" && path === "/api/v1/home-snapshot") {
    const url = new URL(request.url);
    const fromDate = url.searchParams.get("fromDate");
    const toDate = url.searchParams.get("toDate");
    // Keep these reads sequential. Every store shares one bounded SQL client,
    // so one app screen consumes one database connection rather than a fan-out.
    const currentUser = await db.currentUser(identity);
    const treatmentPlans = await db.listTreatmentPlans(identity.appUserId);
    const doseOccurrences = await db.listDoseOccurrences(
      identity.appUserId,
      fromDate,
      toDate,
    );
    const ownerCareEvents = await careEvents.listCareEvents(
      identity.appUserId,
      fromDate,
      toDate,
    );
    return json({
      currentUser,
      treatmentPlans,
      doseOccurrences,
      careEvents: ownerCareEvents,
    });
  }

  if (
    request.method === "GET" &&
    path === "/api/v1/women-calendar/dashboard"
  ) {
    requireWomenCalendarPilot();
    const url = new URL(request.url);
    const fromDate = url.searchParams.get("fromDate");
    const toDate = url.searchParams.get("toDate");
    const profile = await womenCalendar.getOwnerProfile(identity.appUserId);
    const episodes = await womenCalendar.listOwnerEpisodes(identity.appUserId);
    const currentUser = await db.currentUser(identity);
    const currentProfile = await presentProfile(identity.appUserId);
    const relationships = await db.listRelationships(identity.appUserId);
    const treatmentPlans = await db.listTreatmentPlans(identity.appUserId);
    const dailyLogs = await womenCalendar.listOwnerDailyLogs(
      identity.appUserId,
      fromDate,
      toDate,
    );
    return json({
      profile,
      episodes,
      currentUser: { ...currentUser, profile: currentProfile },
      currentProfile,
      relationships,
      treatmentPlans,
      dailyLogs,
    });
  }

''',
)
replace_once(
    index_path,
    "    if (isPostgresConflict(error)) {\n",
    '''    if (isPostgresUnavailable(error)) {
      console.warn("LifeMate database temporarily unavailable", {
        correlationId,
        method: request.method,
        path,
        ...safeError(error),
      });
      return problem(
        503,
        "database_busy",
        "Database is temporarily busy. Please retry.",
        correlationId,
      );
    }
    if (isPostgresConflict(error)) {
''',
)

deno_path = edge / "deno.json"
deno = deno_path.read_text()
deno = deno.replace(
    "index.ts validation_test.ts",
    "index.ts database_client_test.ts validation_test.ts",
    1,
).replace(
    "deno test --no-check validation_test.ts",
    "deno test --no-check database_client_test.ts validation_test.ts",
    1,
)
deno_path.write_text(deno)

client_path = "packages/lifemate_client/lib/src/lifemate_api_client.dart"
replace_once(
    client_path,
    "  static const _retryDelay = Duration(milliseconds: 250);\n",
    "  static const _retryDelay = Duration(milliseconds: 350);\n",
)
replace_once(
    client_path,
    "    final maxAttempts = retryable ? 2 : 1;\n",
    "    final maxAttempts = retryable ? 3 : 1;\n",
)
replace_once(
    client_path,
    "  Future<Map<String, dynamic>> getCurrentProfile() async =>\n"
    "      _asObject(await _send('GET', '/api/v1/me/profile', retryable: true));\n\n",
    '''  Future<Map<String, dynamic>> getCurrentProfile() async =>
      _asObject(await _send('GET', '/api/v1/me/profile', retryable: true));

  Future<Map<String, dynamic>> getHomeSnapshot({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => _asObject(
    await _send(
      'GET',
      '/api/v1/home-snapshot',
      query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
      retryable: true,
    ),
  );

''',
)
replace_once(
    client_path,
    "  Future<Map<String, dynamic>> getWomenCalendarProfile() async => _asObject(\n"
    "    await _send('GET', '/api/v1/women-calendar/profile', retryable: true),\n"
    "  );\n\n",
    '''  Future<Map<String, dynamic>> getWomenCalendarProfile() async => _asObject(
    await _send('GET', '/api/v1/women-calendar/profile', retryable: true),
  );

  Future<Map<String, dynamic>> getWomenCalendarDashboard({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => _asObject(
    await _send(
      'GET',
      '/api/v1/women-calendar/dashboard',
      query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
      retryable: true,
    ),
  );

''',
)

loader_path = Path("wellmate/lib/screens/home/home_schedule_loader.dart")
loader = loader_path.read_text()
start = loader.index("  Future<HomeScheduleSnapshot> load({")
end = loader.index("  Future<_HomeLoadResult<T>> _capture<T>(", start)
loader_replacement = '''  Future<HomeScheduleSnapshot> load({
    required LifeMateApiClient api,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    try {
      final value = await api.getHomeSnapshot(
        fromDate: fromDate,
        toDate: toDate,
      );
      return HomeScheduleSnapshot(
        currentUser: _object(value['currentUser'], 'currentUser'),
        treatmentPlans: _objects(value['treatmentPlans'], 'treatmentPlans'),
        doseOccurrences: _objects(
          value['doseOccurrences'],
          'doseOccurrences',
        ),
        careEvents: _objects(value['careEvents'], 'careEvents'),
        failures: const [],
      );
    } on LifeMateApiException catch (error) {
      if (error.statusCode != 404 || error.code != 'route_not_found') rethrow;
      return _loadLegacy(api: api, fromDate: fromDate, toDate: toDate);
    }
  }

  Future<HomeScheduleSnapshot> _loadLegacy({
    required LifeMateApiClient api,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final currentUserFuture = _capture('current-user', api.getCurrentUser());
    final treatmentPlansFuture = _capture(
      'treatment-plans',
      api.getTreatmentPlans(),
    );
    final doseOccurrencesFuture = _capture(
      'dose-occurrences',
      api.getDoseOccurrences(fromDate: fromDate, toDate: toDate),
    );
    final careEventsFuture = _capture(
      'care-events',
      api.getCareEvents(fromDate: fromDate, toDate: toDate),
    );

    final currentUser = await currentUserFuture;
    final treatmentPlans = await treatmentPlansFuture;
    final doseOccurrences = await doseOccurrencesFuture;
    final careEvents = await careEventsFuture;
    currentUser.throwIfFailed();
    if (doseOccurrences.hasFailed && careEvents.hasFailed) {
      throw HomeScheduleLoadException([
        doseOccurrences.failure!,
        careEvents.failure!,
      ]);
    }
    final failures = <HomeScheduleLoadFailure>[
      if (treatmentPlans.failure case final failure?) failure,
      if (doseOccurrences.failure case final failure?) failure,
      if (careEvents.failure case final failure?) failure,
    ];
    return HomeScheduleSnapshot(
      currentUser: currentUser.value!,
      treatmentPlans: treatmentPlans.value ?? const [],
      doseOccurrences: doseOccurrences.value ?? const [],
      careEvents: careEvents.value ?? const [],
      failures: List<HomeScheduleLoadFailure>.unmodifiable(failures),
    );
  }

  Map<String, dynamic> _object(dynamic value, String field) {
    if (value is Map<String, dynamic>) return value;
    throw FormatException('Home snapshot field $field is not an object.');
  }

  List<Map<String, dynamic>> _objects(dynamic value, String field) {
    if (value is! List) {
      throw FormatException('Home snapshot field $field is not a list.');
    }
    return value
        .map((item) => _object(item, field))
        .toList(growable: false);
  }

'''
loader_path.write_text(loader[:start] + loader_replacement + loader[end:])

home_path = "wellmate/lib/screens/home/home_screen.dart"
replace_once(
    home_path,
    "  int _currentIndex = 4;\n",
    "  int _currentIndex = 4;\n  final Set<int> _visitedTabs = <int>{4};\n",
)
replace_once(
    home_path,
    "  bool _womenCalendarEnabled = false;\n",
    "  bool _womenCalendarEnabled =\n"
    "      LifeMateFeatureFlags.womenCalendarPilotEnabled;\n",
)
replace_once(
    home_path,
    "    } catch (_) {\n"
    "      debugPrint('Women calendar navigation state failed.');\n"
    "      if (mounted && _currentIndex == 3) {\n"
    "        setState(() => _currentIndex = 4);\n"
    "      }\n"
    "    } finally {\n",
    "    } catch (_) {\n"
    "      // Preserve the last known feature state on transient failures.\n"
    "      debugPrint('Women calendar navigation state failed.');\n"
    "    } finally {\n",
)
replace_once(
    home_path,
    "    setState(() {\n      _currentIndex = index;\n      switch (index) {\n",
    "    setState(() {\n"
    "      _visitedTabs.add(index);\n"
    "      _currentIndex = index;\n"
    "      switch (index) {\n",
)
replace_once(
    home_path,
    '''  @override
  Widget build(BuildContext context) {
    final pages = [
      CalendarScreen(refreshToken: _calendarRevision),
      TreatmentsScreen(refreshToken: _treatmentsRevision),
      CarePlanHubScreen(onCreated: _treatmentCreated),
      WomenCompanionScreen(
        key: ValueKey<int>(_womenRevision),
        onProfileChanged: () => _loadWomenCalendarState(force: true),
      ),
      HomeScreenContent(
        key: ValueKey<int>(_homeRevision),
        onOpenTreatments: () => _onItemTapped(1),
        onAddTreatment: () => _onItemTapped(2),
      ),
    ];
''',
    '''  Widget _buildTab(int index) {
    if (!_visitedTabs.contains(index)) return const SizedBox.shrink();
    return switch (index) {
      0 => CalendarScreen(refreshToken: _calendarRevision),
      1 => TreatmentsScreen(refreshToken: _treatmentsRevision),
      2 => CarePlanHubScreen(onCreated: _treatmentCreated),
      3 => WomenCompanionScreen(
        key: ValueKey<int>(_womenRevision),
        onProfileChanged: () => _loadWomenCalendarState(force: true),
      ),
      _ => HomeScreenContent(
        key: ValueKey<int>(_homeRevision),
        onOpenTreatments: () => _onItemTapped(1),
        onAddTreatment: () => _onItemTapped(2),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pages = List<Widget>.generate(5, _buildTab);
''',
)

content_path = "wellmate/lib/screens/home/home_screen_content.dart"
replace_once(
    content_path,
    "  Timer? _timer;\n",
    "  Timer? _timer;\n"
    "  Timer? _retryTimer;\n"
    "  int _automaticRetryCount = 0;\n"
    "  static const _maximumAutomaticRetries = 2;\n",
)
replace_once(
    content_path,
    "  void dispose() {\n    _timer?.cancel();\n    super.dispose();\n  }\n",
    "  void dispose() {\n"
    "    _timer?.cancel();\n"
    "    _retryTimer?.cancel();\n"
    "    super.dispose();\n"
    "  }\n",
)
replace_once(
    content_path,
    "      if (!mounted) return;\n"
    "      setState(() {\n"
    "        _displayName = profile['displayName']?.toString().trim() ?? '';\n",
    "      if (!mounted) return;\n"
    "      _automaticRetryCount = 0;\n"
    "      _retryTimer?.cancel();\n"
    "      setState(() {\n"
    "        _displayName = profile['displayName']?.toString().trim() ?? '';\n",
)
replace_once(
    content_path,
    '''    } catch (error) {
      debugPrint('WellMate home schedule sync failed: $error');
      if (!mounted) return;
      setState(() {
        isLoading = false;
        loadError = 'برنامه امروز دریافت نشد. اتصال را بررسی کنید.';
      });
    }
  }
''',
    '''    } catch (error) {
      debugPrint('WellMate home schedule sync failed: $error');
      if (!mounted) return;
      if (_isTransientLoadError(error) &&
          _automaticRetryCount < _maximumAutomaticRetries) {
        _automaticRetryCount += 1;
        final delay = Duration(milliseconds: 500 * _automaticRetryCount);
        setState(() {
          isLoading = true;
          loadError = null;
        });
        _retryTimer?.cancel();
        _retryTimer = Timer(delay, _fetchScheduleFromBackend);
        return;
      }
      setState(() {
        isLoading = false;
        loadError = 'برنامه امروز دریافت نشد. اتصال را بررسی کنید.';
      });
    }
  }

  bool _isTransientLoadError(Object error) {
    if (error is LifeMateApiException) {
      return error.statusCode == 0 ||
          error.statusCode == 500 ||
          error.statusCode == 502 ||
          error.statusCode == 503 ||
          error.statusCode == 504;
    }
    if (error is HomeScheduleLoadException) {
      return error.failures.any(
        (failure) => _isTransientLoadError(failure.error),
      );
    }
    return false;
  }

  void _retryManually() {
    _automaticRetryCount = 0;
    _retryTimer?.cancel();
    _fetchScheduleFromBackend();
  }
''',
)
replace_once(
    content_path,
    "                      onPressed: _fetchScheduleFromBackend,\n",
    "                      onPressed: _retryManually,\n",
)

companion_path = "wellmate/lib/screens/women_calendar/women_companion_screen.dart"
replace_once(
    companion_path,
    '''      final api = context.read<LifeMateApiClient>();
      final now = DateTime.now();
      final results = await Future.wait<dynamic>([
        api.getWomenCalendarProfile(),
        api.getWomenCalendarEpisodes(),
        api.getCurrentProfile(),
        api.getCareRelationships(),
        _companionApi.getDailyLogs(
          fromDate: now.subtract(const Duration(days: 89)),
          toDate: now,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as Map<String, dynamic>;
        _episodes = results[1] as List<Map<String, dynamic>>;
        _currentProfile = results[2] as Map<String, dynamic>;
        _relationships = results[3] as List<Map<String, dynamic>>;
        _dailyLogs = results[4] as List<Map<String, dynamic>>;
      });
''',
    '''      final api = context.read<LifeMateApiClient>();
      final now = DateTime.now();
      final dashboard = await api.getWomenCalendarDashboard(
        fromDate: now.subtract(const Duration(days: 89)),
        toDate: now,
      );
      if (!mounted) return;
      setState(() {
        _profile = dashboard['profile'] as Map<String, dynamic>? ?? const {};
        _episodes = (dashboard['episodes'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        _currentProfile =
            dashboard['currentProfile'] as Map<String, dynamic>? ?? const {};
        _relationships =
            (dashboard['relationships'] as List<dynamic>? ?? const [])
                .cast<Map<String, dynamic>>();
        _dailyLogs = (dashboard['dailyLogs'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
      });
''',
)

calendar_path = "wellmate/lib/screens/women_calendar/women_calendar_screen.dart"
replace_once(
    calendar_path,
    '''      final api = context.read<LifeMateApiClient>();
      final results = await Future.wait<dynamic>([
        api.getWomenCalendarProfile(),
        api.getWomenCalendarEpisodes(),
        api.getCurrentUser(),
        api.getCareRelationships(),
        api.getTreatmentPlans(),
      ]);
      if (!mounted) return;
      final profile = results[0] as Map<String, dynamic>;
      setState(() {
        _profile = profile;
        _episodes = results[1] as List<Map<String, dynamic>>;
        _currentUser = results[2] as Map<String, dynamic>;
        _relationships = results[3] as List<Map<String, dynamic>>;
        _treatmentPlans = results[4] as List<Map<String, dynamic>>;
        _applyProfile(profile);
      });
''',
    '''      final api = context.read<LifeMateApiClient>();
      final now = DateTime.now();
      final dashboard = await api.getWomenCalendarDashboard(
        fromDate: now.subtract(const Duration(days: 89)),
        toDate: now,
      );
      if (!mounted) return;
      final profile =
          dashboard['profile'] as Map<String, dynamic>? ?? const {};
      setState(() {
        _profile = profile;
        _episodes = (dashboard['episodes'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        _currentUser =
            dashboard['currentUser'] as Map<String, dynamic>? ?? const {};
        _relationships =
            (dashboard['relationships'] as List<dynamic>? ?? const [])
                .cast<Map<String, dynamic>>();
        _treatmentPlans =
            (dashboard['treatmentPlans'] as List<dynamic>? ?? const [])
                .cast<Map<String, dynamic>>();
        _applyProfile(profile);
      });
''',
)

home_test = "wellmate/test/home_schedule_loader_test.dart"
anchor = "  @override\n  Future<Map<String, dynamic>> getCurrentUser() async {\n"
replace_once(
    home_test,
    anchor,
    '''  @override
  Future<Map<String, dynamic>> getHomeSnapshot({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    throw const LifeMateApiException(
      statusCode: 404,
      code: 'route_not_found',
      message: 'Exercise the legacy partial-response fallback.',
    );
  }

'''
    + anchor,
)

women_test = "wellmate/test/women_companion_experience_test.dart"
anchor = "  @override\n  Future<Map<String, dynamic>> getWomenCalendarProfile() async {\n"
replace_once(
    women_test,
    anchor,
    '''  @override
  Future<Map<String, dynamic>> getWomenCalendarDashboard({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final today = _dateOnly(DateTime.now());
    final periodStart = today.subtract(const Duration(days: 2));
    return {
      'profile': {
        'enabled': true,
        'lastPeriodStart': _isoDate(periodStart),
        'cycleLength': 28,
        'periodLength': 5,
        'remindersEnabled': true,
        'version': 2,
      },
      'episodes': [
        {
          'id': 'episode-1',
          'startedOn': _isoDate(periodStart),
          'endedOn': null,
          'version': 1,
        },
      ],
      'currentUser': const {
        'user': {'id': 'patient-1'},
        'profile': {'displayName': 'نازنین'},
      },
      'currentProfile': const {
        'displayName': 'نازنین',
        'avatarKey': 'person_pink',
        'profilePhotoUrl': null,
      },
      'relationships': const [
        {
          'id': 'relationship-1',
          'status': 'active',
          'caregiverDisplayName': 'حمیدرضا',
          'canViewWomenCalendar': true,
        },
      ],
      'treatmentPlans': const [],
      'dailyLogs': [
        {
          'id': 'daily-1',
          'loggedOn': _isoDate(today),
          'mood': 'good',
          'energyLevel': 4,
          'painLevel': 1,
          'symptoms': ['fatigue'],
          'privateNotes': 'private owner note',
          'shareSummaryWithCompanion': true,
          'version': 1,
        },
      ],
    };
  }

'''
    + anchor,
)

client_test = Path("packages/lifemate_client/test/lifemate_api_client_test.dart")
text = client_test.read_text()
text = text.replace(
    "        if (requestCount == 1) {\n"
    "          return http.Response(\n"
    "            jsonEncode({'code': 'temporarily_unavailable'}),\n",
    "        if (requestCount < 3) {\n"
    "          return http.Response(\n"
    "            jsonEncode({'code': 'database_busy'}),\n",
    1,
).replace(
    "    expect(requestCount, 2);\n"
    "    expect(result.single['id'], 'medication-1');\n",
    "    expect(requestCount, 3);\n"
    "    expect(result.single['id'], 'medication-1');\n",
    1,
)
extra_test = '''
  test('home snapshot uses one range-scoped authenticated request', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'currentUser': {'profile': {'displayName': 'Test'}},
            'treatmentPlans': [],
            'doseOccurrences': [],
            'careEvents': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.getHomeSnapshot(
      fromDate: DateTime(2026, 8, 6),
      toDate: DateTime(2026, 8, 13),
    );

    expect(observed.url.path, '/api/v1/home-snapshot');
    expect(observed.url.queryParameters['fromDate'], '2026-08-06');
    expect(observed.url.queryParameters['toDate'], '2026-08-13');
    expect(result['doseOccurrences'], isEmpty);
  });
'''
if not text.endswith("\n}\n"):
    raise SystemExit("client test closing anchor missing")
client_test.write_text(text[:-3] + extra_test + "\n}\n")

# A lightweight source regression protects against reintroducing eager mounting.
ui_test = Path("wellmate/test/ui_regression_test.dart")
ui = ui_test.read_text()
marker = "void main() {\n"
regression = '''  test('home mounts data-heavy tabs lazily', () {
    final source = File('lib/screens/home/home_screen.dart').readAsStringSync();
    expect(source, contains('final Set<int> _visitedTabs = <int>{4}'));
    expect(source, contains('if (!_visitedTabs.contains(index))'));
    expect(source, contains('_visitedTabs.add(index)'));
  });

'''
if "home mounts data-heavy tabs lazily" not in ui:
    ui = ui.replace(marker, marker + regression, 1)
ui_test.write_text(ui)

Path(".github/workflows/db-pool-startup-resilience.yml").unlink()
Path("tools/hotfix/apply_db_pool_startup_resilience.py").unlink()
