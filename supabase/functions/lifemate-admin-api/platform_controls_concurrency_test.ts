import { assert, assertStringIncludes } from "jsr:@std/assert@1";

Deno.test("active control rules re-check and lock their parent control", async () => {
  const sql = await Deno.readTextFile(
    "../../migrations/20260828023500_platform_rule_parent_state_guard.sql",
  );

  assertStringIncludes(sql, "new.status <> 'Active'");
  assertStringIncludes(sql, "from platform.controls c");
  assertStringIncludes(sql, "where c.control_key = new.control_key");
  assertStringIncludes(sql, "for update");
  assertStringIncludes(sql, "platform_control_inactive");
  assertStringIncludes(sql, "before insert or update of status, control_key");
  assertStringIncludes(
    sql,
    "execute function platform.enforce_active_rule_parent()",
  );

  const parentCheck =
    /select c\.status[\s\S]*where c\.control_key = new\.control_key[\s\S]*for update[\s\S]*v_parent_status <> 'Active'/;
  assert(parentCheck.test(sql));
});
