import { assertEquals, assertThrows } from "jsr:@std/assert";

import { ApiError } from "./validation.ts";
import {
  matchUserActivityPath,
  matchUserDetailPath,
  parseUserActivityQuery,
} from "./user_detail.ts";

const ACCOUNT_ID = "91000000-0000-4000-8000-000000000001";

Deno.test("matches a valid User 360 account path", () => {
  assertEquals(matchUserDetailPath(`/api/v1/users/${ACCOUNT_ID}`), ACCOUNT_ID);
});

Deno.test("matches the paginated user activity path without colliding with detail", () => {
  assertEquals(
    matchUserActivityPath(`/api/v1/users/${ACCOUNT_ID}/activity`),
    ACCOUNT_ID,
  );
  assertEquals(matchUserDetailPath(`/api/v1/users/${ACCOUNT_ID}/activity`), null);
});

Deno.test("ignores non-detail routes", () => {
  assertEquals(matchUserDetailPath("/api/v1/users"), null);
  assertEquals(matchUserDetailPath("/api/v1/users/search"), null);
  assertEquals(matchUserActivityPath("/api/v1/users"), null);
});

Deno.test("rejects malformed UUID-shaped detail and activity paths", () => {
  assertThrows(
    () =>
      matchUserDetailPath("/api/v1/users/91000000-0000-0000-0000-000000000001"),
    ApiError,
  );
  assertThrows(
    () =>
      matchUserActivityPath(
        "/api/v1/users/91000000-0000-0000-0000-000000000001/activity",
      ),
    ApiError,
  );
});

Deno.test("uses bounded defaults for user activity pagination", () => {
  assertEquals(
    parseUserActivityQuery(new URL(`https://admin.example/api/v1/users/${ACCOUNT_ID}/activity`)),
    { page: 1, pageSize: 20 },
  );
  assertEquals(
    parseUserActivityQuery(
      new URL(
        `https://admin.example/api/v1/users/${ACCOUNT_ID}/activity?page=3&pageSize=50`,
      ),
    ),
    { page: 3, pageSize: 50 },
  );
});

Deno.test("rejects user activity pagination outside the safe bounds", () => {
  assertThrows(
    () =>
      parseUserActivityQuery(
        new URL(
          `https://admin.example/api/v1/users/${ACCOUNT_ID}/activity?page=0&pageSize=20`,
        ),
      ),
    ApiError,
  );
  assertThrows(
    () =>
      parseUserActivityQuery(
        new URL(
          `https://admin.example/api/v1/users/${ACCOUNT_ID}/activity?page=1&pageSize=100`,
        ),
      ),
    ApiError,
  );
});
