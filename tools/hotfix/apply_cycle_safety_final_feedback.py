from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"Expected snippet missing in {path}: {old[:160]!r}")
    write(path, text.replace(old, new, 1))


# Calendar-day gaps must be timezone/DST independent.
replace_once(
    "packages/lifemate_client/lib/src/women_calendar.dart",
    ".map((value) => DateTime(value.year, value.month, value.day))",
    ".map((value) => DateTime.utc(value.year, value.month, value.day))",
)

server = "supabase/functions/lifemate-api/women_calendar.ts"

# Do not expose raw fertility timing at all when the estimate is unreliable.
replace_once(
    server,
    """  ovulationDay: number;\n  fertileWindowStartDay: number;\n  fertileWindowEndDay: number;""",
    """  ovulationDay: number | null;\n  fertileWindowStartDay: number | null;\n  fertileWindowEndDay: number | null;""",
)
replace_once(
    server,
    """    ovulationDay,\n    fertileWindowStartDay,\n    fertileWindowEndDay,\n    pmsStartDay,""",
    """    ovulationDay: fertilityEstimateReliable ? ovulationDay : null,\n    fertileWindowStartDay: fertilityEstimateReliable ? fertileWindowStartDay : null,\n    fertileWindowEndDay: fertilityEstimateReliable ? fertileWindowEndDay : null,\n    pmsStartDay,""",
)

# Owner profile GET must use actual episode history just like CareMate.
replace_once(
    server,
    """    return rows[0] ? mapProfile(rows[0]) : defaultProfile(userId);""",
    """    if (!rows[0]) return defaultProfile(userId);\n    const episodes = await sql`\n      select started_on from lifemate.women_calendar_episodes\n      where owner_user_id = ${userId}\n      order by started_on asc\n      limit 100\n    `;\n    return mapProfileWithEpisodeHistory(rows[0], episodes);""",
)

# Profile update responses should also return the same history-aware estimate.
replace_once(
    server,
    """        return mapProfile(rows[0]);\n      }\n      if (existing.version !== expectedVersion) {""",
    """        const episodes = await tx`\n          select started_on from lifemate.women_calendar_episodes\n          where owner_user_id = ${userId}\n          order by started_on asc\n          limit 100\n        `;\n        return mapProfileWithEpisodeHistory(rows[0], episodes);\n      }\n      if (existing.version !== expectedVersion) {""",
)
replace_once(
    server,
    """      return mapProfile(rows[0]);\n    });\n  }\n\n  async function listOwnerEpisodes(""",
    """      const episodes = await tx`\n        select started_on from lifemate.women_calendar_episodes\n        where owner_user_id = ${userId}\n        order by started_on asc\n        limit 100\n      `;\n      return mapProfileWithEpisodeHistory(rows[0], episodes);\n    });\n  }\n\n  async function listOwnerEpisodes(""",
)

# Centralize profile mapping so all owner responses share one estimate contract.
replace_once(
    server,
    """function defaultProfile(userId: string): Record<string, unknown> {""",
    """function mapProfileWithEpisodeHistory(\n  row: Row,\n  episodeRows: Row[],\n): Record<string, any> {\n  const profile = mapProfile(row);\n  const lastPeriodStart = profile.lastPeriodStart;\n  if (profile.enabled === true && typeof lastPeriodStart === \"string\") {\n    profile.estimate = calculateWomenCalendarEstimateFromEpisodes(\n      lastPeriodStart,\n      Number(profile.cycleLength),\n      Number(profile.periodLength),\n      episodeRows.map((episode) => dateString(episode.started_on)),\n    );\n  }\n  return profile;\n}\n\nfunction defaultProfile(userId: string): Record<string, unknown> {""",
)

# Extend Edge tests to assert redaction and reliable timing availability.
test = "supabase/functions/lifemate-api/women_calendar_test.ts"
text = read(test)
text = text.replace(
    """  assertEquals(estimate.fertilityEstimateReliable, false);\n  assertEquals(\n    [\"fertile\", \"ovulation\"].includes(estimate.detailedPhase),\n    false,\n  );""",
    """  assertEquals(estimate.fertilityEstimateReliable, false);\n  assertEquals(estimate.ovulationDay, null);\n  assertEquals(estimate.fertileWindowStartDay, null);\n  assertEquals(estimate.fertileWindowEndDay, null);\n  assertEquals(\n    [\"fertile\", \"ovulation\"].includes(estimate.detailedPhase),\n    false,\n  );""",
    1,
)
needle = """  assertEquals(estimate.fertilityEstimateReliable, true);\n});"""
replacement = """  assertEquals(estimate.fertilityEstimateReliable, true);\n  assertEquals(typeof estimate.ovulationDay, \"number\");\n  assertEquals(typeof estimate.fertileWindowStartDay, \"number\");\n  assertEquals(typeof estimate.fertileWindowEndDay, \"number\");\n});"""
if replacement not in text:
    if needle not in text:
        raise SystemExit("Stable-history test snippet missing")
    text = text.replace(needle, replacement, 1)
# Add redaction asserts to the variable test too.
variable_old = """  assertEquals(estimate.fertilityEstimateReliable, false);\n  assertEquals(\n    [\"fertile\", \"ovulation\"].includes(estimate.detailedPhase),\n    false,\n  );\n});"""
variable_new = """  assertEquals(estimate.fertilityEstimateReliable, false);\n  assertEquals(estimate.ovulationDay, null);\n  assertEquals(estimate.fertileWindowStartDay, null);\n  assertEquals(estimate.fertileWindowEndDay, null);\n  assertEquals(\n    [\"fertile\", \"ovulation\"].includes(estimate.detailedPhase),\n    false,\n  );\n});"""
if text.count(variable_new) < 2:
    pos = text.rfind(variable_old)
    if pos == -1:
        raise SystemExit("Variable-history test snippet missing")
    text = text[:pos] + variable_new + text[pos + len(variable_old):]
write(test, text)

# Add a Dart regression test proving DST-sensitive local dates are compared as calendar days.
dart_test = "packages/lifemate_client/test/women_calendar_test.dart"
text = read(dart_test)
if "normalizes episode gaps by calendar date" not in text:
    insertion = r'''

  test('normalizes episode gaps by calendar date rather than elapsed local hours', () {
    final assessment = WomenCycleHistoryAssessment.fromPeriodStarts(
      periodStarts: [
        DateTime(2026, 2, 22, 23, 30),
        DateTime(2026, 3, 15, 0, 15),
        DateTime(2026, 4, 5, 18),
      ],
      fallbackCycleLength: 21,
    );

    expect(assessment.pattern, WomenCyclePattern.regular);
    expect(assessment.representativeCycleLength, 21);
  });
'''
    idx = text.rfind("\n}")
    if idx == -1:
        raise SystemExit("Dart test closing brace missing")
    text = text[:idx] + insertion + text[idx:]
write(dart_test, text)
