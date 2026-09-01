import { assertEquals, assertFalse } from "jsr:@std/assert";

import { projectDemographicAudienceAttributes } from "./audience_demographics.ts";
import { evaluateSegmentRuleSet, parseSegmentRuleSet } from "./audience_segments.ts";

Deno.test("demographic projection computes birthday-local age boundaries without exposing DOB", () => {
  const beforeBirthday = projectDemographicAudienceAttributes({
    birthDate: "2000-09-02",
    localDate: "2026-09-01",
    genderIdentity: "Woman",
  });
  const onBirthday = projectDemographicAudienceAttributes({
    birthDate: "2000-09-02",
    localDate: "2026-09-02",
    genderIdentity: "Woman",
  });

  assertEquals(beforeBirthday["demographic.age_years"], 25);
  assertEquals(beforeBirthday["demographic.age_bucket"], "25_34");
  assertEquals(beforeBirthday["demographic.birthday_days_ahead"], 1);
  assertEquals(onBirthday["demographic.age_years"], 26);
  assertEquals(onBirthday["demographic.birthday_days_ahead"], 0);
  assertEquals(onBirthday["demographic.birthday_month"], 9);
  assertEquals(onBirthday["demographic.birthday_day"], 2);

  const serialized = JSON.stringify(onBirthday).toLowerCase();
  assertFalse(serialized.includes("2000-09-02"));
  assertFalse(serialized.includes("birth_date"));
});

Deno.test("29-Feb birthday has deterministic annual behavior in non-leap years", () => {
  const projected = projectDemographicAudienceAttributes({
    birthDate: "2000-02-29",
    localDate: "2026-02-27",
    genderIdentity: "Man",
  });
  assertEquals(projected["demographic.age_years"], 25);
  assertEquals(projected["demographic.birthday_days_ahead"], 1);
  assertEquals(projected["demographic.birthday_month"], 2);
  assertEquals(projected["demographic.birthday_day"], 29);
});

Deno.test("prefer-not-to-say and uncollected gender are absent from audience attributes", () => {
  for (const genderIdentity of ["PreferNotToSay", "NotCollected", null]) {
    const projected = projectDemographicAudienceAttributes({
      birthDate: null,
      localDate: "2026-09-01",
      genderIdentity,
    });
    assertEquals(projected["demographic.gender_identity"], undefined);
  }
  const explicit = projectDemographicAudienceAttributes({
    birthDate: null,
    localDate: "2026-09-01",
    genderIdentity: "NonBinary",
  });
  assertEquals(explicit["demographic.gender_identity"], "NonBinary");
});

Deno.test("demographic cohort DSL supports age ranges birthday windows and gender", () => {
  const rules = parseSegmentRuleSet({
    version: 1,
    match: "all",
    rules: [
      { attribute: "demographic.age_years", operator: "gte", value: 18 },
      { attribute: "demographic.age_years", operator: "lte", value: 45 },
      { attribute: "demographic.birthday_days_ahead", operator: "lte", value: 7 },
      { attribute: "demographic.gender_identity", operator: "eq", value: "Woman" },
    ],
  });

  assertEquals(
    evaluateSegmentRuleSet(rules, {
      "demographic.age_years": 30,
      "demographic.birthday_days_ahead": 4,
      "demographic.gender_identity": "Woman",
    }),
    true,
  );
});

Deno.test("demographic numeric filters are bounded", () => {
  for (const [attribute, value] of [
    ["demographic.age_years", 126],
    ["demographic.birthday_month", 13],
    ["demographic.birthday_day", 32],
    ["demographic.birthday_days_ahead", 367],
  ] as const) {
    let failed = false;
    try {
      parseSegmentRuleSet({
        version: 1,
        match: "all",
        rules: [{ attribute, operator: "lte", value }],
      });
    } catch {
      failed = true;
    }
    assertEquals(failed, true, `${attribute} must reject out-of-range values`);
  }
});
