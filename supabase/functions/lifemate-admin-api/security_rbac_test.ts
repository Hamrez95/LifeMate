import { assertEquals, assertRejects } from "jsr:@std/assert";

import { buildAdminRbacMatrix } from "./security_rbac.ts";
import { createSecurityRbacRouteHandler } from "./security_rbac_routes.ts";

const inertDatabaseUrl = "postgres://test:test@127.0.0.1:5432/test";

Deno.test("RBAC matrix keeps canonical ordering and direct effective assignments", () => {
  const matrix = buildAdminRbacMatrix(
    [
      {
        code: "security",
        displayName: "Security",
        rank: 150,
        status: "Active",
        isSystem: true,
      },
      {
        code: "founder",
        displayName: "Founder",
        rank: 10,
        status: "Active",
        isSystem: true,
      },
    ],
    [
      {
        code: "security.roles.write",
        domain: "security",
        riskLevel: "HIGH_RISK",
        roleAssignable: true,
        description: "Manage roles",
      },
      {
        code: "analytics.read",
        domain: "analytics",
        riskLevel: "STANDARD",
        roleAssignable: true,
        description: "Read analytics",
      },
    ],
    [
      { roleCode: "security", permissionCode: "security.roles.write" },
      { roleCode: "founder", permissionCode: "analytics.read" },
    ],
  );

  assertEquals(matrix.state, "ready");
  assertEquals(matrix.roles.map((role) => role.code), ["founder", "security"]);
  assertEquals(matrix.permissionGroups.map((group) => group.domain), [
    "analytics",
    "security",
  ]);
  assertEquals(matrix.assignments, [
    {
      roleCode: "founder",
      permissionCode: "analytics.read",
      source: "direct",
      effective: true,
      blockedReason: null,
    },
    {
      roleCode: "security",
      permissionCode: "security.roles.write",
      source: "direct",
      effective: true,
      blockedReason: null,
    },
  ]);
  assertEquals(matrix.inheritance.supported, false);
});

Deno.test("RBAC matrix visibly blocks elevated permissions from ordinary roles", () => {
  const matrix = buildAdminRbacMatrix(
    [
      {
        code: "founder",
        displayName: "Founder",
        rank: 10,
        status: "Active",
        isSystem: true,
      },
    ],
    [
      {
        code: "health.read.elevated",
        domain: "health",
        riskLevel: "ELEVATED",
        roleAssignable: false,
        description: "Break-glass health access",
      },
    ],
    [{ roleCode: "founder", permissionCode: "health.read.elevated" }],
  );

  assertEquals(
    matrix.permissionGroups[0]?.permissions[0]?.roleAssignable,
    false,
  );
  assertEquals(matrix.assignments[0], {
    roleCode: "founder",
    permissionCode: "health.read.elevated",
    source: "direct",
    effective: false,
    blockedReason: "permission_not_role_assignable",
  });
});

Deno.test("RBAC matrix marks assignments on disabled roles as ineffective", () => {
  const matrix = buildAdminRbacMatrix(
    [
      {
        code: "legacy",
        displayName: "Legacy",
        rank: 500,
        status: "Disabled",
        isSystem: false,
      },
    ],
    [
      {
        code: "settings.read",
        domain: "settings",
        riskLevel: "STANDARD",
        roleAssignable: true,
        description: "Read settings",
      },
    ],
    [{ roleCode: "legacy", permissionCode: "settings.read" }],
  );

  assertEquals(matrix.assignments[0]?.effective, false);
  assertEquals(matrix.assignments[0]?.blockedReason, "role_disabled");
});

Deno.test("RBAC route denies missing security.audit.read before querying store", async () => {
  let queried = false;
  const handler = createSecurityRbacRouteHandler(inertDatabaseUrl, {
    async getRolePermissionMatrix() {
      queried = true;
      throw new Error("store must not be queried");
    },
  });

  await assertRejects(
    async () =>
      await handler({
        request: new Request(
          "https://admin.test/api/v1/security/role-permission-matrix",
        ),
        path: "/api/v1/security/role-permission-matrix",
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

Deno.test("RBAC route returns canonical matrix to authorized security reader", async () => {
  const handler = createSecurityRbacRouteHandler(inertDatabaseUrl, {
    async getRolePermissionMatrix() {
      return buildAdminRbacMatrix(
        [
          {
            code: "security",
            displayName: "Security",
            rank: 150,
            status: "Active",
            isSystem: true,
          },
        ],
        [
          {
            code: "security.audit.read",
            domain: "security",
            riskLevel: "SENSITIVE",
            roleAssignable: true,
            description: "Read security evidence",
          },
        ],
        [{ roleCode: "security", permissionCode: "security.audit.read" }],
      );
    },
  });

  const response = await handler({
    request: new Request(
      "https://admin.test/api/v1/security/role-permission-matrix",
    ),
    path: "/api/v1/security/role-permission-matrix",
    admin: {
      accountId: crypto.randomUUID(),
      roles: ["security"],
      permissions: ["security.audit.read"],
    },
    origin: null,
  });

  assertEquals(response?.status, 200);
  const body = await response?.json();
  assertEquals(body.state, "ready");
  assertEquals(body.roles[0].code, "security");
  assertEquals(body.assignments[0].effective, true);
  assertEquals(body.source.kind, "canonical");
  assertEquals(body.freshness.status, "fresh");
});
