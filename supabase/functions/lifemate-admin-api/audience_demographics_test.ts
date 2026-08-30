import { assertEquals } from "jsr:@std/assert";

import {
  birthdayDaysUntil,
  projectDemographicSubject,
} from "./audience_segments_service.ts";

Deno.test("demographic projection computes age in the person's local date", () => {
  const subject = projectDemographicSubject(
    {
      locale: "fa-IR",
      time_zone: "Asia/Tehran",
      birth_date: "2000-09-01",
      gender_identity: "Woman",
    },
    new Date("2026-08-31T21:30:00Z"), // 2026-09-01 in Tehran
  );

  assertEquals(subject["demographic.age_years"], 26);
  assertEquals(subject["demographic.age_bucket"], "25_34");
  assertEquals(subject["demographic.birthday_upcoming_days"], 0);
  assertEquals(subject["demographic.gender_identity"], "woman");
  assertEquals(subject["demographic.locale"], "fa-IR");
});

Deno.test("birthday projection never exposes the full birth date", () => {
  const subject = projectDemographicSubject(
    {
      locale: "en",
      time_zone: "UTC",
      birth_date: "1994-12-20",
      gender_identity: "Man",
    },
    new Date("2026-12-10T12:00:00Z"),
  );

  assertEquals(subject["demographic.birthday_month"], 12);
  assertEquals(subject["demographic.birthday_day"], 20);
  assertEquals(subject["demographic.birthday_upcoming_days"], 10);
  assertEquals(Object.values(subject).includes("1994-12-20"), false);
});

Deno.test("Feb-29 birthdays use Feb-28 in non-leap years", () => {
  assertEquals(
    birthdayDaysUntil(
      { year: 2000, month: 2, day: 29 },
      { year: 2027, month: 2, day: 28 },
    ),
    0,
  );
});

Deno.test("NotCollected gender is unavailable while explicit privacy answer is projected", () => {
  const unknown = projectDemographicSubject({
    locale: "fa",
    time_zone: "Asia/Tehran",
    birth_date: null,
    gender_identity: "NotCollected",
  });
  assertEquals(unknown["demographic.gender_identity"], undefined);

  const privateAnswer = projectDemographicSubject({
    locale: "fa",
    time_zone: "Asia/Tehran",
    birth_date: null,
    gender_identity: "PreferNotToSay",
  });
  assertEquals(
    privateAnswer["demographic.gender_identity"],
    "prefer_not_to_say",
  );
});
