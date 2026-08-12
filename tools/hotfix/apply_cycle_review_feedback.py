from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def patch(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"Expected snippet missing in {path}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


patch(
    "wellmate/lib/screens/women_calendar/women_companion_screen.dart",
    """    final sections = <(int, Color)>[
      (value.periodLength, const Color(0xFFF15D7B)),
      (
        (value.fertileWindowStartDay - value.periodLength - 1)
            .clamp(0, value.cycleLength)
            .toInt(),
        const Color(0xFFBA8CE2),
      ),
      (
        (value.fertileWindowEndDay - value.fertileWindowStartDay + 1)
            .clamp(0, value.cycleLength)
            .toInt(),
        const Color(0xFF58C8B8),
      ),
      (
        (value.pmsStartDay - value.fertileWindowEndDay - 1)
            .clamp(0, value.cycleLength)
            .toInt(),
        const Color(0xFFF5BE58),
      ),
      (
        (value.cycleLength - value.pmsStartDay + 1)
            .clamp(0, value.cycleLength)
            .toInt(),
        const Color(0xFFE98A75),
      ),
    ];""",
    """    final sections = value.fertilityEstimateReliable
        ? <(int, Color)>[
            (value.periodLength, const Color(0xFFF15D7B)),
            (
              (value.fertileWindowStartDay - value.periodLength - 1)
                  .clamp(0, value.cycleLength)
                  .toInt(),
              const Color(0xFFBA8CE2),
            ),
            (
              (value.fertileWindowEndDay - value.fertileWindowStartDay + 1)
                  .clamp(0, value.cycleLength)
                  .toInt(),
              const Color(0xFF58C8B8),
            ),
            (
              (value.pmsStartDay - value.fertileWindowEndDay - 1)
                  .clamp(0, value.cycleLength)
                  .toInt(),
              const Color(0xFFF5BE58),
            ),
            (
              (value.cycleLength - value.pmsStartDay + 1)
                  .clamp(0, value.cycleLength)
                  .toInt(),
              const Color(0xFFE98A75),
            ),
          ]
        : <(int, Color)>[
            (value.periodLength, const Color(0xFFF15D7B)),
            (
              (value.pmsStartDay - value.periodLength - 1)
                  .clamp(0, value.cycleLength)
                  .toInt(),
              const Color(0xFFBA8CE2),
            ),
            (
              (value.cycleLength - value.pmsStartDay + 1)
                  .clamp(0, value.cycleLength)
                  .toInt(),
              const Color(0xFFE98A75),
            ),
          ];""",
)

patch(
    "wellmate/test/women_calendar_month_card_test.dart",
    """      final estimate = WomenCalendarEstimate.calculate(
        lastPeriodStart: DateTime(2026, 8, 1),
        cycleLength: 28,
        periodLength: 5,
        today: DateTime(2026, 8, 4),
      );""",
    """      final estimate = WomenCalendarEstimate.calculateFromEpisodes(
        lastPeriodStart: DateTime(2026, 8, 1),
        configuredCycleLength: 28,
        periodLength: 5,
        periodStarts: [
          DateTime(2026, 5, 9),
          DateTime(2026, 6, 6),
          DateTime(2026, 7, 4),
          DateTime(2026, 8, 1),
        ],
        today: DateTime(2026, 8, 4),
      );""",
)

patch(
    "supabase/functions/lifemate-api/women_calendar.ts",
    """  const usable = intervals.filter((value) => value >= 21 && value <= 45);
  const source = usable.length === 0 ? intervals : usable;
  const sorted = [...source].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  const representativeCycleLength = sorted.length % 2 === 1
    ? sorted[middle]
    : Math.round((sorted[middle - 1] + sorted[middle]) / 2);""",
    """  const usable = intervals.filter((value) => value >= 21 && value <= 45);
  const sorted = [...usable].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  const representativeCycleLength = sorted.length === 0
    ? configuredCycleLength
    : sorted.length % 2 === 1
    ? sorted[middle]
    : Math.round((sorted[middle - 1] + sorted[middle]) / 2);""",
)

patch(
    "wellmate/lib/screens/women_calendar/women_calendar_month_card.dart",
    """      oldDelegate.estimate.cycleDay != estimate.cycleDay ||
      oldDelegate.estimate.cycleLength != estimate.cycleLength ||
      oldDelegate.estimate.periodLength != estimate.periodLength ||
      oldDelegate.dayLabel != dayLabel;""",
    """      oldDelegate.estimate.cycleDay != estimate.cycleDay ||
      oldDelegate.estimate.cycleLength != estimate.cycleLength ||
      oldDelegate.estimate.periodLength != estimate.periodLength ||
      oldDelegate.estimate.fertilityEstimateReliable !=
          estimate.fertilityEstimateReliable ||
      oldDelegate.dayLabel != dayLabel;""",
)
