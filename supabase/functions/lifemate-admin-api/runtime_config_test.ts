import { assertEquals, assertThrows } from "jsr:@std/assert@1";

import { buildRestrictedDatabaseUrl } from "./runtime_config.ts";

Deno.test("restricted database URL preserves Supabase pooler suffix", () => {
  const value = buildRestrictedDatabaseUrl(
    "postgres://postgres.projectref:old@pooler.example.com:6543/postgres",
    "lifemate_admin_runtime",
    "0123456789abcdef0123456789abcdef",
  );
  const parsed = new URL(value);
  assertEquals(decodeURIComponent(parsed.username), "lifemate_admin_runtime.projectref");
  assertEquals(parsed.password, "0123456789abcdef0123456789abcdef");
});

Deno.test("restricted database password cannot be weak", () => {
  assertThrows(() =>
    buildRestrictedDatabaseUrl(
      "postgres://postgres@localhost:5432/postgres",
      "lifemate_admin_runtime",
      "short",
    )
  );
});
