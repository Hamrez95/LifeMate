import {
  hashStaffActionRequest,
  matchStaffActionPath,
  parseStaffActionRequest,
} from "./staff_actions.ts";

Deno.test("staff action paths are purpose-specific and UUID-bound", () => {
  const id = "11111111-1111-4111-8111-111111111111";
  const membership = matchStaffActionPath(`/api/v1/staff/${id}/actions/disable`);
  if (!membership || membership.kind !== "membership") throw new Error("membership route missing");
  if (membership.accountId !== id || membership.action !== "disable") throw new Error("membership route mismatch");

  const role = matchStaffActionPath(`/api/v1/staff/${id}/roles/assign`);
  if (!role || role.kind !== "role") throw new Error("role route missing");
  if (role.accountId !== id || role.action !== "assign") throw new Error("role route mismatch");

  let rejected = false;
  try {
    matchStaffActionPath("/api/v1/staff/not-a-uuid/actions/disable");
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("invalid UUID route must fail closed");
});

Deno.test("membership actions require a meaningful reason and reject role input", async () => {
  const route = matchStaffActionPath(
    "/api/v1/staff/11111111-1111-4111-8111-111111111111/actions/disable",
  );
  if (!route) throw new Error("route missing");

  const parsed = await parseStaffActionRequest(
    new Request("https://example.test", {
      method: "POST",
      body: JSON.stringify({ reason: "Employee access has ended." }),
    }),
    route,
  );
  if (parsed.roleCode !== null || parsed.reason !== "Employee access has ended.") {
    throw new Error("membership request mismatch");
  }

  let rejected = false;
  try {
    await parseStaffActionRequest(
      new Request("https://example.test", {
        method: "POST",
        body: JSON.stringify({ reason: "Employee access has ended.", roleCode: "support" }),
      }),
      route,
    );
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("membership roleCode must be rejected");
});

Deno.test("ordinary staff workflow cannot assign or revoke founder role", async () => {
  const route = matchStaffActionPath(
    "/api/v1/staff/11111111-1111-4111-8111-111111111111/roles/assign",
  );
  if (!route) throw new Error("route missing");

  let rejected = false;
  try {
    await parseStaffActionRequest(
      new Request("https://example.test", {
        method: "POST",
        body: JSON.stringify({ reason: "Approved workforce role change.", roleCode: "founder" }),
      }),
      route,
    );
  } catch (error) {
    rejected = error instanceof Error && error.message.includes("Founder role");
  }
  if (!rejected) throw new Error("founder role mutation must be rejected");
});

Deno.test("staff request hash binds target, action, role and reason", async () => {
  const first = matchStaffActionPath(
    "/api/v1/staff/11111111-1111-4111-8111-111111111111/roles/assign",
  );
  const second = matchStaffActionPath(
    "/api/v1/staff/22222222-2222-4222-8222-222222222222/roles/assign",
  );
  if (!first || !second) throw new Error("routes missing");

  const request = { reason: "Approved workforce role change.", roleCode: "support" };
  const firstHash = await hashStaffActionRequest(first, request);
  const secondHash = await hashStaffActionRequest(second, request);
  if (firstHash === secondHash || firstHash.length !== 64 || secondHash.length !== 64) {
    throw new Error("hash must bind target and remain SHA-256 hex");
  }
});
