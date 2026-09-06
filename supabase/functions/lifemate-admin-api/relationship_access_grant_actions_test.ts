import { assertEquals, assertRejects } from "jsr:@std/assert";
import {
  hashAccessGrantActionRequest,
  matchAccessGrantActionPath,
  parseAccessGrantActionRequest,
} from "./relationship_access_grant_actions.ts";
import { ApiError } from "./validation.ts";

const grantId = "123e4567-e89b-12d3-a456-426614174000";

Deno.test("access grant action path matches supported lifecycle operations", () => {
  assertEquals(
    matchAccessGrantActionPath(
      `/api/v1/relationships/access-grants/${grantId}/actions/extend`,
    ),
    { grantId, action: "extend" },
  );
  assertEquals(
    matchAccessGrantActionPath(
      `/api/v1/relationships/access-grants/${grantId}/actions/replace-scopes`,
    ),
    { grantId, action: "replace-scopes" },
  );
  assertEquals(
    matchAccessGrantActionPath(
      `/api/v1/relationships/access-grants/${grantId}/actions/revoke`,
    ),
    { grantId, action: "revoke" },
  );
  assertEquals(
    matchAccessGrantActionPath("/api/v1/relationships/overview"),
    null,
  );
});

Deno.test("access grant extend requires canonical expiry, version, reason and confirmation", async () => {
  const parsed = await parseAccessGrantActionRequest(
    new Request("https://admin.test", {
      method: "POST",
      body: JSON.stringify({
        expectedVersion: 2,
        expiresAtUtc: "2026-09-30T12:00:00.000Z",
        reason: "Extend approved operational access window.",
        confirmation: "confirm-access-grant-change",
      }),
    }),
    "extend",
  );
  assertEquals(parsed.expectedVersion, 2);
  assertEquals(parsed.expiresAtUtc, "2026-09-30T12:00:00.000Z");
  assertEquals(parsed.scopes, null);
});

Deno.test("access grant scope replacement is deterministic and rejects duplicates", async () => {
  const parsed = await parseAccessGrantActionRequest(
    new Request("https://admin.test", {
      method: "POST",
      body: JSON.stringify({
        expectedVersion: 3,
        scopes: ["profile.read", "appointments.read"],
        reason: "Reduce grant to the minimum required scopes.",
        confirmation: "confirm-access-grant-change",
      }),
    }),
    "replace-scopes",
  );
  assertEquals(parsed.scopes, ["appointments.read", "profile.read"]);

  await assertRejects(
    () =>
      parseAccessGrantActionRequest(
        new Request("https://admin.test", {
          method: "POST",
          body: JSON.stringify({
            expectedVersion: 3,
            scopes: ["profile.read", "profile.read"],
            reason: "Attempt duplicated access grant scopes.",
            confirmation: "confirm-access-grant-change",
          }),
        }),
        "replace-scopes",
      ),
    ApiError,
    "unique",
  );
});

Deno.test("access grant actions reject unsupported fields and missing confirmation", async () => {
  await assertRejects(
    () =>
      parseAccessGrantActionRequest(
        new Request("https://admin.test", {
          method: "POST",
          body: JSON.stringify({
            expectedVersion: 1,
            reason: "Revoke access after reviewed operational request.",
            confirmation: "confirm-access-grant-change",
            subjectPersonId: grantId,
          }),
        }),
        "revoke",
      ),
    ApiError,
    "unsupported",
  );
  await assertRejects(
    () =>
      parseAccessGrantActionRequest(
        new Request("https://admin.test", {
          method: "POST",
          body: JSON.stringify({
            expectedVersion: 1,
            reason: "Revoke access after reviewed operational request.",
          }),
        }),
        "revoke",
      ),
    ApiError,
    "confirmation",
  );
});

Deno.test("access grant request hash is deterministic and action bound", async () => {
  const request = {
    expectedVersion: 2,
    expiresAtUtc: null,
    scopes: ["appointments.read"],
    reason: "Reduce access after reviewed operational request.",
    confirmation: "confirm-access-grant-change" as const,
  };
  const first = await hashAccessGrantActionRequest(
    grantId,
    "replace-scopes",
    request,
  );
  const second = await hashAccessGrantActionRequest(
    grantId,
    "replace-scopes",
    request,
  );
  const other = await hashAccessGrantActionRequest(grantId, "revoke", {
    ...request,
    scopes: null,
  });
  assertEquals(first, second);
  assertEquals(first.length, 64);
  assertEquals(first === other, false);
});
