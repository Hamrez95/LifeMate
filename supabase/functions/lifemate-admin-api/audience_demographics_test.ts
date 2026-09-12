import { assert, assertEquals } from "jsr:@std/assert";

import { projectDemographicSubject } from "./audience_segments_service.ts";

Deno.test("derived demographic projection maps bounded campaign attributes", () => {
  const subject = projectDemographicSubject({
    locale: "fa-IR",
    age_years: 26,
    age_bucket: "25_34",
    birthday_month: 9,
    birthday_day: 1,
    birthday_upcoming_days: 0,
    gender_identity: "woman",
  });

  assertEquals(subject["demographic.locale"], "fa-IR");
  assertEquals(subject["demographic.age_years"], 26);
  assertEquals(subject["demographic.age_bucket"], "25_34");
  assertEquals(subject["demographic.birthday_month"], 9);
  assertEquals(subject["demographic.birthday_day"], 1);
  assertEquals(subject["demographic.birthday_upcoming_days"], 0);
  assertEquals(subject["demographic.gender_identity"], "woman");
});

Deno.test("invalid derived values stay unavailable instead of being coerced", () => {
  const subject = projectDemographicSubject({
    locale: "",
    age_years: 131,
    age_bucket: null,
    birthday_month: 13,
    birthday_day: 32,
    birthday_upcoming_days: 367,
    gender_identity: null,
  });

  assertEquals(subject["demographic.locale"], undefined);
  assertEquals(subject["demographic.age_years"], undefined);
  assertEquals(subject["demographic.age_bucket"], undefined);
  assertEquals(subject["demographic.birthday_month"], undefined);
  assertEquals(subject["demographic.birthday_day"], undefined);
  assertEquals(subject["demographic.birthday_upcoming_days"], undefined);
  assertEquals(subject["demographic.gender_identity"], undefined);
});

Deno.test("purpose-limited subject contains no raw birth date or contact fields", () => {
  const subject = projectDemographicSubject({
    locale: "en",
    age_years: 31,
    age_bucket: "25_34",
    birthday_month: 12,
    birthday_day: 20,
    birthday_upcoming_days: 10,
    gender_identity: "man",
  });

  const keys = Object.keys(subject);
  assert(!keys.some((key) => key.includes("birth_date")));
  assert(!keys.some((key) => /phone|email|contact/i.test(key)));
  assert(!Object.values(subject).includes("1994-12-20"));
});

Deno.test("PreferNotToSay can exist internally but requires explicit DSL selection", () => {
  const subject = projectDemographicSubject({
    locale: "fa",
    age_years: null,
    age_bucket: null,
    birthday_month: null,
    birthday_day: null,
    birthday_upcoming_days: null,
    gender_identity: "prefer_not_to_say",
  });

  assertEquals(
    subject["demographic.gender_identity"],
    "prefer_not_to_say",
  );
});
