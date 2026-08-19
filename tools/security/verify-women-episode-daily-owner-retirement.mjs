import { readFileSync } from "node:fs";

const migration = readFileSync(
  "supabase/migrations/20260819152200_retire_women_episode_daily_owner_user_storage.sql",
  "utf8",
);
const runtime = readFileSync(
  "supabase/functions/lifemate-api/person_women_calendar.ts",
  "utf8",
);

for (const marker of [
  "alter column owner_person_id set not null",
  "alter column owner_user_id drop not null",
  "uq_women_calendar_episode_person_start",
  "uq_women_calendar_daily_person_log",
  "trg_00_retire_canonical_women_owner_user",
  "before insert on lifemate.women_calendar_episodes",
  "before insert on lifemate.women_calendar_daily_logs",
  "if new.owner_person_id is not null then",
  "new.owner_user_id := null",
  "women_calendar_episode_person_backfill_incomplete",
  "women_calendar_daily_person_backfill_incomplete",
]) {
  if (!migration.includes(marker)) {
    throw new Error(`Women owner retirement contract is missing: ${marker}`);
  }
}

for (const legacyConstraint of [
  "uq_women_calendar_episode_start",
  "uq_women_calendar_daily_log",
]) {
  if (new RegExp(`drop\\s+(constraint|index)[^;]*${legacyConstraint}`, "i").test(migration)) {
    throw new Error(
      `Staged retirement must preserve legacy compatibility uniqueness: ${legacyConstraint}`,
    );
  }
}

if (/before\s+update[^;]*retire_canonical_women_owner_user/i.test(migration)) {
  throw new Error(
    "Owner retirement trigger must stay INSERT-only so historical linkage is never scrubbed accidentally.",
  );
}
if (/\b(delete\s+from|truncate)\s+lifemate\.women_calendar_(episodes|daily_logs)/i.test(migration)) {
  throw new Error("Women owner retirement migration must not delete historical rows.");
}

for (const marker of [
  "where owner_person_id = ${personId}::uuid",
  "createOwnerEpisode",
  "upsertOwnerDailyLog",
]) {
  if (!runtime.includes(marker)) {
    throw new Error(`Person-authoritative runtime boundary is missing: ${marker}`);
  }
}

console.log("Women Calendar episode/daily owner retirement boundary verified.");
