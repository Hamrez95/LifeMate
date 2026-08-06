import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  ApiError,
  normalizeDoseStatus,
  normalizePath,
  normalizeSchedules,
  requiredDate,
  requiredTimeZone,
  validateRange,
  validateReportedAt,
} from "./validation.ts";

Deno.test("requiredDate accepts a real leap date", () => {
  assertEquals(requiredDate("2028-02-29", "date"), "2028-02-29");
});

Deno.test("requiredDate rejects calendar rollover dates", () => {
  const error = assertThrows(
    () => requiredDate("2026-02-31", "date"),
    ApiError,
  );
  assertEquals(error.code, "invalid_date");
});

Deno.test("normalizeSchedules canonicalizes and rejects duplicates", () => {
  assertEquals(
    normalizeSchedules([
      { dayOfWeek: "monday", localTime: "08:05:00" },
      { dayOfWeek: "Friday", localTime: "22:30" },
    ]),
    [
      { dayOfWeek: "Monday", localTime: "08:05" },
      { dayOfWeek: "Friday", localTime: "22:30" },
    ],
  );
  assertThrows(
    () =>
      normalizeSchedules([
        { dayOfWeek: "Monday", localTime: "08:05" },
        { dayOfWeek: "monday", localTime: "08:05:00" },
      ]),
    ApiError,
  );
});

Deno.test("normalizeSchedules rejects out-of-range clock values", () => {
  for (const localTime of ["24:00", "23:60", "99:99", "12:30:60"]) {
    assertThrows(
      () => normalizeSchedules([{ dayOfWeek: "Monday", localTime }]),
      ApiError,
    );
  }
});

Deno.test("requiredTimeZone accepts IANA zones and rejects arbitrary text", () => {
  assertEquals(requiredTimeZone("Asia/Tehran"), "Asia/Tehran");
  assertThrows(() => requiredTimeZone("Tehran/Invalid"), ApiError);
});

Deno.test("validateRange keeps strict defaults and supports explicit history", () => {
  validateRange("2026-07-01", "2026-08-01");
  assertThrows(() => validateRange("2026-08-02", "2026-08-01"), ApiError);
  assertThrows(() => validateRange("2026-07-01", "2026-08-02"), ApiError);
  validateRange("2026-05-08", "2026-08-06", 90);
  assertThrows(() => validateRange("2026-05-07", "2026-08-06", 90), ApiError);
});

Deno.test("validateReportedAt rejects implausible future and stale events", () => {
  const now = new Date("2026-07-30T12:00:00Z");
  validateReportedAt(new Date("2026-07-30T11:59:00Z"), now);
  assertThrows(
    () => validateReportedAt(new Date("2026-07-30T12:06:00Z"), now),
    ApiError,
  );
  assertThrows(
    () => validateReportedAt(new Date("2026-06-01T00:00:00Z"), now),
    ApiError,
  );
});

Deno.test("normalizeDoseStatus only accepts supported patient actions", () => {
  assertEquals(normalizeDoseStatus("TAKEN"), "Taken");
  assertEquals(normalizeDoseStatus("skipped"), "Skipped");
  assertThrows(() => normalizeDoseStatus("missed"), ApiError);
});

Deno.test("normalizePath supports direct production and candidate paths", () => {
  assertEquals(normalizePath("/api/v1/me"), "/api/v1/me");
  assertEquals(
    normalizePath("/functions/v1/lifemate-api/api/v1/me/"),
    "/api/v1/me",
  );
  assertEquals(
    normalizePath("/lifemate-api-candidate/health"),
    "/health",
  );
  assertEquals(
    normalizePath(
      "/functions/v1/lifemate-api-candidate/api/v1/care/relationships/",
    ),
    "/api/v1/care/relationships",
  );
  assertEquals(
    normalizePath("/nested/lifemate-api-candidate/health"),
    "/nested/lifemate-api-candidate/health",
  );
});
