import { readFileSync } from "node:fs";

const migration = readFileSync(
  "supabase/migrations/20260819154000_women_profile_person_primary_key.sql",
  "utf8",
);

for (const marker of [
  "women_calendar_profile_person_backfill_incomplete",
  "women_calendar_profile_person_ownership_ambiguous",
  "uq_women_calendar_profile_owner_user",
  "alter column owner_person_id set not null",
  "alter column owner_user_id drop not null",
  "add constraint women_calendar_profiles_pkey primary key(owner_person_id)",
  "canonicalize_women_profile_audit_resource",
  "new.resource_id := v_person_id",
]) {
  if (!migration.includes(marker)) {
    throw new Error(`Women profile Person-primary contract is missing: ${marker}`);
  }
}

if (/\b(delete\s+from|truncate|update)\s+lifemate\.women_calendar_profiles/i.test(migration)) {
  throw new Error(
    "Women profile Person-primary migration must not rewrite/delete historical profiles.",
  );
}
if (/drop\s+(index|constraint)[^;]*uq_women_calendar_profile_owner_user/i.test(migration)) {
  throw new Error(
    "Women profile staged migration must preserve legacy owner-user uniqueness.",
  );
}
if (/owner_user_id\s*:=\s*null|set\s+owner_user_id\s*=\s*null/i.test(migration)) {
  throw new Error(
    "Phase 1 must not scrub the compatibility owner value before rollback readiness.",
  );
}

console.log("Women Calendar profile Person-primary policy verified.");
