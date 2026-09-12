import { assert, assertStringIncludes } from "jsr:@std/assert@1";

Deno.test("marketing and analytics get aggregate trends without raw feedback queue access", async () => {
  const sql = await Deno.readTextFile(
    "../../migrations/20260828025000_feedback_raw_text_role_scope.sql",
  );
  const routes = await Deno.readTextFile("./feedback_admin_routes.ts");

  assertStringIncludes(sql, "permission_code = 'feedback.read'");
  assertStringIncludes(sql, "'feedback.trends.read'");
  assertStringIncludes(sql, "r.code in ('marketing','analytics')");
  assertStringIncludes(sql, "delete from admin.role_permissions");
  assertStringIncludes(
    sql,
    "admin.account_has_permission(p_actor_account_id,'feedback.trends.read')",
  );
  assertStringIncludes(
    sql,
    "Aggregate feedback/NPS trends guarded by feedback.trends.read. No free-text payload is returned.",
  );
  assertStringIncludes(routes, 'path === "/api/v1/feedback/trends"');
  assertStringIncludes(
    routes,
    'requirePermission(admin, "feedback.trends.read")',
  );

  const revocation =
    /delete from admin\.role_permissions[\s\S]*permission_code = 'feedback\.read'[\s\S]*marketing','analytics/;
  assert(revocation.test(sql));
  const aggregateGrant =
    /insert into admin\.role_permissions[\s\S]*'feedback\.trends\.read'[\s\S]*marketing','analytics/;
  assert(aggregateGrant.test(sql));
});
