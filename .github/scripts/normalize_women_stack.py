from __future__ import annotations

from collections import Counter
from pathlib import Path

EDGE_PATH = Path("supabase/functions/lifemate-api/women_calendar.ts")
MIGRATIONS_PATH = Path("supabase/migrations")


def ensure_shared_daily_summary() -> None:
    text = EDGE_PATH.read_text(encoding="utf-8")
    if "const sharedDailySummary =" in text:
        return

    needle = (
        "    const profile = mapProfile(profiles[0]);\n"
        "    const patientProfile = patientProfiles[0];\n"
        "    return {\n"
    )
    replacement = (
        "    const profile = mapProfile(profiles[0]);\n"
        "    const dailyCheckIn = profile.dailyCheckIn as "
        "Record<string, unknown> | null;\n"
        "    const sharedDailySummary = dailyCheckIn?.shareSummary === true\n"
        "      ? {\n"
        "        date: dailyCheckIn.date,\n"
        "        mood: dailyCheckIn.mood,\n"
        "        energy: dailyCheckIn.energy,\n"
        "        supportNeed: dailyCheckIn.supportNeed,\n"
        "      }\n"
        "      : null;\n"
        "    const patientProfile = patientProfiles[0];\n"
        "    return {\n"
    )
    if needle not in text:
        raise RuntimeError(
            "Could not locate getCareSummary return block for sharedDailySummary repair."
        )
    EDGE_PATH.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def assert_unique_migration_versions() -> None:
    versions = [path.name[:14] for path in MIGRATIONS_PATH.glob("*.sql")]
    duplicates = sorted(
        version for version, count in Counter(versions).items() if count > 1
    )
    if duplicates:
        raise RuntimeError(
            "Duplicate Supabase migration versions: " + ", ".join(duplicates)
        )


def main() -> None:
    ensure_shared_daily_summary()
    assert_unique_migration_versions()


if __name__ == "__main__":
    main()
