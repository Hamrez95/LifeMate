from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace(path: str, old: str, new: str) -> None:
    text = read(path)
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"Expected snippet missing in {path}: {old[:150]!r}")
    write(path, text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# WellMate estimators: use recorded episode starts in both production routes.
# ---------------------------------------------------------------------------
replace(
    "wellmate/lib/screens/women_calendar/women_calendar_screen.dart",
    '''    return WomenCalendarEstimate.calculate(\n      lastPeriodStart: start,\n      cycleLength: _cycleLength,\n      periodLength: _periodLength,\n    );''',
    '''    final periodStarts = _episodes\n        .map((episode) => DateTime.tryParse(episode['startedOn']?.toString() ?? ''))\n        .whereType<DateTime>()\n        .toList(growable: false);\n    return WomenCalendarEstimate.calculateFromEpisodes(\n      lastPeriodStart: start,\n      configuredCycleLength: _cycleLength,\n      periodLength: _periodLength,\n      periodStarts: periodStarts,\n    );''',
)

replace(
    "wellmate/lib/screens/women_calendar/women_companion_screen.dart",
    '''    return WomenCalendarEstimate.calculate(\n                lastPeriodStart: start,\n                cycleLength: _profile['cycleLength'] is int\n                    ? _profile['cycleLength'] as int\n                    : 28,\n                periodLength: _profile['periodLength'] is int\n                    ? _profile['periodLength'] as int\n                    : 5,\n              );''',
    '''    final periodStarts = _episodes\n                .map((episode) => DateTime.tryParse(episode['startedOn']?.toString() ?? ''))\n                .whereType<DateTime>()\n                .toList(growable: false);\n              return WomenCalendarEstimate.calculateFromEpisodes(\n                lastPeriodStart: start,\n                configuredCycleLength: _profile['cycleLength'] is int\n                    ? _profile['cycleLength'] as int\n                    : 28,\n                periodLength: _profile['periodLength'] is int\n                    ? _profile['periodLength'] as int\n                    : 5,\n                periodStarts: periodStarts,\n              );''',
)

# ---------------------------------------------------------------------------
# WellMate visuals: when fertility is unreliable, never draw a fertile or
# ovulation segment and never show an ovulation countdown.
# ---------------------------------------------------------------------------
experience = "wellmate/lib/screens/women_calendar/women_calendar_experience_widgets.dart"
replace(
    experience,
    '''  final follicular = WomenCycleSegment(\n    startDay: period.endDay + 1,\n    endDay: estimate.fertileWindowStartDay - 1,\n    phase: WomenCalendarDetailedPhase.follicular,\n    color: const Color(0xFFF0A643),\n  );''',
    '''  if (!estimate.fertilityEstimateReliable) {\n    final pmsStart = math.max(estimate.periodLength + 1, estimate.cycleLength - 4);\n    return [\n      period,\n      WomenCycleSegment(\n        startDay: period.endDay + 1,\n        endDay: pmsStart - 1,\n        phase: WomenCalendarDetailedPhase.follicular,\n        color: const Color(0xFFF0A643),\n      ),\n      WomenCycleSegment(\n        startDay: pmsStart,\n        endDay: estimate.cycleLength,\n        phase: WomenCalendarDetailedPhase.pms,\n        color: const Color(0xFFEE7991),\n      ),\n    ].where((segment) => segment.startDay <= segment.endDay).toList(growable: false);\n  }\n\n  final follicular = WomenCycleSegment(\n    startDay: period.endDay + 1,\n    endDay: estimate.fertileWindowStartDay - 1,\n    phase: WomenCalendarDetailedPhase.follicular,\n    color: const Color(0xFFF0A643),\n  );''',
)
replace(
    experience,
    '''                _CycleMetric(\n                  icon: Icons.local_florist_outlined,\n                  color: womenLilac,\n                  label:\n                      '${localizeDigits(context, math.max(0, value.ovulationDay - value.cycleDay))} روز تا تخمک‌گذاری تخمینی',\n                ),''',
    '''                _CycleMetric(\n                  icon: value.fertilityEstimateReliable\n                      ? Icons.local_florist_outlined\n                      : Icons.info_outline_rounded,\n                  color: womenLilac,\n                  label: value.fertilityEstimateReliable\n                      ? '${localizeDigits(context, math.max(0, value.ovulationDay - value.cycleDay))} روز تا تخمک‌گذاری تخمینی'\n                      : 'فعلاً داده کافی برای نمایش زمان باروری نداریم',\n                ),''',
)

month = "wellmate/lib/screens/women_calendar/women_calendar_month_card.dart"
replace(
    month,
    '''    final segments = <_CycleSegment>[\n      _CycleSegment(1, estimate.periodLength, _periodColor),\n      _CycleSegment(\n        estimate.periodLength + 1,\n        estimate.fertileWindowStartDay - 1,\n        _follicularColor,\n      ),\n      _CycleSegment(\n        estimate.fertileWindowStartDay,\n        estimate.ovulationDay - 1,\n        _fertileColor,\n      ),\n      _CycleSegment(\n        estimate.ovulationDay,\n        estimate.fertileWindowEndDay,\n        _ovulationColor,\n      ),\n      _CycleSegment(\n        estimate.fertileWindowEndDay + 1,\n        pmsStart - 1,\n        _lutealColor,\n      ),\n      _CycleSegment(pmsStart, estimate.cycleLength, _pmsColor),\n    ];''',
    '''    final segments = estimate.fertilityEstimateReliable\n        ? <_CycleSegment>[\n            _CycleSegment(1, estimate.periodLength, _periodColor),\n            _CycleSegment(\n              estimate.periodLength + 1,\n              estimate.fertileWindowStartDay - 1,\n              _follicularColor,\n            ),\n            _CycleSegment(\n              estimate.fertileWindowStartDay,\n              estimate.ovulationDay - 1,\n              _fertileColor,\n            ),\n            _CycleSegment(\n              estimate.ovulationDay,\n              estimate.fertileWindowEndDay,\n              _ovulationColor,\n            ),\n            _CycleSegment(\n              estimate.fertileWindowEndDay + 1,\n              pmsStart - 1,\n              _lutealColor,\n            ),\n            _CycleSegment(pmsStart, estimate.cycleLength, _pmsColor),\n          ]\n        : <_CycleSegment>[\n            _CycleSegment(1, estimate.periodLength, _periodColor),\n            _CycleSegment(estimate.periodLength + 1, pmsStart - 1, _follicularColor),\n            _CycleSegment(pmsStart, estimate.cycleLength, _pmsColor),\n          ];''',
)

# ---------------------------------------------------------------------------
# Server contract: expose confidence and derive it from actual recorded period
# starts for the caregiver summary. The old fixed estimator remains a safe low-
# confidence fallback for callers that do not supply history.
# ---------------------------------------------------------------------------
server = "supabase/functions/lifemate-api/women_calendar.ts"
replace(
    server,
    '''  algorithmVersion: "calendar-estimate-v1";\n};''',
    '''  algorithmVersion: "calendar-estimate-v1";\n  confidence: "low" | "medium" | "high";\n  cyclePattern: "insufficient_data" | "regular" | "variable";\n  fertilityEstimateReliable: boolean;\n  uncertaintyReason: string;\n};''',
)

text = read(server)
if "export function calculateWomenCalendarEstimateFromEpisodes(" not in text:
    match = re.search(
        r"export function calculateWomenCalendarEstimate\([\s\S]*?\n}\n\nfunction mapProfile",
        text,
    )
    if not match:
        raise SystemExit("Could not locate server calendar estimator block")
    new_calc = r'''export function calculateWomenCalendarEstimate(
  lastPeriodStart: string,
  cycleLength: number,
  periodLength: number,
  todayValue = new Date(),
): WomenCalendarEstimate {
  return calculateCalendarCore(
    lastPeriodStart,
    cycleLength,
    periodLength,
    todayValue,
    {
      confidence: "low",
      pattern: "insufficient_data",
      reliable: false,
      reason:
        "ثبت‌های کافی برای برآورد باروری وجود ندارد؛ این تقویم تقریبی است و تشخیص پزشکی نیست.",
    },
  );
}

export function calculateWomenCalendarEstimateFromEpisodes(
  lastPeriodStart: string,
  configuredCycleLength: number,
  periodLength: number,
  periodStarts: string[],
  todayValue = new Date(),
): WomenCalendarEstimate {
  const assessment = assessCycleHistory(periodStarts, configuredCycleLength);
  return calculateCalendarCore(
    lastPeriodStart,
    assessment.representativeCycleLength,
    periodLength,
    todayValue,
    {
      confidence: assessment.confidence,
      pattern: assessment.pattern,
      reliable:
        assessment.pattern === "regular" && assessment.confidence !== "low",
      reason: assessment.reason,
    },
  );
}

function calculateCalendarCore(
  lastPeriodStart: string,
  cycleLength: number,
  periodLength: number,
  todayValue: Date,
  safety: {
    confidence: "low" | "medium" | "high";
    pattern: "insufficient_data" | "regular" | "variable";
    reliable: boolean;
    reason: string;
  },
): WomenCalendarEstimate {
  const start = parseDateOnly(lastPeriodStart);
  const today = new Date(Date.UTC(
    todayValue.getUTCFullYear(),
    todayValue.getUTCMonth(),
    todayValue.getUTCDate(),
  ));
  const rawDiff = Math.floor((today.getTime() - start.getTime()) / 86_400_000);
  const cyclesElapsed = rawDiff < 0 ? 0 : Math.floor(rawDiff / cycleLength);
  let cycleStart = addDays(start, cyclesElapsed * cycleLength);
  if (cycleStart > today) cycleStart = start;
  const cycleDay = Math.max(
    1,
    Math.floor((today.getTime() - cycleStart.getTime()) / 86_400_000) + 1,
  );
  const nextPeriodStart = addDays(cycleStart, cycleLength);
  const daysUntilNextPeriod = Math.max(
    0,
    Math.floor((nextPeriodStart.getTime() - today.getTime()) / 86_400_000),
  );
  const ovulationDay = clamp(
    cycleLength - 14,
    periodLength + 2,
    cycleLength - 5,
  );
  const fertileWindowStartDay = clamp(
    ovulationDay - 5,
    periodLength + 1,
    ovulationDay,
  );
  const fertileWindowEndDay = clamp(
    ovulationDay + 1,
    ovulationDay,
    cycleLength,
  );
  const pmsStartDay = clamp(
    cycleLength - 4,
    fertileWindowEndDay + 1,
    cycleLength,
  );
  const rawDetailedPhase = phaseForCycleDay(
    cycleDay,
    periodLength,
    ovulationDay,
    fertileWindowStartDay,
    fertileWindowEndDay,
    pmsStartDay,
  );
  const detailedPhase: DetailedPhase = !safety.reliable &&
      (rawDetailedPhase === "fertile" || rawDetailedPhase === "ovulation")
    ? (cycleDay <= ovulationDay ? "follicular" : "luteal")
    : rawDetailedPhase;
  const estimatedBleeding = detailedPhase === "period";
  const phase = detailedPhase === "period"
    ? "period"
    : detailedPhase === "follicular"
    ? "post_period"
    : detailedPhase === "pms"
    ? "pre_period"
    : "cycle";
  return {
    cycleStart: formatDateOnly(cycleStart),
    cycleDay,
    cycleLength,
    periodLength,
    estimatedBleeding,
    phase,
    detailedPhase,
    ovulationDay,
    fertileWindowStartDay,
    fertileWindowEndDay,
    pmsStartDay,
    nextPeriodStart: formatDateOnly(nextPeriodStart),
    daysUntilNextPeriod,
    algorithmVersion: "calendar-estimate-v1",
    confidence: safety.confidence,
    cyclePattern: safety.pattern,
    fertilityEstimateReliable: safety.reliable,
    uncertaintyReason: safety.reason,
  };
}

function assessCycleHistory(
  periodStarts: string[],
  configuredCycleLength: number,
): {
  pattern: "insufficient_data" | "regular" | "variable";
  confidence: "low" | "medium" | "high";
  representativeCycleLength: number;
  reason: string;
} {
  const starts = Array.from(new Set(periodStarts))
    .map(parseDateOnly)
    .sort((a, b) => a.getTime() - b.getTime());
  const intervals: number[] = [];
  for (let index = 1; index < starts.length; index++) {
    const days = Math.round(
      (starts[index].getTime() - starts[index - 1].getTime()) / 86_400_000,
    );
    if (days >= 15 && days <= 90) intervals.push(days);
  }
  if (intervals.length < 2) {
    return {
      pattern: "insufficient_data",
      confidence: "low",
      representativeCycleLength: configuredCycleLength,
      reason:
        "برای برآورد باروری به ثبت چند چرخه نیاز داریم؛ فعلاً فقط زمان دوره به‌صورت تقریبی نمایش داده می‌شود.",
    };
  }
  const sorted = [...intervals].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  const representativeCycleLength = sorted.length % 2 === 1
    ? sorted[middle]
    : Math.round((sorted[middle - 1] + sorted[middle]) / 2);
  const spread = sorted[sorted.length - 1] - sorted[0];
  const outsideTypicalRange = sorted.some((value) => value < 21 || value > 45);
  if (spread > 7 || outsideTypicalRange) {
    return {
      pattern: "variable",
      confidence: "low",
      representativeCycleLength,
      reason:
        "چرخه‌های ثبت‌شده متغیرند؛ زمان باروری/تخمک‌گذاری نمایش داده نمی‌شود و این تقویم تشخیص پزشکی نیست.",
    };
  }
  const confidence = intervals.length >= 3 && spread <= 4 ? "high" : "medium";
  return {
    pattern: "regular",
    confidence,
    representativeCycleLength,
    reason:
      "زمان باروری فقط یک برآورد تقویمی بر پایه چرخه‌های ثبت‌شده است و برای پیشگیری یا تشخیص پزشکی قابل اتکا نیست.",
  };
}

function mapProfile'''
    text = text[:match.start()] + new_calc + text[match.end():]
    write(server, text)

replace(
    server,
    '''    const profile = mapProfile(profiles[0]);\n    const canonicalSharedLog = sharedLogs[0]''',
    '''    const profile = mapProfile(profiles[0]);\n    const estimate = calculateWomenCalendarEstimateFromEpisodes(\n      dateString(profiles[0].last_period_start),\n      profiles[0].cycle_length,\n      profiles[0].period_length,\n      episodes.map((episode: Row) => dateString(episode.started_on)),\n    );\n    const canonicalSharedLog = sharedLogs[0]''',
)
replace(
    server,
    '''      estimate: profile.estimate,\n      sharedDailySummary,''',
    '''      estimate,\n      sharedDailySummary,''',
)

# ---------------------------------------------------------------------------
# CareMate gates any old/raw fertility phase and surfaces the reason.
# ---------------------------------------------------------------------------
care = "caremate/lib/screens/women_calendar/care_women_calendar_screen.dart"
replace(
    care,
    '''    final phase =\n        estimate['detailedPhase']?.toString() ?? estimate['phase']?.toString();\n    final visual = _phaseVisual(phase);''',
    '''    final fertilityReliable = estimate['fertilityEstimateReliable'] == true;\n    final rawPhase =\n        estimate['detailedPhase']?.toString() ?? estimate['phase']?.toString();\n    final phase = !fertilityReliable &&\n            (rawPhase == 'fertile' || rawPhase == 'ovulation')\n        ? 'follicular'\n        : rawPhase;\n    final uncertaintyReason = estimate['uncertaintyReason']?.toString().trim();\n    final visual = _phaseVisual(phase);''',
)
replace(
    care,
    '''              Text(\n                daysLeft == null\n                    ? 'اطلاعات کافی برای برآورد وجود ندارد.'\n                    : 'حدود ${localizeDigits(context, daysLeft)} روز تا شروع تخمینی دوره بعدی',\n                style: const TextStyle(\n                  fontSize: 11,\n                  height: 1.45,\n                  color: AppColors.secondaryText,\n                ),\n              ),\n            ],''',
    '''              Text(\n                daysLeft == null\n                    ? 'اطلاعات کافی برای برآورد وجود ندارد.'\n                    : 'حدود ${localizeDigits(context, daysLeft)} روز تا شروع تخمینی دوره بعدی',\n                style: const TextStyle(\n                  fontSize: 11,\n                  height: 1.45,\n                  color: AppColors.secondaryText,\n                ),\n              ),\n              if (!fertilityReliable &&\n                  uncertaintyReason != null &&\n                  uncertaintyReason.isNotEmpty) ...[\n                const SizedBox(height: 7),\n                Text(\n                  uncertaintyReason,\n                  style: const TextStyle(\n                    fontSize: 10.5,\n                    height: 1.45,\n                    color: AppColors.secondaryText,\n                  ),\n                ),\n              ],\n            ],''',
)

# ---------------------------------------------------------------------------
# Edge tests for insufficient, stable and variable histories.
# ---------------------------------------------------------------------------
test = "supabase/functions/lifemate-api/women_calendar_test.ts"
t = read(test)
if "calculateWomenCalendarEstimateFromEpisodes" not in t.split("\n", 10)[0:10].__str__():
    t = t.replace(
        'import { calculateWomenCalendarEstimate } from "./women_calendar.ts";',
        'import { calculateWomenCalendarEstimate, calculateWomenCalendarEstimateFromEpisodes } from "./women_calendar.ts";',
        1,
    )
if "server cycle history enables fertility only for stable repeated intervals" not in t:
    t += r'''

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
write(test, t)
