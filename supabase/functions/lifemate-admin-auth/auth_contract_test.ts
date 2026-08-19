import { assert, assertEquals } from "jsr:@std/assert@1";

const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const runtime = await Deno.readTextFile(
  new URL("./runtime_config.ts", import.meta.url),
);

Deno.test("username auth keeps password handling in Supabase Auth", () => {
  assert(index.includes("signInWithPassword"));
  assert(index.includes("auth.admin.createUser"));
  assert(index.includes("email_confirm: true"));
  assert(!index.includes("encrypted_password"));
  assert(!index.includes("insert into auth.users"));
});

Deno.test("self signup remains pending and grants no role in edge code", () => {
  assert(index.includes('status: "pending_role_assignment"'));
  assert(index.includes("register_pending_workforce_account"));
  assert(!index.includes("insert into admin.member_roles"));
});

Deno.test("public auth boundary is origin allow-listed and rate limited", () => {
  assert(index.includes("config.allowedOrigins.has(origin)"));
  assert(index.includes("consume_workforce_auth_attempt"));
  assert(index.includes('"Cache-Control": "private, no-store"'));
  assert(index.includes('code: "invalid_credentials"'));
  assert(!index.includes("console.log"));
  assert(!index.includes("console.error"));
});

Deno.test("service role stays server-only and DB access uses restricted runtime", () => {
  assert(runtime.includes("SUPABASE_SERVICE_ROLE_KEY"));
  assert(runtime.includes("lifemate_admin_runtime"));
  assert(runtime.includes("lifemate_admin_runtime_password"));
  assert(!runtime.includes("NEXT_PUBLIC"));
});

Deno.test("username format is stable", () => {
  const match = index.match(/const usernamePattern = (\/.*?\/);/);
  assert(match);
  assertEquals(match[1], "/^[a-z0-9][a-z0-9._-]{2,31}$/");
});
