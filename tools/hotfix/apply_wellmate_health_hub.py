from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def write(path: str, value: str) -> None:
    Path(path).write_text(value, encoding="utf-8")


def replace_once(value: str, old: str, new: str, label: str) -> str:
    count = value.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return value.replace(old, new, 1)


# Edge API routing.
path = "supabase/functions/lifemate-api/index.ts"
value = read(path)
value = replace_once(
    value,
    'import { createEditStore } from "./edit_store.ts";\n',
    'import { createEditStore } from "./edit_store.ts";\nimport { createHealthObservationStore } from "./health_observations.ts";\n',
    "health store import",
)
value = replace_once(
    value,
    'const edits = createEditStore(databaseUrl);\n',
    'const edits = createEditStore(databaseUrl);\nconst healthObservations = createHealthObservationStore(databaseUrl);\n',
    "health store initialization",
)
health_routes = '''  if (request.method === "GET" && path === "/api/v1/health/observations") {
    const url = new URL(request.url);
    return json(
      await healthObservations.listOwnerObservations(
        identity.appUserId,
        url.searchParams.get("fromDate"),
        url.searchParams.get("toDate"),
      ),
    );
  }
  if (request.method === "POST" && path === "/api/v1/health/observations") {
    enforceRateLimit(`health-write:${identity.appUserId}`, 60, 60 * 60_000);
    return json(
      await healthObservations.createOwnerObservation(
        identity.appUserId,
        await readJsonObject(request),
      ),
      201,
    );
  }
  const healthObservationMatch = path.match(
    /^\\/api\\/v1\\/health\\/observations\\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "DELETE" && healthObservationMatch) {
    enforceRateLimit(`health-delete:${identity.appUserId}`, 30, 60 * 60_000);
    await healthObservations.deleteOwnerObservation(
      identity.appUserId,
      healthObservationMatch[1],
    );
    return new Response(null, { status: 204, headers: corsHeaders });
  }

'''
value = replace_once(
    value,
    '  if (request.method === "GET" && path === "/api/v1/women-calendar/profile") {\n',
    health_routes + '  if (request.method === "GET" && path === "/api/v1/women-calendar/profile") {\n',
    "health routes",
)
write(path, value)

# Deno check/test task coverage.
path = "supabase/functions/lifemate-api/deno.json"
value = read(path)
value = replace_once(
    value,
    'profile_photo_test.ts database_integration_test.ts',
    'profile_photo_test.ts health_observations_test.ts database_integration_test.ts',
    "deno check health test",
)
value = replace_once(
    value,
    'profile_photo_test.ts women_calendar_test.ts',
    'profile_photo_test.ts health_observations_test.ts women_calendar_test.ts',
    "deno unit health test",
)
write(path, value)

# Shared client export.
path = "packages/lifemate_client/lib/lifemate_client.dart"
value = read(path)
value = replace_once(
    value,
    "export 'src/health_facts.dart';\n",
    "export 'src/health_facts.dart';\nexport 'src/health_observations_api.dart';\n",
    "shared client health export",
)
write(path, value)

# Calendar can render a health-history event dot while preserving treatment dots.
path = "wellmate/lib/screens/calendar/custom_table_calendar.dart"
value = read(path)
value = replace_once(
    value,
    "    final colors = <Color>[\n",
    "    final colors = <Color>[\n      if (eventTypes.contains('health')) AppColors.primary,\n",
    "health calendar dot",
)
write(path, value)

# Add Health as a first-class tab without removing the existing Women companion.
path = "wellmate/lib/core/widgets/wellmate_bottom_nav.dart"
value = read(path)
needle = '''            _buildNavItem(
              icon: Icons.add_circle_outline_rounded,
              label: loc['nav_add_treatment'],
              index: 2,
              fontFamily: fontFamily,
            ),
            if (womenCalendarEnabled)
'''
replacement = '''            _buildNavItem(
              icon: Icons.add_circle_outline_rounded,
              label: loc['nav_add_treatment'],
              index: 2,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              icon: Icons.monitor_heart_rounded,
              label: isPersian ? 'سلامت' : 'Health',
              index: 3,
              fontFamily: fontFamily,
            ),
            if (womenCalendarEnabled)
'''
value = replace_once(value, needle, replacement, "bottom nav health item")
value = replace_once(value, "                index: 3,\n", "                index: 4,\n", "women nav index")
value = replace_once(value, "              index: 4,\n", "              index: 5,\n", "home nav index")
write(path, value)

path = "wellmate/lib/screens/home/home_screen.dart"
value = read(path)
value = replace_once(
    value,
    "import '../calendar/calendar_screen.dart';\n",
    "import '../calendar/calendar_screen.dart';\nimport '../health/health_screen.dart';\n",
    "home health import",
)
value = replace_once(
    value,
    "  int _currentIndex = 4;\n  final Set<int> _visitedTabs = <int>{4};\n",
    "  int _currentIndex = 5;\n  final Set<int> _visitedTabs = <int>{5};\n",
    "home initial index",
)
value = replace_once(
    value,
    "  int _treatmentsRevision = 0;\n  int _womenRevision = 0;\n",
    "  int _treatmentsRevision = 0;\n  int _healthRevision = 0;\n  int _womenRevision = 0;\n",
    "health revision",
)
value = replace_once(
    value,
    "_visitedTabs.addAll(const <int>{0, 1, 2, 3, 4})",
    "_visitedTabs.addAll(const <int>{0, 1, 2, 3, 4, 5})",
    "tab prewarm",
)
value = value.replace("if (_currentIndex == 3) _currentIndex = 4;", "if (_currentIndex == 4) _currentIndex = 5;")
value = replace_once(
    value,
    "        _treatmentsRevision++;\n        _womenRevision++;\n",
    "        _treatmentsRevision++;\n        _healthRevision++;\n        _womenRevision++;\n",
    "full health refresh",
)
value = replace_once(
    value,
    "      _currentIndex = 4;\n",
    "      _currentIndex = 5;\n",
    "post treatment home",
)
value = replace_once(
    value,
    "    if (index == 3 && !_womenCalendarEnabled) return;\n",
    "    if (index == 4 && !_womenCalendarEnabled) return;\n",
    "women disabled nav guard",
)
old_switch = '''        case 3:
          _womenRevision++;
          break;
        case 4:
          _homeRevision++;
          break;
'''
new_switch = '''        case 3:
          _healthRevision++;
          break;
        case 4:
          _womenRevision++;
          break;
        case 5:
          _homeRevision++;
          break;
'''
value = replace_once(value, old_switch, new_switch, "active tab refresh switch")
old_tabs = '''      3 => WomenCompanionScreen(
        refreshToken: _womenRevision,
        onProfileChanged: () => _loadWomenCalendarState(force: true),
      ),
      _ => HomeScreenContent(
'''
new_tabs = '''      3 => HealthScreen(refreshToken: _healthRevision),
      4 => WomenCompanionScreen(
        refreshToken: _womenRevision,
        onProfileChanged: () => _loadWomenCalendarState(force: true),
      ),
      _ => HomeScreenContent(
'''
value = replace_once(value, old_tabs, new_tabs, "health tab screen")
value = replace_once(value, "final pages = List<Widget>.generate(5, _buildTab);", "final pages = List<Widget>.generate(6, _buildTab);", "six pages")
value = replace_once(value, "canPop: _currentIndex == 4,", "canPop: _currentIndex == 5,", "home pop index")
value = replace_once(value, "if (!didPop && _currentIndex != 4) {", "if (!didPop && _currentIndex != 5) {", "home pop guard")
value = replace_once(value, "_currentIndex = 4;\n            _homeRevision++;", "_currentIndex = 5;\n            _homeRevision++;", "pop returns home")
write(path, value)

# Small runtime layout/cancellation polish found while validating the new screen.
path = "wellmate/lib/screens/health/health_screen.dart"
value = read(path)
value = replace_once(
    value,
    "          crossAxisAlignment: CrossAxisAlignment.stretch,\n          children: [\n            Expanded(child: cards[0]),",
    "          crossAxisAlignment: CrossAxisAlignment.start,\n          children: [\n            Expanded(child: cards[0]),",
    "health body row layout",
)
value = replace_once(
    value,
    "            const Spacer(),\n            Container(\n              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),",
    "            const SizedBox(height: 9),\n            Container(\n              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),",
    "vital card bounded flex",
)
value = replace_once(
    value,
    "          await _load(background: true);\n          WellMateRefreshSignal.notifyChanged();\n        },\n      ),\n    );\n    if (!mounted) return;\n    ScaffoldMessenger.of(context).showSnackBar(\n      const SnackBar(content: Text('اطلاعات سلامت ذخیره شد.')),\n    );\n",
    "          await _load(background: true);\n          WellMateRefreshSignal.notifyChanged();\n          if (mounted) {\n            ScaffoldMessenger.of(context).showSnackBar(\n              const SnackBar(content: Text('اطلاعات سلامت ذخیره شد.')),\n            );\n          }\n        },\n      ),\n    );\n",
    "entry cancel snackbar",
)
write(path, value)

print("WellMate health hub patch applied.")
