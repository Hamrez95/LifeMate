import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "jsr:@std/assert";
import {
  hashCustomRoleMutationRequest,
  hashCustomRolePermissionRequest,
  matchCustomRolePath,
  matchCustomRolePermissionPath,
  matchCustomRoleRetirePath,
  parseCustomRoleMutationRequest,
  parseCustomRolePermissionRequest,
} from "./custom_roles.ts";
import { ApiError } from "./validation.ts";

function request(body: unknown): Request {
  return new Request("https://example.test", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("custom role create request is bounded and canonical", async () => {
  const parsed = await parseCustomRoleMutationRequest(
    request({
      code: "support_lead",
      displayName: "Support Lead",
      rank: 115,
      reason: "Create a limited support leadership role.",
    }),
    "create",
  );
  assertEquals(parsed.code, "support_lead");
  assertEquals(parsed.expectedVersion, null);
  assertEquals(parsed.rank, 115);
  const first = await hashCustomRoleMutationRequest("create", parsed);
  const second = await hashCustomRoleMutationRequest("create", parsed);
  assertEquals(first, second);
  assert(/^[0-9a-f]{64}$/.test(first));
});

Deno.test("founder and super admin role codes stay reserved", async () => {
  for (const code of ["founder", "super_admin"]) {
    const error = await assertRejects(
      () =>
        parseCustomRoleMutationRequest(
          request({
            code,
            displayName: "Reserved",
            rank: 200,
            reason: "Attempt a reserved administrative role code.",
          }),
          "create",
        ),
      ApiError,
    );
    assertEquals(error.code, "custom_role_code_invalid");
  }
});

Deno.test("custom role permission request requires concurrency and reason", async () => {
  const parsed = await parseCustomRolePermissionRequest(request({
    permissionCode: "support.write",
    expectedVersion: 4,
    reason: "Allow this custom role to handle support replies.",
  }));
  assertEquals(parsed.permissionCode, "support.write");
  assertEquals(parsed.expectedVersion, 4);
  const hash = await hashCustomRolePermissionRequest(
    "support_lead",
    "assign",
    parsed,
  );
  assert(/^[0-9a-f]{64}$/.test(hash));
});

Deno.test("custom role route matching is explicit", () => {
  assertEquals(
    matchCustomRolePath("/api/v1/security/custom-roles/support_lead"),
    "support_lead",
  );
  assertEquals(
    matchCustomRoleRetirePath(
      "/api/v1/security/custom-roles/support_lead/actions/retire",
    ),
    "support_lead",
  );
  assertEquals(
    matchCustomRolePermissionPath(
      "/api/v1/security/custom-roles/support_lead/permissions/assign",
    ),
    { roleCode: "support_lead", action: "assign" },
  );
  assertEquals(
    matchCustomRolePermissionPath(
      "/api/v1/security/custom-roles/support_lead/permissions/revoke",
    ),
    { roleCode: "support_lead", action: "revoke" },
  );
});

Deno.test("custom role source enforces non-delegable and self-escalation boundaries", async () => {
  const mutation = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827001500_admin_custom_roles.sql",
      import.meta.url,
    ),
  );
  const guard = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827001600_admin_custom_role_assignment_guard.sql",
      import.meta.url,
    ),
  );
  const hardening = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827001700_admin_custom_roles_security_hardening.sql",
      import.meta.url,
    ),
  );
  const staffStore = await Deno.readTextFile(
    new URL("./staff_actions_service.ts", import.meta.url),
  );
  assertStringIncludes(
    mutation,
    "v_action='assign' and (not v_permission.role_assignable or v_permission.risk_level='ELEVATED')",
  );
  assertStringIncludes(
    mutation,
    "v_action='assign' and not admin.account_has_permission(p_actor_account_id,v_permission.code)",
  );
  assertStringIncludes(mutation, "v_role.is_system");
  assertStringIncludes(guard, "new.account_id=new.granted_by_account_id");
  assertStringIncludes(
    guard,
    "not admin.account_has_permission(new.granted_by_account_id,p.code)",
  );
  assertStringIncludes(hardening, "alter function admin.mutate_custom_role(");
  assertStringIncludes(hardening, "security definer");
  assertStringIncludes(hardening, "v_role.rank<=v_actor_rank");
  assertStringIncludes(hardening, "Target staff membership must be active");
  assertStringIncludes(staffStore, "permission_delegation_denied");
  assertStringIncludes(staffStore, "requireCustomRoleDelegable");
});

Deno.test("custom role routes use purpose-specific write permission and no browser database path", async () => {
  const routes = await Deno.readTextFile(
    new URL("./custom_roles_routes.ts", import.meta.url),
  );
  const service = await Deno.readTextFile(
    new URL("./custom_roles_service.ts", import.meta.url),
  );
  assertStringIncludes(
    routes,
    'requirePermission(admin,"security.roles.write")',
  );
  assertStringIncludes(
    routes,
    'requirePermission(admin,"security.audit.read")',
  );
  assert(!routes.includes("service_role"));
  assert(!service.includes("supabase.from"));
});
