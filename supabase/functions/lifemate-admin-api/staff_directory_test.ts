import { assertEquals, assertThrows } from "jsr:@std/assert";

import {
  encodeStaffDirectoryCursor,
  matchStaffDetailPath,
  parseStaffDirectoryQuery,
} from "./staff_directory.ts";
import { ApiError } from "./validation.ts";

const ACCOUNT_ID = "91000000-0000-4000-8000-000000000001";

Deno.test("matches only canonical staff detail paths", () => {
  assertEquals(matchStaffDetailPath(`/api/v1/staff/${ACCOUNT_ID}`), ACCOUNT_ID);
  assertEquals(matchStaffDetailPath("/api/v1/staff"), null);
  assertEquals(
    matchStaffDetailPath(`/api/v1/staff/${ACCOUNT_ID}/roles/assign`),
    null,
  );
});

Deno.test("parses bounded safe staff directory filters", () => {
  const query = parseStaffDirectoryQuery(
    new URL(
      "https://admin.example/api/v1/staff?pageSize=50&status=Active&role=support&q=ali",
    ),
  );
  assertEquals(query.pageSize, 50);
  assertEquals(query.status, "Active");
  assertEquals(query.roleCode, "support");
  assertEquals(query.q, "ali");
  assertEquals(query.cursor, null);
});

Deno.test("round-trips opaque stable staff directory cursor", () => {
  const cursor = encodeStaffDirectoryCursor({
    createdAtUtc: "2026-08-25T10:00:00.000Z",
    accountId: ACCOUNT_ID,
  });
  const query = parseStaffDirectoryQuery(
    new URL(
      `https://admin.example/api/v1/staff?cursor=${encodeURIComponent(cursor)}`,
    ),
  );
  assertEquals(query.cursor, {
    createdAtUtc: "2026-08-25T10:00:00.000Z",
    accountId: ACCOUNT_ID,
  });
});

Deno.test("rejects unsafe staff directory filters and malformed cursors", () => {
  assertThrows(
    () =>
      parseStaffDirectoryQuery(
        new URL("https://admin.example/api/v1/staff?status=Pending"),
      ),
    ApiError,
  );
  assertThrows(
    () =>
      parseStaffDirectoryQuery(
        new URL("https://admin.example/api/v1/staff?role=SUPER-ADMIN!"),
      ),
    ApiError,
  );
  assertThrows(
    () =>
      parseStaffDirectoryQuery(
        new URL("https://admin.example/api/v1/staff?q=x"),
      ),
    ApiError,
  );
  assertThrows(
    () =>
      parseStaffDirectoryQuery(
        new URL("https://admin.example/api/v1/staff?cursor=not-a-cursor"),
      ),
    ApiError,
  );
});
