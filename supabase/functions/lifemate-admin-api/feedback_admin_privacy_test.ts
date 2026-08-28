import { assert, assertStringIncludes } from "jsr:@std/assert@1";

Deno.test("marketing and analytics are not granted raw feedback queue access", async () => {
  const sql = await Deno.readTextFile(
    "../../migrations/20260828025000_feedback_raw_text_role_scope.sql",
  );

  assertStringIncludes(sql, "permission_code = 'feedback.read'");
  assertStringIncludes(sql, "r.code in ('marketing','analytics')");
  assertStringIncludes(sql, "delete from admin.role_permissions");
  assertStringIncludes(sql, "Aggregate feedback/NPS trends. No free-text payload is returned.");

  const revocation = /delete from admin\.role_permissions[\s\S]*permission_code = 'feedback\.read'[\s\S]*marketing','analytics/;
  assert(revocation.test(sql));
});
