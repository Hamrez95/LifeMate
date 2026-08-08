from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / 'supabase/functions/lifemate-api/women_calendar.ts'
text = PATH.read_text(encoding='utf-8')


def replace_once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'expected one women backend match, found {count}: {old[:120]!r}')
    text = text.replace(old, new, 1)


replace_once(
    '''    assertCanonicalWomenDailyLogPayload(body);
    const hasDailyCheckIn = false;
    const requestedDailyCheckIn: DailyCheckIn | undefined = undefined;
    const now = new Date();''',
    '''    assertCanonicalWomenDailyLogPayload(body);
    const now = new Date();''',
)

replace_once(
    '''        const daily = requestedDailyCheckIn ?? null;
        const rows = await tx`
          insert into lifemate.women_calendar_profiles
            (owner_user_id, enabled, last_period_start, cycle_length,
             period_length, reminders_enabled, algorithm_version, version,
             daily_check_in_date, daily_mood, daily_energy, daily_symptoms,
             daily_support_need, daily_private_note, share_daily_summary,
             created_at_utc, updated_at_utc)
          values
            (${userId}, ${enabled}, ${lastPeriodStart}, ${cycleLength},
             ${periodLength}, ${remindersEnabled}, 'calendar-estimate-v1', 1,
             ${daily?.date ?? null}, ${daily?.mood ?? null},
             ${daily?.energy ?? null}, ${daily?.symptoms ?? []},
             ${daily?.supportNeed ?? null}, ${daily?.privateNote ?? null},
             ${daily?.shareSummary ?? false}, ${now}, ${now})
          returning *
        `;
        await insertAudit(
          tx,
          userId,
          daily == null
            ? "women_calendar.profile_created"
            : "women_calendar.profile_and_check_in_created",
          "women_calendar_profile",
          userId,
        );''',
    '''        const rows = await tx`
          insert into lifemate.women_calendar_profiles
            (owner_user_id, enabled, last_period_start, cycle_length,
             period_length, reminders_enabled, algorithm_version, version,
             created_at_utc, updated_at_utc)
          values
            (${userId}, ${enabled}, ${lastPeriodStart}, ${cycleLength},
             ${periodLength}, ${remindersEnabled}, 'calendar-estimate-v1', 1,
             ${now}, ${now})
          returning *
        `;
        await insertAudit(
          tx,
          userId,
          "women_calendar.profile_created",
          "women_calendar_profile",
          userId,
        );''',
)

replace_once(
    '''
      finalDailyCheckIn:
      {
        // A labeled block keeps the preservation rule visually explicit:
        // omitted dailyCheckIn means settings-only update; null means clear.
      }
      const daily = hasDailyCheckIn
        ? requestedDailyCheckIn
        : dailyCheckInFromRow(existing);
      const rows = await tx`
        update lifemate.women_calendar_profiles
        set enabled = ${enabled}, last_period_start = ${lastPeriodStart},
            cycle_length = ${cycleLength}, period_length = ${periodLength},
            reminders_enabled = ${remindersEnabled},
            daily_check_in_date = ${daily?.date ?? null},
            daily_mood = ${daily?.mood ?? null},
            daily_energy = ${daily?.energy ?? null},
            daily_symptoms = ${daily?.symptoms ?? []},
            daily_support_need = ${daily?.supportNeed ?? null},
            daily_private_note = ${daily?.privateNote ?? null},
            share_daily_summary = ${daily?.shareSummary ?? false},
            version = version + 1, updated_at_utc = ${now}
        where owner_user_id = ${userId}
        returning *
      `;
      await insertAudit(
        tx,
        userId,
        hasDailyCheckIn
          ? "women_calendar.daily_check_in_updated"
          : enabled
          ? "women_calendar.profile_enabled_or_updated"
          : "women_calendar.profile_disabled",
        "women_calendar_profile",
        userId,
      );''',
    '''
      const rows = await tx`
        update lifemate.women_calendar_profiles
        set enabled = ${enabled}, last_period_start = ${lastPeriodStart},
            cycle_length = ${cycleLength}, period_length = ${periodLength},
            reminders_enabled = ${remindersEnabled},
            version = version + 1, updated_at_utc = ${now}
        where owner_user_id = ${userId}
        returning *
      `;
      await insertAudit(
        tx,
        userId,
        enabled
          ? "women_calendar.profile_enabled_or_updated"
          : "women_calendar.profile_disabled",
        "women_calendar_profile",
        userId,
      );''',
)

PATH.write_text(text, encoding='utf-8')
Path(__file__).unlink()
print('women profile writes now contain persistent configuration only')
