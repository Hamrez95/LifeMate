from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"Expected snippet not found in {path}: {old[:180]!r}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


# WellMate: both production routes must assess recorded period-start history.
old_getter = '''    return WomenCalendarEstimate.calculate(\n      lastPeriodStart: start,\n      cycleLength: _cycleLength,\n      periodLength: _periodLength,\n    );'''
new_getter = '''    final periodStarts = _episodes\n        .map((episode) => DateTime.tryParse(episode['startedOn']?.toString() ?? ''))\n        .whereType<DateTime>()\n        .toList(growable: false);\n    return WomenCalendarEstimate.calculateFromEpisodes(\n      lastPeriodStart: start,\n      configuredCycleLength: _cycleLength,\n      periodLength: _periodLength,\n      periodStarts: periodStarts,\n    );'''
replace_once(
    "wellmate/lib/screens/women_calendar/women_calendar_screen.dart",
    old_getter,
    new_getter,
)
replace_once(
    "wellmate/lib/screens/women_calendar/women_companion_screen.dart",
    old_getter,
    new_getter,
)

# Shared WellMate ring: never draw fertility/ovulation segments when history is
# insufficient or variable.
replace_once(
    "wellmate/lib/screens/women_calendar/women_calendar_experience_widgets.dart",
    '''List<WomenCycleSegment> womenCycleSegments(WomenCalendarEstimate estimate) {\n  final pmsStart = math.max(estimate.periodLength + 1, estimate.cycleLength - 4);\n  return [\n    WomenCycleSegment(\n      startDay: 1,\n      endDay: estimate.periodLength,\n      phase: WomenCalendarDetailedPhase.period,\n      color: const Color(0xFFE65F8C),\n    ),\n    WomenCycleSegment(\n      startDay: estimate.periodLength + 1,\n      endDay: math.max(estimate.periodLength + 1, estimate.fertileWindowStartDay - 1),\n      phase: WomenCalendarDetailedPhase.follicular,\n      color: const Color(0xFFF0A643),\n    ),\n    WomenCycleSegment(\n      startDay: estimate.fertileWindowStartDay,\n      endDay: estimate.ovulationDay - 1,\n      phase: WomenCalendarDetailedPhase.fertile,\n      color: const Color(0xFF45B8A5),\n    ),\n    WomenCycleSegment(\n      startDay: estimate.ovulationDay,\n      endDay: estimate.ovulationDay,\n      phase: WomenCalendarDetailedPhase.ovulation,\n      color: const Color(0xFF2E9A7B),\n    ),\n    WomenCycleSegment(\n      startDay: estimate.ovulationDay + 1,\n      endDay: pmsStart - 1,\n      phase: WomenCalendarDetailedPhase.luteal,\n      color: const Color(0xFF9C71D2),\n    ),\n    WomenCycleSegment(\n      startDay: pmsStart,\n      endDay: estimate.cycleLength,\n      phase: WomenCalendarDetailedPhase.pms,\n      color: const Color(0xFFEE7991),\n    ),\n  ].where((segment) => segment.startDay <= segment.endDay).toList(growable: false);\n}''',
    '''List<WomenCycleSegment> womenCycleSegments(WomenCalendarEstimate estimate) {\n  final pmsStart = math.max(estimate.periodLength + 1, estimate.cycleLength - 4);\n  if (!estimate.fertilityEstimateReliable) {\n    return [\n      WomenCycleSegment(\n        startDay: 1,\n        endDay: estimate.periodLength,\n        phase: WomenCalendarDetailedPhase.period,\n        color: const Color(0xFFE65F8C),\n      ),\n      WomenCycleSegment(\n        startDay: estimate.periodLength + 1,\n        endDay: pmsStart - 1,\n        phase: WomenCalendarDetailedPhase.follicular,\n        color: const Color(0xFFF0A643),\n      ),\n      WomenCycleSegment(\n        startDay: pmsStart,\n        endDay: estimate.cycleLength,\n        phase: WomenCalendarDetailedPhase.pms,\n        color: const Color(0xFFEE7991),\n      ),\n    ].where((segment) => segment.startDay <= segment.endDay).toList(growable: false);\n  }\n  return [\n    WomenCycleSegment(\n      startDay: 1,\n      endDay: estimate.periodLength,\n      phase: WomenCalendarDetailedPhase.period,\n      color: const Color(0xFFE65F8C),\n    ),\n    WomenCycleSegment(\n      startDay: estimate.periodLength + 1,\n      endDay: math.max(estimate.periodLength + 1, estimate.fertileWindowStartDay - 1),\n      phase: WomenCalendarDetailedPhase.follicular,\n      color: const Color(0xFFF0A643),\n    ),\n    WomenCycleSegment(\n      startDay: estimate.fertileWindowStartDay,\n      endDay: estimate.ovulationDay - 1,\n      phase: WomenCalendarDetailedPhase.fertile,\n      color: const Color(0xFF45B8A5),\n    ),\n    WomenCycleSegment(\n      startDay: estimate.ovulationDay,\n      endDay: estimate.ovulationDay,\n      phase: WomenCalendarDetailedPhase.ovulation,\n      color: const Color(0xFF2E9A7B),\n    ),\n    WomenCycleSegment(\n      startDay: estimate.ovulationDay + 1,\n      endDay: pmsStart - 1,\n      phase: WomenCalendarDetailedPhase.luteal,\n      color: const Color(0xFF9C71D2),\n    ),\n    WomenCycleSegment(\n      startDay: pmsStart,\n      endDay: estimate.cycleLength,\n      phase: WomenCalendarDetailedPhase.pms,\n      color: const Color(0xFFEE7991),\n    ),\n  ].where((segment) => segment.startDay <= segment.endDay).toList(growable: false);\n}''',
)

replace_once(
    "wellmate/lib/screens/women_calendar/women_calendar_experience_widgets.dart",
    '''                _CycleMetric(\n                  icon: Icons.spa_outlined,\n                  title: 'تخمک‌گذاری',\n                  value:\n                      '${math.max(0, value.ovulationDay - value.cycleDay)} روز تا تخمک‌گذاری تخمینی',\n                ),''',
    '''                _CycleMetric(\n                  icon: value.fertilityEstimateReliable\n                      ? Icons.spa_outlined\n                      : Icons.info_outline_rounded,\n                  title: 'برآورد باروری',\n                  value: value.fertilityEstimateReliable\n                      ? '${math.max(0, value.ovulationDay - value.cycleDay)} روز تا تخمک‌گذاری تخمینی'\n                      : 'فعلاً داده کافی برای نمایش زمان باروری نداریم',\n                ),''',
)

# The compact month ring had its own raw fertile/ovulation segments.
replace_once(
    "wellmate/lib/screens/women_calendar/women_calendar_month_card.dart",
    '''    final segments = <_CycleSegment>[\n      _CycleSegment(1, estimate.periodLength, _periodColor),\n      _CycleSegment(\n        estimate.periodLength + 1,\n        estimate.fertileWindowStartDay - 1,\n        _follicularColor,\n      ),\n      _CycleSegment(\n        estimate.fertileWindowStartDay,\n        estimate.ovulationDay - 1,\n        _fertileColor,\n      ),\n      _CycleSegment(\n        estimate.ovulationDay,\n        estimate.ovulationDay,\n        _ovulationColor,\n      ),\n      _CycleSegment(\n        estimate.ovulationDay + 1,\n        pmsStart - 1,\n        _lutealColor,\n      ),\n      _CycleSegment(pmsStart, estimate.cycleLength, _pmsColor),\n    ];''',
    '''    final segments = estimate.fertilityEstimateReliable\n        ? <_CycleSegment>[\n            _CycleSegment(1, estimate.periodLength, _periodColor),\n            _CycleSegment(\n              estimate.periodLength + 1,\n              estimate.fertileWindowStartDay - 1,\n              _follicularColor,\n            ),\n            _CycleSegment(\n              estimate.fertileWindowStartDay,\n              estimate.ovulationDay - 1,\n              _fertileColor,\n            ),\n            _CycleSegment(\n              estimate.ovulationDay,\n              estimate.ovulationDay,\n              _ovulationColor,\n            ),\n            _CycleSegment(\n              estimate.ovulationDay + 1,\n              pmsStart - 1,\n              _lutealColor,\n            ),\n            _CycleSegment(pmsStart, estimate.cycleLength, _pmsColor),\n          ]\n        : <_CycleSegment>[\n            _CycleSegment(1, estimate.periodLength, _periodColor),\n            _CycleSegment(estimate.periodLength + 1, pmsStart - 1, _follicularColor),\n            _CycleSegment(pmsStart, estimate.cycleLength, _pmsColor),\n          ];''',
)

server = "supabase/functions/lifemate-api/women_calendar.ts"
replace_once(
    server,
    '''export type WomenCalendarEstimate = {\n  cycleStart: string;\n  cycleDay: number;\n  cycleLength: number;\n  periodLength: number;\n  estimatedBleeding: boolean;\n  phase: "period" | "post_period" | "cycle" | "pre_period";\n  detailedPhase:\n    | "period"\n    | "follicular"\n    | "fertile"\n    | "ovulation"\n    | "luteal"\n    | "pms";\n  ovulationDay: number;\n  fertileWindowStartDay: number;\n  fertileWindowEndDay: number;\n  nextPeriodStart: string;\n  daysUntilNextPeriod: number;\n  algorithmVersion: "calendar-estimate-v1";\n};''',
    '''export type WomenCalendarEstimate = {\n  cycleStart: string;\n  cycleDay: number;\n  cycleLength: number;\n  periodLength: number;\n  estimatedBleeding: boolean;\n  phase: "period" | "post_period" | "cycle" | "pre_period";\n  detailedPhase:\n    | "period"\n    | "follicular"\n    | "fertile"\n    | "ovulation"\n    | "luteal"\n    | "pms";\n  ovulationDay: number;\n  fertileWindowStartDay: number;\n  fertileWindowEndDay: number;\n  nextPeriodStart: string;\n  daysUntilNextPeriod: number;\n  algorithmVersion: "calendar-estimate-v1";\n  confidence: "low" | "medium" | "high";\n  cyclePattern: "insufficient_data" | "regular" | "variable";\n  fertilityEstimateReliable: boolean;\n  uncertaintyReason: string;\n};''',
)

old_calc = '''export function calculateWomenCalendarEstimate(\n  lastPeriodStart: string,\n  cycleLength: number,\n  periodLength: number,\n  now: Date = new Date(),\n): WomenCalendarEstimate {\n  const today = new Date(\n    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),\n  );\n  const anchor = parseDateOnly(lastPeriodStart);\n  const daysSinceAnchor = Math.floor(\n    (today.getTime() - anchor.getTime()) / 86_400_000,\n  );\n  const offset = ((daysSinceAnchor % cycleLength) + cycleLength) % cycleLength;\n  const cycleStart = addUtcDays(today, -offset);\n  const cycleDay = offset + 1;\n  const daysUntilNextPeriod = cycleLength - offset;\n  const nextPeriodStart = addUtcDays(today, daysUntilNextPeriod);\n  const phase = cycleDay <= periodLength\n    ? "period"\n    : cycleDay >= Math.max(periodLength + 1, cycleLength - 4)\n    ? "pre_period"\n    : cycleDay <= periodLength + 3\n    ? "post_period"\n    : "cycle";\n  const ovulationDay = clamp(\n    cycleLength - 14,\n    periodLength + 2,\n    cycleLength - 5,\n  );\n  const fertileWindowStartDay = clamp(\n    ovulationDay - 5,\n    periodLength + 1,\n    ovulationDay,\n  );\n  const fertileWindowEndDay = clamp(\n    ovulationDay + 1,\n    ovulationDay,\n    cycleLength,\n  );\n  const detailedPhase = phaseForCycleDay(\n    cycleDay,\n    periodLength,\n    cycleLength,\n    fertileWindowStartDay,\n    fertileWindowEndDay,\n    ovulationDay,\n  );\n  return {\n    cycleStart: dateString(cycleStart),\n    cycleDay,\n    cycleLength,\n    periodLength,\n    estimatedBleeding: cycleDay <= periodLength,\n    phase,\n    detailedPhase,\n    ovulationDay,\n    fertileWindowStartDay,\n    fertileWindowEndDay,\n    nextPeriodStart: dateString(nextPeriodStart),\n    daysUntilNextPeriod,\n    algorithmVersion: "calendar-estimate-v1",\n  };\n}'''
new_calc = '''export function calculateWomenCalendarEstimate(\n  lastPeriodStart: string,\n  cycleLength: number,\n  periodLength: number,\n  now: Date = new Date(),\n): WomenCalendarEstimate {\n  const estimate = calculateCalendarCore(\n    lastPeriodStart,\n    cycleLength,\n    periodLength,\n    now,\n    false,\n  );\n  return {\n    ...estimate,\n    confidence: "low",\n    cyclePattern: "insufficient_data",\n    fertilityEstimateReliable: false,\n    uncertaintyReason:\n      "ثبت‌های کافی برای برآورد باروری وجود ندارد؛ این تقویم تقریبی است و تشخیص پزشکی نیست.",\n  };\n}\n\nexport function calculateWomenCalendarEstimateFromEpisodes(\n  lastPeriodStart: string,\n  configuredCycleLength: number,\n  periodLength: number,\n  periodStarts: string[],\n  now: Date = new Date(),\n): WomenCalendarEstimate {\n  const assessment = assessCycleHistory(periodStarts, configuredCycleLength);\n  const reliable =\n    assessment.pattern === "regular" && assessment.confidence !== "low";\n  const estimate = calculateCalendarCore(\n    lastPeriodStart,\n    assessment.representativeCycleLength,\n    periodLength,\n    now,\n    reliable,\n  );\n  return {\n    ...estimate,\n    confidence: assessment.confidence,\n    cyclePattern: assessment.pattern,\n    fertilityEstimateReliable: reliable,\n    uncertaintyReason: assessment.reason,\n  };\n}\n\nfunction calculateCalendarCore(\n  lastPeriodStart: string,\n  cycleLength: number,\n  periodLength: number,\n  now: Date,\n  allowFertilityPhase: boolean,\n): Omit<\n  WomenCalendarEstimate,\n  "confidence" | "cyclePattern" | "fertilityEstimateReliable" | "uncertaintyReason"\n> {\n  const today = new Date(\n    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),\n  );\n  const anchor = parseDateOnly(lastPeriodStart);\n  const daysSinceAnchor = Math.floor(\n    (today.getTime() - anchor.getTime()) / 86_400_000,\n  );\n  const offset = ((daysSinceAnchor % cycleLength) + cycleLength) % cycleLength;\n  const cycleStart = addUtcDays(today, -offset);\n  const cycleDay = offset + 1;\n  const daysUntilNextPeriod = cycleLength - offset;\n  const nextPeriodStart = addUtcDays(today, daysUntilNextPeriod);\n  const phase = cycleDay <= periodLength\n    ? "period"\n    : cycleDay >= Math.max(periodLength + 1, cycleLength - 4)\n    ? "pre_period"\n    : cycleDay <= periodLength + 3\n    ? "post_period"\n    : "cycle";\n  const ovulationDay = clamp(\n    cycleLength - 14,\n    periodLength + 2,\n    cycleLength - 5,\n  );\n  const fertileWindowStartDay = clamp(\n    ovulationDay - 5,\n    periodLength + 1,\n    ovulationDay,\n  );\n  const fertileWindowEndDay = clamp(\n    ovulationDay + 1,\n    ovulationDay,\n    cycleLength,\n  );\n  const rawDetailedPhase = phaseForCycleDay(\n    cycleDay,\n    periodLength,\n    cycleLength,\n    fertileWindowStartDay,\n    fertileWindowEndDay,\n    ovulationDay,\n  );\n  const detailedPhase = !allowFertilityPhase &&\n      (rawDetailedPhase === "fertile" || rawDetailedPhase === "ovulation")\n    ? (cycleDay <= ovulationDay ? "follicular" : "luteal")\n    : rawDetailedPhase;\n  return {\n    cycleStart: dateString(cycleStart),\n    cycleDay,\n    cycleLength,\n    periodLength,\n    estimatedBleeding: cycleDay <= periodLength,\n    phase,\n    detailedPhase,\n    ovulationDay,\n    fertileWindowStartDay,\n    fertileWindowEndDay,\n    nextPeriodStart: dateString(nextPeriodStart),\n    daysUntilNextPeriod,\n    algorithmVersion: "calendar-estimate-v1",\n  };\n}\n\nfunction assessCycleHistory(\n  periodStarts: string[],\n  configuredCycleLength: number,\n): {\n  pattern: "insufficient_data" | "regular" | "variable";\n  confidence: "low" | "medium" | "high";\n  representativeCycleLength: number;\n  reason: string;\n} {\n  const starts = Array.from(new Set(periodStarts))\n    .map(parseDateOnly)\n    .sort((a, b) => a.getTime() - b.getTime());\n  const intervals: number[] = [];\n  for (let index = 1; index < starts.length; index++) {\n    const days = Math.round(\n      (starts[index].getTime() - starts[index - 1].getTime()) / 86_400_000,\n    );\n    if (days >= 15 && days <= 90) intervals.push(days);\n  }\n  if (intervals.length < 2) {\n    return {\n      pattern: "insufficient_data",\n      confidence: "low",\n      representativeCycleLength: configuredCycleLength,\n      reason:\n        "برای برآورد باروری به ثبت چند چرخه نیاز داریم؛ فعلاً فقط زمان دوره به‌صورت تقریبی نمایش داده می‌شود.",\n    };\n  }\n  const sorted = [...intervals].sort((a, b) => a - b);\n  const middle = Math.floor(sorted.length / 2);\n  const representative = sorted.length % 2 === 1\n    ? sorted[middle]\n    : Math.round((sorted[middle - 1] + sorted[middle]) / 2);\n  const spread = sorted[sorted.length - 1] - sorted[0];\n  const outsideTypicalRange = sorted.some((value) => value < 21 || value > 45);\n  if (spread > 7 || outsideTypicalRange) {\n    return {\n      pattern: "variable",\n      confidence: "low",\n      representativeCycleLength: representative,\n      reason:\n        "چرخه‌های ثبت‌شده متغیرند؛ زمان باروری/تخمک‌گذاری نمایش داده نمی‌شود و این تقویم تشخیص پزشکی نیست.",\n    };\n  }\n  const confidence = intervals.length >= 3 && spread <= 4 ? "high" : "medium";\n  return {\n    pattern: "regular",\n    confidence,\n    representativeCycleLength: representative,\n    reason:\n      "زمان باروری فقط یک برآورد تقویمی بر پایه چرخه‌های ثبت‌شده است و برای پیشگیری یا تشخیص پزشکی قابل اتکا نیست.",\n  };\n}'''
replace_once(server, old_calc, new_calc)

replace_once(
    server,
    '''function estimateForProfile(profile: Row): WomenCalendarEstimate | null {\n  if (!profile.enabled || !profile.last_period_start) return null;\n  return calculateWomenCalendarEstimate(\n    dateString(profile.last_period_start),\n    profile.cycle_length,\n    profile.period_length,\n  );\n}''',
    '''function estimateForProfile(\n  profile: Row,\n  episodes: Row[] = [],\n): WomenCalendarEstimate | null {\n  if (!profile.enabled || !profile.last_period_start) return null;\n  return calculateWomenCalendarEstimateFromEpisodes(\n    dateString(profile.last_period_start),\n    profile.cycle_length,\n    profile.period_length,\n    episodes.map((episode) => dateString(episode.started_on)),\n  );\n}''',
)
replace_once(
    server,
    '''      estimate: estimateForProfile(profile),''',
    '''      estimate: estimateForProfile(profile, episodes),''',
)

# CareMate consumes the server reliability contract and displays uncertainty.
replace_once(
    "caremate/lib/screens/women_calendar/care_women_calendar_screen.dart",
    '''    final phase =\n        estimate['detailedPhase']?.toString() ?? estimate['phase']?.toString();\n    final visual = _phaseVisual(phase);''',
    '''    final fertilityReliable = estimate['fertilityEstimateReliable'] == true;\n    final rawPhase =\n        estimate['detailedPhase']?.toString() ?? estimate['phase']?.toString();\n    final phase = !fertilityReliable &&\n            (rawPhase == 'fertile' || rawPhase == 'ovulation')\n        ? 'follicular'\n        : rawPhase;\n    final uncertaintyReason = estimate['uncertaintyReason']?.toString().trim();\n    final visual = _phaseVisual(phase);''',
)
replace_once(
    "caremate/lib/screens/women_calendar/care_women_calendar_screen.dart",
    '''              Text(\n                daysLeft == null\n                    ? 'اطلاعات کافی برای برآورد وجود ندارد.'\n                    : 'حدود ${localizeDigits(context, daysLeft)} روز تا شروع تخمینی دوره بعدی',\n                style: const TextStyle(\n                  fontSize: 11,\n                  height: 1.45,\n                  color: AppColors.secondaryText,\n                ),\n              ),''',
    '''              Text(\n                daysLeft == null\n                    ? 'اطلاعات کافی برای برآورد وجود ندارد.'\n                    : 'حدود ${localizeDigits(context, daysLeft)} روز تا شروع تخمینی دوره بعدی',\n                style: const TextStyle(\n                  fontSize: 11,\n                  height: 1.45,\n                  color: AppColors.secondaryText,\n                ),\n              ),\n              if (!fertilityReliable &&\n                  uncertaintyReason != null &&\n                  uncertaintyReason.isNotEmpty) ...[\n                const SizedBox(height: 7),\n                Text(\n                  uncertaintyReason,\n                  style: const TextStyle(\n                    fontSize: 10.5,\n                    height: 1.45,\n                    color: AppColors.secondaryText,\n                  ),\n                ),\n              ],''',
)

# Server tests: fixed input must be low confidence; stable history enables the
# estimate; variable history suppresses it.
test_path = ROOT / "supabase/functions/lifemate-api/women_calendar_test.ts"
text = test_path.read_text(encoding="utf-8")
text = text.replace(
    'import { calculateWomenCalendarEstimate } from "./women_calendar.ts";',
    'import { calculateWomenCalendarEstimate, calculateWomenCalendarEstimateFromEpisodes } from "./women_calendar.ts";',
    1,
)
if 'server cycle history enables fertility only for stable repeated intervals' not in text:
    text += r'''

Deno.test("server cycle history suppresses fertility with insufficient history", () => {
  const estimate = calculateWomenCalendarEstimateFromEpisodes(
    "2026-08-01",
    28,
    5,
    ["2026-07-04", "2026-08-01"],
    new Date("2026-08-14T00:00:00Z"),
  );
  assertEquals(estimate.confidence, "low");
  assertEquals(estimate.cyclePattern, "insufficient_data");
  assertEquals(estimate.fertilityEstimateReliable, false);
  assertEquals(["fertile", "ovulation"].includes(estimate.detailedPhase), false);
});

Deno.test("server cycle history enables fertility only for stable repeated intervals", () => {
  const estimate = calculateWomenCalendarEstimateFromEpisodes(
    "2026-08-01",
    28,
    5,
    ["2026-05-09", "2026-06-06", "2026-07-04", "2026-08-01"],
    new Date("2026-08-14T00:00:00Z"),
  );
  assertEquals(estimate.cyclePattern, "regular");
  assertEquals(estimate.confidence, "high");
  assertEquals(estimate.fertilityEstimateReliable, true);
});

Deno.test("server variable cycle history suppresses fertility timing", () => {
  const estimate = calculateWomenCalendarEstimateFromEpisodes(
    "2026-08-01",
    28,
    5,
    ["2026-05-01", "2026-05-25", "2026-07-04", "2026-08-01"],
    new Date("2026-08-14T00:00:00Z"),
  );
  assertEquals(estimate.cyclePattern, "variable");
  assertEquals(estimate.confidence, "low");
  assertEquals(estimate.fertilityEstimateReliable, false);
  assertEquals(["fertile", "ovulation"].includes(estimate.detailedPhase), false);
});
'''
test_path.write_text(text, encoding="utf-8")
