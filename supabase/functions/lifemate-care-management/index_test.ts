import { assert, assertFalse } from "jsr:@std/assert@1";

Deno.test("care-management auth lookup preserves varchar auth_subject semantics", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  assert(
    source.includes(
      "where auth_subject = ${authSubject} and status = 'Active'",
    ),
  );
  assertFalse(source.includes("auth_subject = ${authSubject}::uuid"));
  assert(source.includes('return Deno.env.get("SUPABASE_ANON_KEY") ?? null;'));
});
