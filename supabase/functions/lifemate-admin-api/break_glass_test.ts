import { assertEquals, assertRejects } from "jsr:@std/assert";

import {
  matchBreakGlassActionPath,
  parseBreakGlassActionRequest,
  parseBreakGlassCreateRequest,
} from "./break_glass.ts";

Deno.test("break-glass request keeps exact target/capability and bounded TTL", async () => {
  const subjectPersonId = "11111111-1111-4111-8111-111111111111";
  const parsed = await parseBreakGlassCreateRequest(
    new Request("https://admin.test/api/v1/security/break-glass/requests", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        subjectPersonId,
        capability: "health.read.elevated",
        ttlMinutes: 30,
        reason: "Investigate a specific support escalation safely.",
      }),
    }),
  );

  assertEquals(parsed.subjectPersonId, subjectPersonId);
  assertEquals(parsed.capability, "health.read.elevated");
  assertEquals(parsed.ttlMinutes, 30);
});

Deno.test("women-health break-glass TTL is stricter", async () => {
  await assertRejects(
    () =>
      parseBreakGlassCreateRequest(
        new Request("https://admin.test/api/v1/security/break-glass/requests", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            subjectPersonId: "11111111-1111-4111-8111-111111111111",
            capability: "women_health.read.elevated",
            ttlMinutes: 45,
            reason: "Investigate a specific support escalation safely.",
          }),
        }),
      ),
    Error,
    "TTL must be between 5 and 30 minutes",
  );
});

Deno.test("break-glass action route is exact and versioned", async () => {
  const requestId = "22222222-2222-4222-8222-222222222222";
  assertEquals(
    matchBreakGlassActionPath(
      `/api/v1/security/break-glass/requests/${requestId}/actions/approve`,
    ),
    { requestId, action: "approve" },
  );

  const payload = await parseBreakGlassActionRequest(
    new Request("https://admin.test", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        expectedVersion: 2,
        reason: "Independent approval after reviewing exact scope.",
      }),
    }),
  );
  assertEquals(payload.expectedVersion, 2);
});

Deno.test("break-glass parser rejects unknown fields and implicit capability expansion", async () => {
  await assertRejects(
    () =>
      parseBreakGlassCreateRequest(
        new Request("https://admin.test", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            subjectPersonId: "11111111-1111-4111-8111-111111111111",
            capability: "health.read.elevated",
            ttlMinutes: 15,
            reason: "Investigate one approved support escalation only.",
            scopes: ["all"],
          }),
        }),
      ),
    Error,
    "unsupported field",
  );
});
