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
        raise SystemExit(f'Expected snippet missing in {path}: {old[:140]!r}')
    write(path, text.replace(old, new, 1))

client = 'packages/lifemate_client/lib/src/women_calendar.dart'
replace_once(
    client,
    '''    final history = WomenCycleHistoryAssessment.fromPeriodStarts(\n      periodStarts: periodStarts,\n      fallbackCycleLength: configuredCycleLength,\n    );''',
    '''    final history = WomenCycleHistoryAssessment.fromPeriodStarts(\n      periodStarts: [...periodStarts, lastPeriodStart],\n      fallbackCycleLength: configuredCycleLength,\n    );''',
)
replace_once(
    client,
    '''    if (cycleDay <= periodLength) return WomenCyclePhase.period;\n    if (fertilityReliable && cycleDay == ovulationDay) {\n      return WomenCyclePhase.ovulation;\n    }\n    if (fertilityReliable &&\n        cycleDay >= fertileWindowStartDay &&\n        cycleDay <= fertileWindowEndDay) {\n      return WomenCyclePhase.fertile;\n    }\n    if (cycleDay >= pmsStartDay) return WomenCyclePhase.pms;\n    if (cycleDay > fertileWindowEndDay) return WomenCyclePhase.luteal;\n    return WomenCyclePhase.follicular;''',
    '''    if (cycleDay <= periodLength) return WomenCyclePhase.period;\n    if (!fertilityReliable) {\n      if (cycleDay >= pmsStartDay) return WomenCyclePhase.pms;\n      return WomenCyclePhase.follicular;\n    }\n    if (cycleDay == ovulationDay) return WomenCyclePhase.ovulation;\n    if (cycleDay >= fertileWindowStartDay &&\n        cycleDay <= fertileWindowEndDay) {\n      return WomenCyclePhase.fertile;\n    }\n    if (cycleDay >= pmsStartDay) return WomenCyclePhase.pms;\n    if (cycleDay > fertileWindowEndDay) return WomenCyclePhase.luteal;\n    return WomenCyclePhase.follicular;''',
)

client_test = 'packages/lifemate_client/test/women_calendar_test.dart'
text = read(client_test)
if 'latest configured period start participates in confidence history' not in text:
    marker = "\n  test(\n    'normalizes episode gaps by calendar date rather than elapsed local hours',"
    addition = '''\n  test('latest configured period start participates in confidence history', () {\n    final estimate = WomenCalendarEstimate.calculateFromEpisodes(\n      lastPeriodStart: DateTime(2026, 8, 1),\n      configuredCycleLength: 28,\n      periodLength: 5,\n      periodStarts: [\n        DateTime(2026, 5, 1),\n        DateTime(2026, 5, 29),\n        DateTime(2026, 6, 26),\n      ],\n      today: DateTime(2026, 8, 1),\n    );\n\n    expect(estimate.pattern, WomenCyclePattern.variable);\n    expect(estimate.confidence, WomenCycleEstimateConfidence.low);\n    expect(estimate.fertilityEstimateReliable, isFalse);\n  });\n\n  test('low confidence does not reveal the ovulation boundary via luteal phase', () {\n    final estimate = WomenCalendarEstimate.calculate(\n      lastPeriodStart: DateTime(2026, 8, 1),\n      cycleLength: 28,\n      periodLength: 5,\n      today: DateTime(2026, 8, 16),\n    );\n\n    expect(estimate.fertilityEstimateReliable, isFalse);\n    expect(estimate.detailedPhase, WomenCyclePhase.follicular);\n    expect(estimate.phaseForDate(DateTime(2026, 8, 16)), WomenCyclePhase.follicular);\n  });\n'''
    if marker not in text:
        raise SystemExit('Client test insertion marker missing')
    text = text.replace(marker, addition + marker, 1)
    write(client_test, text)

server = 'supabase/functions/lifemate-api/women_calendar.ts'
replace_once(
    server,
    '''  const assessment = assessCycleHistory(periodStarts, configuredCycleLength);''',
    '''  const assessment = assessCycleHistory(\n    [...periodStarts, lastPeriodStart],\n    configuredCycleLength,\n  );''',
)
replace_once(
    server,
    '''  const detailedPhase: DetailedPhase = !fertilityEstimateReliable &&\n      (rawDetailedPhase === "fertile" || rawDetailedPhase === "ovulation")\n    ? (cycleDay <= ovulationDay ? "follicular" : "luteal")\n    : rawDetailedPhase;''',
    '''  const detailedPhase: DetailedPhase = !fertilityEstimateReliable &&\n      rawDetailedPhase !== "period" && rawDetailedPhase !== "pms"\n    ? "follicular"\n    : rawDetailedPhase;''',
)

server_test = 'supabase/functions/lifemate-api/women_calendar_test.ts'
text = read(server_test)
if 'latest configured period start participates in server confidence history' not in text:
    text += '''\n\nDeno.test("latest configured period start participates in server confidence history", () => {\n  const estimate = calculateWomenCalendarEstimateFromEpisodes(\n    "2026-08-01",\n    28,\n    5,\n    ["2026-05-01", "2026-05-29", "2026-06-26"],\n    new Date("2026-08-01T00:00:00Z"),\n  );\n  assertEquals(estimate.cyclePattern, "variable");\n  assertEquals(estimate.confidence, "low");\n  assertEquals(estimate.fertilityEstimateReliable, false);\n});\n\nDeno.test("low confidence does not expose ovulation boundary through luteal phase", () => {\n  const estimate = calculateWomenCalendarEstimateFromEpisodes(\n    "2026-08-01",\n    28,\n    5,\n    ["2026-08-01"],\n    new Date("2026-08-16T00:00:00Z"),\n  );\n  assertEquals(estimate.fertilityEstimateReliable, false);\n  assertEquals(estimate.detailedPhase, "follicular");\n  assertEquals(estimate.ovulationDay, null);\n  assertEquals(estimate.fertileWindowStartDay, null);\n  assertEquals(estimate.fertileWindowEndDay, null);\n});\n'''
    write(server_test, text)
