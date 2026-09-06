from pathlib import Path

# Person-primary contract: omitted sharing is private on insert and preserves
# the canonical sharing bit on update.
path = Path("supabase/functions/lifemate-api/person_women_calendar.ts")
text = path.read_text()
old = '''    const shareSummaryWithCompanion = requiredBoolean(
      body.shareSummaryWithCompanion,
      "shareSummaryWithCompanion",
    );'''
new = '''    const shareSummaryProvided = Object.hasOwn(
      body,
      "shareSummaryWithCompanion",
    );
    const shareSummaryWithCompanion = shareSummaryProvided
      ? requiredBoolean(
        body.shareSummaryWithCompanion,
        "shareSummaryWithCompanion",
      )
      : null;'''
if old not in text:
    raise SystemExit("person share validation seam changed")
text = text.replace(old, new, 1)
old = '''             ${symptoms}, ${privateNotes}, ${shareSummaryWithCompanion},
             1, ${now}, ${now})'''
new = '''             ${symptoms}, ${privateNotes}, ${shareSummaryWithCompanion ?? false},
             1, ${now}, ${now})'''
if old not in text:
    raise SystemExit("person insert share seam changed")
text = text.replace(old, new, 1)
old = '''              private_notes = ${privateNotes},
              share_summary_with_companion = ${shareSummaryWithCompanion},
              version = version + 1, updated_at_utc = ${now}'''
new = '''              private_notes = ${privateNotes},
              share_summary_with_companion = case
                when ${shareSummaryProvided}
                  then ${shareSummaryWithCompanion}
                else share_summary_with_companion
              end,
              version = version + 1, updated_at_utc = ${now}'''
if old not in text:
    raise SystemExit("person update share seam changed")
path.write_text(text)

# Rich/product routing: complete daily check-ins belong to the person-primary
# contract even when pain/symptoms/private notes are present.
path = Path("supabase/functions/lifemate-api/women_calendar_rich_period.ts")
text = path.read_text()
old = '''    const hasRichPeriodPatch = [
      "periodFlow",
      "bloodAppearance",
      "bloodTexture",
      "painLevel",
      "symptoms",
      "privateNotes",
      "delete",
    ].some((key) => Object.hasOwn(body, key));
    if (!hasRichPeriodPatch) {
      return await base.upsertOwnerDailyLog(appUserId, body);
    }
'''
new = '''    const writeMode = classifyWomenDailyLogWrite(body);
    if (writeMode === "owner_check_in") {
      return await base.upsertOwnerDailyLog(appUserId, body);
    }
'''
if old not in text:
    raise SystemExit("rich routing seam changed")
text = text.replace(old, new, 1)
marker = "export function mapRichDailyLog(row: Row): Record<string, unknown> {"
helper = '''export type WomenDailyLogWriteMode = "owner_check_in" | "rich_period";

export function classifyWomenDailyLogWrite(
  body: Record<string, unknown>,
): WomenDailyLogWriteMode {
  const hasOwnerCheckInField = [
    "mood",
    "energyLevel",
    "shareSummaryWithCompanion",
  ].some((key) => Object.hasOwn(body, key));
  const hasRichOnlyField = [
    "periodFlow",
    "bloodAppearance",
    "bloodTexture",
    "delete",
  ].some((key) => Object.hasOwn(body, key));
  if (hasOwnerCheckInField && hasRichOnlyField) {
    throw new ApiError(
      400,
      "mixed_women_daily_log_contract",
      "Daily check-in and rich period-only fields must be saved separately.",
    );
  }
  const hasRichPeriodPatch = [
    "periodFlow",
    "bloodAppearance",
    "bloodTexture",
    "painLevel",
    "symptoms",
    "privateNotes",
    "delete",
  ].some((key) => Object.hasOwn(body, key));
  return hasOwnerCheckInField || !hasRichPeriodPatch
    ? "owner_check_in"
    : "rich_period";
}

'''
if marker not in text:
    raise SystemExit("rich helper insertion seam changed")
text = text.replace(marker, helper + marker, 1)
path.write_text(text)

# Unit routing tests.
path = Path("supabase/functions/lifemate-api/women_calendar_rich_period_test.ts")
text = path.read_text()
old = '''import { assertEquals } from "jsr:@std/assert@1";
import { mapRichDailyLog } from "./women_calendar_rich_period.ts";'''
new = '''import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  classifyWomenDailyLogWrite,
  mapRichDailyLog,
} from "./women_calendar_rich_period.ts";'''
if old not in text:
    raise SystemExit("rich test import seam changed")
text = text.replace(old, new, 1)
text += '''

Deno.test("owner check-in routing wins over overlapping pain/symptom fields", () => {
  assertEquals(
    classifyWomenDailyLogWrite({
      mood: "low",
      energyLevel: 2,
      painLevel: 3,
      symptoms: ["cramps"],
      privateNotes: "owner only",
    }),
    "owner_check_in",
  );
  assertEquals(
    classifyWomenDailyLogWrite({
      periodFlow: "medium",
      painLevel: 2,
      symptoms: ["cramps"],
    }),
    "rich_period",
  );
});

Deno.test("mixed check-in and rich-only fields fail closed", () => {
  assertThrows(
    () => classifyWomenDailyLogWrite({
      mood: "good",
      energyLevel: 4,
      periodFlow: "light",
    }),
    Error,
    "Daily check-in and rich period-only fields must be saved separately.",
  );
});
'''
path.write_text(text)

# Database integration proves omission never changes sharing in either direction.
path = Path("supabase/functions/lifemate-api/women_calendar_integration_test.ts")
text = path.read_text()
old = '''      assertEquals(
        privateDailyLog.privateNotes,
        "daily note that must remain owner only",
      );

      const ownerDailyLogs = await women.listOwnerDailyLogs('''
new = '''      assertEquals(
        privateDailyLog.privateNotes,
        "daily note that must remain owner only",
      );

      const privateReplay = await women.upsertOwnerDailyLog(
        patient.appUserId,
        {
          version: privateDailyLog.version,
          loggedOn: recentDailyLogDate,
          mood: "low",
          energyLevel: 2,
          painLevel: 2,
          symptoms: ["cramps"],
          privateNotes: "offline owner replay stays private",
        },
      );
      assertEquals(privateReplay.version, 2);
      assertEquals(privateReplay.mood, "low");
      assertEquals(privateReplay.energyLevel, 2);
      assertEquals(privateReplay.shareSummaryWithCompanion, false);

      const ownerDailyLogs = await women.listOwnerDailyLogs('''
if old not in text:
    raise SystemExit("integration private replay insertion seam changed")
text = text.replace(old, new, 1)
old = '''          version: privateDailyLog.version,
          loggedOn: recentDailyLogDate,'''
new = '''          version: privateReplay.version,
          loggedOn: recentDailyLogDate,'''
if old not in text:
    raise SystemExit("integration shared version seam changed")
text = text.replace(old, new, 1)
old = '''      assertEquals(sharedDailyLog.version, 2);
      assertEquals(sharedDailyLog.shareSummaryWithCompanion, true);

      const summary = await women.getCareSummary('''
new = '''      assertEquals(sharedDailyLog.version, 3);
      assertEquals(sharedDailyLog.shareSummaryWithCompanion, true);

      const sharedPreservingReplay = await women.upsertOwnerDailyLog(
        patient.appUserId,
        {
          version: sharedDailyLog.version,
          loggedOn: recentDailyLogDate,
          mood: "good",
          energyLevel: 4,
          painLevel: 1,
          symptoms: ["fatigue"],
          privateNotes: "offline replay must preserve existing share true",
        },
      );
      assertEquals(sharedPreservingReplay.version, 4);
      assertEquals(sharedPreservingReplay.shareSummaryWithCompanion, true);

      const summary = await women.getCareSummary('''
if old not in text:
    raise SystemExit("integration shared-preserve insertion seam changed")
text = text.replace(old, new, 1)
path.write_text(text)
