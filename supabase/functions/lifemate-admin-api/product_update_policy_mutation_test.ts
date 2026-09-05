import { assertEquals, assertRejects } from "jsr:@std/assert";
import {
  hashProductUpdatePolicyMutation,
  parseProductUpdatePolicyMutation,
} from "./product_update_policy_mutation.ts";

function request(body: Record<string, unknown>) {
  return new Request(
    "https://example.test/api/v1/platform/product-update-policies",
    {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    },
  );
}

const valid = {
  product: "wellmate",
  platform: "android",
  minimumSupportedVersion: "1.2.3",
  recommendedVersion: "1.4.0",
  mode: "Soft",
  reasonCode: "Routine",
  messageKey: "update.routine",
  status: "Active",
  effectiveAtUtc: "2026-08-28T00:00:00Z",
  expectedVersion: 2,
  reason: "Routine minimum-version policy update.",
};

Deno.test("product update policy parser normalizes canonical payload", async () => {
  const parsed = await parseProductUpdatePolicyMutation(request(valid));
  assertEquals(parsed.product, "wellmate");
  assertEquals(parsed.effectiveAtUtc, "2026-08-28T00:00:00.000Z");
  assertEquals(parsed.expectedVersion, 2);
});

Deno.test("force update rejects Routine reason", async () => {
  await assertRejects(
    () =>
      parseProductUpdatePolicyMutation(request({ ...valid, mode: "Force" })),
    Error,
    "Force update",
  );
});

Deno.test("expectedVersion must be a non-negative integer", async () => {
  await assertRejects(
    () =>
      parseProductUpdatePolicyMutation(
        request({ ...valid, expectedVersion: -1 }),
      ),
    Error,
    "expectedVersion",
  );
  await assertRejects(
    () =>
      parseProductUpdatePolicyMutation(
        request({ ...valid, expectedVersion: 1.5 }),
      ),
    Error,
    "expectedVersion",
  );
});

Deno.test("request hash is stable and changes with policy version", async () => {
  const parsed = await parseProductUpdatePolicyMutation(request(valid));
  const first = await hashProductUpdatePolicyMutation(parsed);
  const second = await hashProductUpdatePolicyMutation(parsed);
  assertEquals(first, second);
  const changed = await hashProductUpdatePolicyMutation({
    ...parsed,
    expectedVersion: 3,
  });
  assertEquals(first === changed, false);
});
