import {
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert";

import { ApiError } from "./validation.ts";
import {
  assertUserAccountActionResult,
  hashUserAccountActionRequest,
  matchUserAccountActionPath,
  parseUserAccountActionRequest,
} from "./user_actions.ts";

const ACCOUNT_ID = "91000000-0000-4000-8000-000000000001";

Deno.test("matches suspend and restore user action routes", () => {
  assertEquals(
    matchUserAccountActionPath(`/api/v1/users/${ACCOUNT_ID}/actions/suspend`),
    { accountId: ACCOUNT_ID, action: "suspend" },
  );
  assertEquals(
    matchUserAccountActionPath(`/api/v1/users/${ACCOUNT_ID}/actions/restore`),
    { accountId: ACCOUNT_ID, action: "restore" },
  );
  assertEquals(matchUserAccountActionPath(`/api/v1/users/${ACCOUNT_ID}`), null);
});

Deno.test("rejects malformed UUIDs on user action routes", () => {
  assertThrows(
    () =>
      matchUserAccountActionPath(
        "/api/v1/users/not-a-uuid/actions/suspend",
      ),
    ApiError,
  );
});

Deno.test("normalizes and validates mandatory action reasons", async () => {
  const request = new Request("https://admin.example", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      reason: "  Repeated abuse confirmed by support.  ",
    }),
  });
  assertEquals(await parseUserAccountActionRequest(request), {
    reason: "Repeated abuse confirmed by support.",
  });

  await assertRejects(
    () =>
      parseUserAccountActionRequest(
        new Request("https://admin.example", {
          method: "POST",
          body: JSON.stringify({ reason: "short" }),
        }),
      ),
    ApiError,
  );
});

Deno.test("hashes action request content deterministically", async () => {
  const first = await hashUserAccountActionRequest(
    ACCOUNT_ID,
    "suspend",
    "Repeated abuse confirmed by support.",
  );
  const same = await hashUserAccountActionRequest(
    ACCOUNT_ID,
    "suspend",
    "Repeated abuse confirmed by support.",
  );
  const different = await hashUserAccountActionRequest(
    ACCOUNT_ID,
    "restore",
    "Repeated abuse confirmed by support.",
  );
  assertEquals(first.length, 64);
  assertEquals(first, same);
  assertNotEquals(first, different);
});

Deno.test("validates database action results before returning them", () => {
  assertEquals(
    assertUserAccountActionResult({
      httpStatus: 200,
      code: "ok",
      accountId: ACCOUNT_ID,
      previousStatus: "Active",
      status: "Disabled",
      action: "suspend",
      replayed: false,
    }).status,
    "Disabled",
  );
  assertThrows(
    () => assertUserAccountActionResult({ httpStatus: "200", code: "ok" }),
    ApiError,
  );
});
