import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert";

import { buildAdminRbacMatrix } from "./security_rbac.ts";
import { createSecurityRbacRouteHandler } from "./security_rbac_routes.ts";
import {
  classifyAdminMembership,
  matchAdminRoleDetailPath,
  rolePermissionDetail,
} from "./security_role_detail.ts";

const evaluation = new Date("2026-08-17T11:45:00.000Z");
const inertDatabaseUrl = "postgres://test:test@127.0.0.1:5432/test";

function matrixStore() {
  return {
    async getRolePermissionMatrix() {
      return buildAdminRbacMatrix([], [], []);
    },
  };
}

function roleDetailFixture() {
  return {
    role: {
      code: "security",
      displayName: "Security",
      rank: 150,
      status: "Active" as const,
      isSystem: true,
    },
    permissions: [
      {
        code: "security.audit.read",
        domain: "security",
        riskLevel: "SENSITIVE" as const,
        roleAssignable: true,
        description: "Read security evidence",
        source: "direct" as const,
        effectiveForActiveMember: true,
        blockedReason: null,
      },
    ],
    memberships: [
      {
        membershipId: "11111111-1111-4111-8111-111111111111",
        accountId: "22222222-2222-4222-8222-222222222222",
        memberStatus: "Active" as const,
        startsAtUtc: "2026-08-01T00:00:00.000Z",
        expiresAtUtc: null,
        revokedAtUtc: null,
        createdAtUtc: "2026-08-01T00:00:00.000Z",
        state: "active" as const,
        effective: true,
        currentRoleCodes: ["security"],
        effectivePermissions: [
          {
            code: "security.audit.read",
            sourceRoleCodes: ["security"],
          },
        ],
      },
    ],
    evaluationAtUtc: evaluation.toISOString(),
    source: {
      kind: "canonical" as const,
      label: "LifeMate admin RBAC control plane",
      definitionVersion: 1,
    },
  };
}

Deno.test("role detail membership classification is deterministic at one evaluation instant", () => {
  const base = {
    startsAtUtc: "2026-08-01T00:00:00.000Z",
    expiresAtUtc: null,
    revokedAtUtc: null,
  };
  assertEquals(
    classifyAdminMembership("Active", "Active", base, evaluation),
    "active",
  );
  assertEquals(
    classifyAdminMembership(
      "Active",
      "Active",
      { ...base, startsAtUtc: "2026-09-01T00:00:00.000Z" },
      evaluation,
    ),
    "scheduled",
  );
  assertEquals(
    classifyAdminMembership(
      "Active",
      "Active",
      { ...base, expiresAtUtc: "2026-08-17T11:45:00.000Z" },
      evaluation,
    ),
    "expired",
  );
  assertEquals(
    classifyAdminMembership(
      "Active",
      "Active",
      { ...base, revokedAtUtc: "2026-08-10T00:00:00.000Z" },
      evaluation,
    ),
    "revoked",
  );
  assertEquals(
    classifyAdminMembership("Disabled", "Active", base, evaluation),
    "member_inactive",
  );
  assertEquals(
    classifyAdminMembership("Active", "Disabled", base, evaluation),
    "role_disabled",
  );
});

Deno.test("role detail rejects malformed membership timestamps", () => {
  assertThrows(
    () =>
      classifyAdminMembership(
        "Active",
        "Active",
        {
          startsAtUtc: "not-a-timestamp",
          expiresAtUtc: null,
          revokedAtUtc: null,
        },
        evaluation,
      ),
    Error,
    "invalid timestamp",
  );
});

Deno.test("role detail never makes elevated permission effective through an ordinary role", () => {
  assertEquals(
    rolePermissionDetail("Active", {
      code: "health.read.elevated",
      domain: "health",
      riskLevel: "ELEVATED",
      roleAssignable: false,
      description: "Break-glass health access",
    }),
    {
      code: "health.read.elevated",
      domain: "health",
      riskLevel: "ELEVATED",
      roleAssignable: false,
      description: "Break-glass health access",
      source: "direct",
      effectiveForActiveMember: false,
      blockedReason: "permission_not_role_assignable",
    },
  );
});

Deno.test("role detail path matcher accepts only bounded role codes", () => {
  assertEquals(
    matchAdminRoleDetailPath("/api/v1/security/roles/security"),
    "security",
  );
  assertEquals(
    matchAdminRoleDetailPath("/api/v1/security/roles/super_admin"),
    "super_admin",
  );
  assertEquals(
    matchAdminRoleDetailPath("/api/v1/security/roles/security/members"),
    null,
  );
  assertEquals(
    matchAdminRoleDetailPath("/api/v1/security/roles/%2e%2e"),
    null,
  );
});

Deno.test("role detail route denies missing security.audit.read before querying store", async () => {
  let queried = false;
  const handler = createSecurityRbacRouteHandler(
    inertDatabaseUrl,
    matrixStore(),
    {
      async getRoleDetail() {
        queried = true;
        return roleDetailFixture();
      },
    },
  );

  await assertRejects(
    async () =>
      await handler({
        request: new Request(
          "https://admin.test/api/v1/security/roles/security",
        ),
        path: "/api/v1/security/roles/security",
        admin: {
          accountId: crypto.randomUUID(),
          roles: ["technical"],
          permissions: ["operations.read"],
        },
        origin: null,
      }),
    Error,
    "Administrative permission is required",
  );
  assertEquals(queried, false);
});

Deno.test("role detail route remains read-only for mutation methods", async () => {
  let queried = false;
  const handler = createSecurityRbacRouteHandler(
    inertDatabaseUrl,
    matrixStore(),
    {
      async getRoleDetail() {
        queried = true;
        return roleDetailFixture();
      },
    },
  );

  const response = await handler({
    request: new Request("https://admin.test/api/v1/security/roles/security", {
      method: "POST",
    }),
    path: "/api/v1/security/roles/security",
    admin: {
      accountId: crypto.randomUUID(),
      roles: ["security"],
      permissions: ["security.audit.read", "security.roles.write"],
    },
    origin: null,
  });

  assertEquals(response, null);
  assertEquals(queried, false);
});

Deno.test("role detail route returns traceable effective permissions to authorized reader", async () => {
  const handler = createSecurityRbacRouteHandler(
    inertDatabaseUrl,
    matrixStore(),
    {
      async getRoleDetail(roleCode: string) {
        assertEquals(roleCode, "security");
        return roleDetailFixture();
      },
    },
  );

  const response = await handler({
    request: new Request(
      "https://admin.test/api/v1/security/roles/security",
    ),
    path: "/api/v1/security/roles/security",
    admin: {
      accountId: crypto.randomUUID(),
      roles: ["security"],
      permissions: ["security.audit.read"],
    },
    origin: null,
  });

  assertEquals(response?.status, 200);
  const body = await response?.json();
  assertEquals(body.role.code, "security");
  assertEquals(
    body.memberships[0].accountId,
    "22222222-2222-4222-8222-222222222222",
  );
  assertEquals(body.memberships[0].effectivePermissions[0], {
    code: "security.audit.read",
    sourceRoleCodes: ["security"],
  });
  assertEquals(body.source.kind, "canonical");
  assertEquals(body.freshness.asOfUtc, evaluation.toISOString());
});

Deno.test("role detail route returns not found for unknown role", async () => {
  const handler = createSecurityRbacRouteHandler(
    inertDatabaseUrl,
    matrixStore(),
    {
      async getRoleDetail() {
        return null;
      },
    },
  );

  await assertRejects(
    async () =>
      await handler({
        request: new Request(
          "https://admin.test/api/v1/security/roles/missing",
        ),
        path: "/api/v1/security/roles/missing",
        admin: {
          accountId: crypto.randomUUID(),
          roles: ["security"],
          permissions: ["security.audit.read"],
        },
        origin: null,
      }),
    Error,
    "does not exist",
  );
});
