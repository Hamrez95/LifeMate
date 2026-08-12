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
        raise SystemExit(f"Expected snippet missing in {path}: {old[:180]!r}")
    write(path, text.replace(old, new, 1))


# WellMate owner calendar: calculate from actual episode history.
replace_once(
    "wellmate/lib/screens/women_calendar/women_calendar_screen.dart",
    """    return WomenCalendarEstimate.calculate(\n      lastPeriodStart: start,\n      cycleLength: _cycleLength,\n      periodLength: _periodLength,\n    );""",
    """    final periodStarts = _episodes\n        .map((episode) => DateTime.tryParse(episode['startedOn']?.toString() ?? ''))\n        .whereType<DateTime>()\n        .toList(growable: false);\n    return WomenCalendarEstimate.calculateFromEpisodes(\n      lastPeriodStart: start,\n      configuredCycleLength: _cycleLength,\n      periodLength: _periodLength,\n      periodStarts: periodStarts,\n    );""",
)

# WellMate companion mode uses the same history-aware estimate.
replace_once(
    "wellmate/lib/screens/women_calendar/women_companion_screen.dart",
    """    return WomenCalendarEstimate.calculate(\n      lastPeriodStart: start,\n      cycleLength: _profile['cycleLength'] is int\n          ? _profile['cycleLength'] as int\n          : 28,\n      periodLength: _profile['periodLength'] is int\n          ? _profile['periodLength'] as int\n          : 5,\n    );""",
    """    final periodStarts = _episodes\n        .map((episode) => DateTime.tryParse(episode['startedOn']?.toString() ?? ''))\n        .whereType<DateTime>()\n        .toList(growable: false);\n    return WomenCalendarEstimate.calculateFromEpisodes(\n      lastPeriodStart: start,\n      configuredCycleLength: _profile['cycleLength'] is int\n          ? _profile['cycleLength'] as int\n          : 28,\n      periodLength: _profile['periodLength'] is int\n          ? _profile['periodLength'] as int\n          : 5,\n      periodStarts: periodStarts,\n    );""",
)

# Preserve the current hero/ring design; only simplify unsafe phase segments.
replace_once(
    "wellmate/lib/screens/women_calendar/women_calendar_experience_widgets.dart",
    """  final follicular = math.max(\n    1,\n    estimate.fertileWindowStartDay - estimate.periodLength - 1,\n  );\n  final fertile = math.max(\n    1,\n    estimate.fertileWindowEndDay - estimate.fertileWindowStartDay,\n  );\n  final luteal = math.max(\n    1,\n    estimate.pmsStartDay - estimate.fertileWindowEndDay - 1,\n  );\n  final pms = math.max(1, estimate.cycleLength - estimate.pmsStartDay + 1);\n  return [""",
    """  final pms = math.max(1, estimate.cycleLength - estimate.pmsStartDay + 1);\n  if (!estimate.fertilityEstimateReliable) {\n    final middle = math.max(\n      1,\n      estimate.pmsStartDay - estimate.periodLength - 1,\n    );\n    return [\n      WomenCycleRingSegment(\n        color: const Color(0xFFF05F78),\n        weight: estimate.periodLength.toDouble(),\n      ),\n      WomenCycleRingSegment(\n        color: const Color(0xFFB889E8),\n        weight: middle.toDouble(),\n      ),\n      WomenCycleRingSegment(\n        color: const Color(0xFFE78374),\n        weight: pms.toDouble(),\n      ),\n    ];\n  }\n  final follicular = math.max(\n    1,\n    estimate.fertileWindowStartDay - estimate.periodLength - 1,\n  );\n  final fertile = math.max(\n    1,\n    estimate.fertileWindowEndDay - estimate.fertileWindowStartDay,\n  );\n  final luteal = math.max(\n    1,\n    estimate.pmsStartDay - estimate.fertileWindowEndDay - 1,\n  );\n  return [""",
)

replace_once(
    "wellmate/lib/screens/women_calendar/women_calendar_experience_widgets.dart",
    """                _CycleMetric(\n                  icon: Icons.local_florist_outlined,\n                  color: womenLilac,\n                  label: LifeMateRuntimeLocale.select(\n                    fa: LifeMateRuntimeLocale.select(\n                      fa: '${localizeDigits(context, math.max(0, value.ovulationDay - value.cycleDay))} روز تا تخمک‌گذاری تخمینی',\n                      en: \"${localizeDigits(context, math.max(0, value.ovulationDay - value.cycleDay))} Days to Estimated Ovulation\",\n                    ),\n                    en: \"${localizeDigits(context, math.max(0, value.ovulationDay - value.cycleDay))} Days to Estimated Ovulation\",\n                  ),\n                ),""",
    """                _CycleMetric(\n                  icon: value.fertilityEstimateReliable\n                      ? Icons.local_florist_outlined\n                      : Icons.info_outline_rounded,\n                  color: womenLilac,\n                  label: value.fertilityEstimateReliable\n                      ? LifeMateRuntimeLocale.select(\n                          fa: '${localizeDigits(context, math.max(0, value.ovulationDay - value.cycleDay))} روز تا تخمک‌گذاری تخمینی',\n                          en: \"${localizeDigits(context, math.max(0, value.ovulationDay - value.cycleDay))} days to estimated ovulation\",\n                        )\n                      : LifeMateRuntimeLocale.select(\n                          fa: 'برای زمان باروری، چند دوره دیگر ثبت کن',\n                          en: 'Log a few more periods before showing fertility timing',\n                        ),\n                ),""",
)

month = "wellmate/lib/screens/women_calendar/women_calendar_month_card.dart"
replace_once(
    month,
    """    final helperText = recordedToday\n        ? LifeMateRuntimeLocale.select(\n            fa: LifeMateRuntimeLocale.select(\n              fa: 'اطلاعات امروز بر اساس دوره‌ای است که ثبت کرده‌اید.',\n              en: \"Today's information is based on the course you have registered.\",\n            ),\n            en: \"Today's information is based on the course you have registered.\",\n          )\n        : _phaseHelper(context, estimate, phase);""",
    """    final helperText = recordedToday\n        ? LifeMateRuntimeLocale.select(\n            fa: 'اطلاعات امروز بر اساس دوره‌ای است که ثبت کرده‌اید.',\n            en: \"Today's information is based on the period you recorded.\",\n          )\n        : !estimate.fertilityEstimateReliable\n        ? LifeMateRuntimeLocale.select(\n            fa: estimate.pattern == WomenCyclePattern.variable\n                ? 'چرخه‌های ثبت‌شده متغیرند؛ زمان باروری فعلاً نمایش داده نمی‌شود.'\n                : 'برای برآورد مطمئن‌تر باروری، چند شروع دوره دیگر ثبت کن.',\n            en: estimate.pattern == WomenCyclePattern.variable\n                ? 'Your recorded cycles vary, so fertility timing is hidden for now.'\n                : 'Log a few more period starts before showing fertility timing.',\n          )\n        : _phaseHelper(context, estimate, phase);""",
)

replace_once(
    month,
    """        const _PhaseLegend(),""",
    """        _PhaseLegend(showFertility: estimate.fertilityEstimateReliable),""",
)

replace_once(
    month,
    """    final segments = <_CycleSegment>[\n      _CycleSegment(1, estimate.periodLength, _periodColor),\n      _CycleSegment(\n        estimate.periodLength + 1,\n        estimate.fertileWindowStartDay - 1,\n        _follicularColor,\n      ),\n      _CycleSegment(\n        estimate.fertileWindowStartDay,\n        estimate.ovulationDay - 1,\n        _fertileColor,\n      ),\n      _CycleSegment(\n        estimate.ovulationDay,\n        estimate.ovulationDay,\n        _ovulationColor,\n      ),\n      _CycleSegment(\n        estimate.ovulationDay + 1,\n        estimate.fertileWindowEndDay,\n        _fertileColor,\n      ),\n      _CycleSegment(\n        estimate.fertileWindowEndDay + 1,\n        estimate.pmsStartDay - 1,\n        _lutealColor,\n      ),\n      _CycleSegment(estimate.pmsStartDay, estimate.cycleLength, _pmsColor),\n    ];""",
    """    final segments = estimate.fertilityEstimateReliable\n        ? <_CycleSegment>[\n            _CycleSegment(1, estimate.periodLength, _periodColor),\n            _CycleSegment(\n              estimate.periodLength + 1,\n              estimate.fertileWindowStartDay - 1,\n              _follicularColor,\n            ),\n            _CycleSegment(\n              estimate.fertileWindowStartDay,\n              estimate.ovulationDay - 1,\n              _fertileColor,\n            ),\n            _CycleSegment(estimate.ovulationDay, estimate.ovulationDay, _ovulationColor),\n            _CycleSegment(\n              estimate.ovulationDay + 1,\n              estimate.fertileWindowEndDay,\n              _fertileColor,\n            ),\n            _CycleSegment(\n              estimate.fertileWindowEndDay + 1,\n              estimate.pmsStartDay - 1,\n              _lutealColor,\n            ),\n            _CycleSegment(estimate.pmsStartDay, estimate.cycleLength, _pmsColor),\n          ]\n        : <_CycleSegment>[\n            _CycleSegment(1, estimate.periodLength, _periodColor),\n            _CycleSegment(\n              estimate.periodLength + 1,\n              estimate.pmsStartDay - 1,\n              _follicularColor,\n            ),\n            _CycleSegment(estimate.pmsStartDay, estimate.cycleLength, _pmsColor),\n          ];""",
)

replace_once(
    month,
    """class _PhaseLegend extends StatelessWidget {\n  const _PhaseLegend();\n\n  @override\n  Widget build(BuildContext context) {""",
    """class _PhaseLegend extends StatelessWidget {\n  const _PhaseLegend({required this.showFertility});\n\n  final bool showFertility;\n\n  @override\n  Widget build(BuildContext context) {""",
)

replace_once(
    month,
    """        _LegendChip(\n          label: LifeMateRuntimeLocale.select(\n            fa: LifeMateRuntimeLocale.select(fa: 'باروری', en: \"fertility\"),\n            en: \"fertility\",\n          ),\n          color: _fertileColor,\n        ),\n        _LegendChip(\n          label: LifeMateRuntimeLocale.select(\n            fa: LifeMateRuntimeLocale.select(fa: 'تخمک‌گذاری', en: \"Ovulation\"),\n            en: \"Ovulation\",\n          ),\n          color: _ovulationColor,\n        ),""",
    """        if (showFertility) ...[\n          _LegendChip(\n            label: LifeMateRuntimeLocale.select(fa: 'باروری', en: 'Fertility'),\n            color: _fertileColor,\n          ),\n          _LegendChip(\n            label: LifeMateRuntimeLocale.select(fa: 'تخمک‌گذاری', en: 'Ovulation'),\n            color: _ovulationColor,\n          ),\n        ],""",
)

replace_once(
    month,
    """          _CalendarLegend(),""",
    """          _CalendarLegend(showFertility: estimate?.fertilityEstimateReliable == true),""",
)

replace_once(
    month,
    """class _CalendarLegend extends StatelessWidget {\n  const _CalendarLegend();\n\n  @override\n  Widget build(BuildContext context) {""",
    """class _CalendarLegend extends StatelessWidget {\n  const _CalendarLegend({required this.showFertility});\n\n  final bool showFertility;\n\n  @override\n  Widget build(BuildContext context) {""",
)

# Replace the first fertility/ovulation legend pair that remains after _PhaseLegend.
text = read(month)
needle = """        _LegendChip(\n          label: LifeMateRuntimeLocale.select(\n            fa: LifeMateRuntimeLocale.select(fa: 'باروری', en: \"fertility\"),\n            en: \"fertility\",\n          ),\n          color: _fertileColor,\n        ),\n        _LegendChip(\n          label: LifeMateRuntimeLocale.select(\n            fa: LifeMateRuntimeLocale.select(fa: 'تخمک‌گذاری', en: \"Ovulation\"),\n            en: \"Ovulation\",\n          ),\n          color: _ovulationColor,\n        ),"""
replacement = """        if (showFertility) ...[\n          _LegendChip(\n            label: LifeMateRuntimeLocale.select(fa: 'باروری', en: 'Fertility'),\n            color: _fertileColor,\n          ),\n          _LegendChip(\n            label: LifeMateRuntimeLocale.select(fa: 'تخمک‌گذاری', en: 'Ovulation'),\n            color: _ovulationColor,\n          ),\n        ],"""
if needle in text:
    write(month, text.replace(needle, replacement, 1))

replace_once(
    month,
    """          Text(\n            LifeMateRuntimeLocale.select(\n              fa: LifeMateRuntimeLocale.select(\n                fa: 'این فازها بر پایه طول چرخه ثبت‌شده تخمین زده می‌شوند و برای تشخیص پزشکی یا پیشگیری از بارداری مناسب نیستند.',\n                en: \"These phases are estimated based on recorded cycle length and are not suitable for medical diagnosis or contraception.\",\n              ),\n              en: \"These phases are estimated based on recorded cycle length and are not suitable for medical diagnosis or contraception.\",\n            ),""",
    """          Text(\n            estimate?.fertilityEstimateReliable == true\n                ? LifeMateRuntimeLocale.select(\n                    fa: 'فازهای باروری فقط برآورد تقویمی‌اند و برای تشخیص پزشکی یا پیشگیری مناسب نیستند.',\n                    en: 'Fertility phases are calendar estimates only and must not be used for diagnosis or contraception.',\n                  )\n                : LifeMateRuntimeLocale.select(\n                    fa: 'قاعدگی و PMS همچنان تقریبی‌اند؛ زمان باروری تا ثبت داده کافی نمایش داده نمی‌شود.',\n                    en: 'Period and PMS timing remain approximate; fertility timing stays hidden until enough history is recorded.',\n                  ),""",
)

# CareMate: trust the server safety contract and reuse the existing summary area.
care = "caremate/lib/screens/women_calendar/care_women_calendar_screen.dart"
replace_once(
    care,
    """    final phase =\n        estimate['detailedPhase']?.toString() ?? estimate['phase']?.toString();\n    final visual = _phaseVisual(phase);""",
    """    final fertilityReliable = estimate['fertilityEstimateReliable'] == true;\n    final rawPhase =\n        estimate['detailedPhase']?.toString() ?? estimate['phase']?.toString();\n    final phase = !fertilityReliable &&\n            (rawPhase == 'fertile' || rawPhase == 'ovulation')\n        ? 'follicular'\n        : rawPhase;\n    final cyclePattern = estimate['cyclePattern']?.toString();\n    final visual = _phaseVisual(phase);""",
)

replace_once(
    care,
    """              Text(\n                daysLeft == null\n                    ? LifeMateRuntimeLocale.select(\n                        fa: 'اطلاعات کافی برای برآورد وجود ندارد.',\n                        en: \"There is not enough information to estimate.\",\n                      )\n                    : LifeMateRuntimeLocale.select(\n                        fa: 'حدود ${localizeDigits(context, daysLeft)} روز تا شروع تخمینی دوره بعدی',\n                        en: \"About ${localizeDigits(context, daysLeft)} days until the estimated start of the next period\",\n                      ),\n                style: TextStyle(\n                  fontSize: 11,\n                  height: 1.45,\n                  color: AppColors.secondaryText,\n                ),\n              ),""",
    """              Text(\n                daysLeft == null\n                    ? LifeMateRuntimeLocale.select(\n                        fa: 'اطلاعات کافی برای برآورد وجود ندارد.',\n                        en: 'There is not enough information to estimate.',\n                      )\n                    : LifeMateRuntimeLocale.select(\n                        fa: 'حدود ${localizeDigits(context, daysLeft)} روز تا شروع تخمینی دوره بعدی',\n                        en: 'About ${localizeDigits(context, daysLeft)} days until the estimated start of the next period',\n                      ),\n                style: TextStyle(\n                  fontSize: 11,\n                  height: 1.45,\n                  color: AppColors.secondaryText,\n                ),\n              ),\n              if (!fertilityReliable) ...[\n                const SizedBox(height: 6),\n                Text(\n                  LifeMateRuntimeLocale.select(\n                    fa: cyclePattern == 'variable'\n                        ? 'چرخه‌ها متغیرند؛ زمان باروری نمایش داده نمی‌شود.'\n                        : 'برای زمان باروری هنوز داده کافی ثبت نشده است.',\n                    en: cyclePattern == 'variable'\n                        ? 'Cycles vary, so fertility timing is hidden.'\n                        : 'There is not enough history to show fertility timing yet.',\n                  ),\n                  style: const TextStyle(\n                    fontSize: 10.5,\n                    height: 1.45,\n                    color: AppColors.secondaryText,\n                  ),\n                ),\n              ],""",
)

# Edge API: expose confidence and compute CareMate estimates from episode history.
server = "supabase/functions/lifemate-api/women_calendar.ts"
replace_once(
    server,
    """  algorithmVersion: \"calendar-estimate-v1\";\n};""",
    """  algorithmVersion: \"calendar-estimate-v1\";\n  confidence: \"low\" | \"medium\" | \"high\";\n  cyclePattern: \"insufficient_data\" | \"regular\" | \"variable\";\n  fertilityEstimateReliable: boolean;\n};""",
)

old_estimator = read(server)
start = old_estimator.index("export function calculateWomenCalendarEstimate(")
end = old_estimator.index("\nfunction mapProfile", start)
new_estimator = r'''export function calculateWomenCalendarEstimate(
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
    "low",
    "insufficient_data",
    false,
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
  const reliable =
    assessment.pattern === "regular" && assessment.confidence !== "low";
  return calculateCalendarCore(
    lastPeriodStart,
    assessment.representativeCycleLength,
    periodLength,
    todayValue,
    assessment.confidence,
    assessment.pattern,
    reliable,
  );
}

function calculateCalendarCore(
  lastPeriodStart: string,
  cycleLength: number,
  periodLength: number,
  todayValue: Date,
  confidence: "low" | "medium" | "high",
  cyclePattern: "insufficient_data" | "regular" | "variable",
  fertilityEstimateReliable: boolean,
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
  const detailedPhase: DetailedPhase = !fertilityEstimateReliable &&
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
    confidence,
    cyclePattern,
    fertilityEstimateReliable,
  };
}

function assessCycleHistory(
  periodStarts: string[],
  configuredCycleLength: number,
): {
  pattern: "insufficient_data" | "regular" | "variable";
  confidence: "low" | "medium" | "high";
  representativeCycleLength: number;
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
    };
  }
  const usable = intervals.filter((value) => value >= 21 && value <= 45);
  const source = usable.length === 0 ? intervals : usable;
  const sorted = [...source].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  const representativeCycleLength = sorted.length % 2 === 1
    ? sorted[middle]
    : Math.round((sorted[middle - 1] + sorted[middle]) / 2);
  const minimum = Math.min(...intervals);
  const maximum = Math.max(...intervals);
  const spread = maximum - minimum;
  const variable = spread > 7 || intervals.some((value) => value < 21 || value > 45);
  if (variable) {
    return {
      pattern: "variable",
      confidence: "low",
      representativeCycleLength: clamp(representativeCycleLength, 21, 45),
    };
  }
  return {
    pattern: "regular",
    confidence: intervals.length >= 3 && spread <= 4 ? "high" : "medium",
    representativeCycleLength,
  };
}
'''
write(server, old_estimator[:start] + new_estimator + old_estimator[end:])

replace_once(
    server,
    """    const profile = mapProfile(profiles[0]);\n    const canonicalSharedLog = sharedLogs[0]""",
    """    const profile = mapProfile(profiles[0]);\n    const estimate = calculateWomenCalendarEstimateFromEpisodes(\n      dateString(profiles[0].last_period_start),\n      profiles[0].cycle_length,\n      profiles[0].period_length,\n      episodes.map((episode: Row) => dateString(episode.started_on)),\n    );\n    const canonicalSharedLog = sharedLogs[0]""",
)
replace_once(server, """      estimate: profile.estimate,""", """      estimate,""")

# Edge unit tests.
test = "supabase/functions/lifemate-api/women_calendar_test.ts"
text = read(test)
text = text.replace(
    'import { calculateWomenCalendarEstimate } from "./women_calendar.ts";',
    'import { calculateWomenCalendarEstimate, calculateWomenCalendarEstimateFromEpisodes } from "./women_calendar.ts";',
    1,
)
if "cycle history enables fertility only for stable repeated intervals" not in text:
    text += r'''

Deno.test("cycle history with insufficient data suppresses fertility timing", () => {
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

Deno.test("cycle history enables fertility only for stable repeated intervals", () => {
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

Deno.test("variable cycle history suppresses fertility timing", () => {
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
write(test, text)
