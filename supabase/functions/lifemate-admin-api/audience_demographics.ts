import type { SegmentSubject } from "./audience_segments.ts";

type DemographicProjectionInput = {
  birthDate: unknown;
  localDate: unknown;
  genderIdentity: unknown;
};

function parseDateOnly(value: unknown): { year: number; month: number; day: number } | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(value ?? ""));
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const candidate = new Date(Date.UTC(year, month - 1, day));
  if (
    candidate.getUTCFullYear() !== year ||
    candidate.getUTCMonth() !== month - 1 ||
    candidate.getUTCDate() !== day
  ) return null;
  return { year, month, day };
}

function leapYear(year: number): boolean {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

function anniversaryForYear(
  birth: { month: number; day: number },
  year: number,
): { month: number; day: number } {
  // Explicit annual policy for 29-Feb birthdays: use 28-Feb in non-leap years.
  if (birth.month === 2 && birth.day === 29 && !leapYear(year)) {
    return { month: 2, day: 28 };
  }
  return birth;
}

function utcDayNumber(year: number, month: number, day: number): number {
  return Math.floor(Date.UTC(year, month - 1, day) / 86_400_000);
}

function ageBucket(age: number): string {
  if (age < 18) return "under_18";
  if (age <= 24) return "18_24";
  if (age <= 34) return "25_34";
  if (age <= 44) return "35_44";
  if (age <= 54) return "45_54";
  if (age <= 64) return "55_64";
  return "65_plus";
}

export function projectDemographicAudienceAttributes(
  input: DemographicProjectionInput,
): SegmentSubject {
  const subject: SegmentSubject = {};
  const today = parseDateOnly(input.localDate);
  const birth = parseDateOnly(input.birthDate);

  if (today && birth && birth.year <= today.year) {
    const thisAnniversary = anniversaryForYear(birth, today.year);
    let age = today.year - birth.year;
    if (
      today.month < thisAnniversary.month ||
      (today.month === thisAnniversary.month && today.day < thisAnniversary.day)
    ) age -= 1;

    if (age >= 0 && age <= 125) {
      subject["demographic.age_years"] = age;
      subject["demographic.age_bucket"] = ageBucket(age);
      subject["demographic.birthday_month"] = birth.month;
      subject["demographic.birthday_day"] = birth.day;

      let nextYear = today.year;
      let next = anniversaryForYear(birth, nextYear);
      if (
        next.month < today.month ||
        (next.month === today.month && next.day < today.day)
      ) {
        nextYear += 1;
        next = anniversaryForYear(birth, nextYear);
      }
      const daysAhead = utcDayNumber(nextYear, next.month, next.day) -
        utcDayNumber(today.year, today.month, today.day);
      if (daysAhead >= 0 && daysAhead <= 366) {
        subject["demographic.birthday_days_ahead"] = daysAhead;
      }
    }
  }

  const gender = typeof input.genderIdentity === "string"
    ? input.genderIdentity.trim()
    : "";
  if (gender && gender !== "NotCollected" && gender !== "PreferNotToSay") {
    subject["demographic.gender_identity"] = gender;
  }

  return subject;
}
