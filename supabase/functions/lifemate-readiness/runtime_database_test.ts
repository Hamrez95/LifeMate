import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  buildRestrictedReadinessDatabaseUrl,
  classifyReadinessDatabaseTransport,
  isReadinessTransactionPoolerUrl,
  parseReadinessBoolean,
  validateReadinessDatabaseTransport,
} from "./runtime_database.ts";

Deno.test("readiness recognizes transaction pooler transport only on 6543", () => {
  const pooler =
    "postgresql://lifemate_edge_runtime.projectref:secret@aws-0-eu-west-1.pooler.supabase.com:6543/postgres";
  const direct =
    "postgresql://lifemate_edge_runtime:secret@db.projectref.supabase.co:5432/postgres";

  assertEquals(isReadinessTransactionPoolerUrl(pooler), true);
  assertEquals(isReadinessTransactionPoolerUrl(direct), false);
  assertEquals(classifyReadinessDatabaseTransport(pooler), "transaction_pooler");
  assertEquals(classifyReadinessDatabaseTransport(direct), "direct_or_other");
});

Deno.test("readiness pooler requirement is strict and fails closed", () => {
  const direct =
    "postgresql://lifemate_edge_runtime:secret@db.projectref.supabase.co:5432/postgres";
  const pooler =
    "postgresql://lifemate_edge_runtime.projectref:secret@aws-0-eu-west-1.pooler.supabase.com:6543/postgres";

  assertThrows(
    () => validateReadinessDatabaseTransport(direct, true),
    Error,
    "transaction-pooler",
  );
  validateReadinessDatabaseTransport(pooler, true);
  assertEquals(
    parseReadinessBoolean("LIFEMATE_REQUIRE_TRANSACTION_POOLER", "true", false),
    true,
  );
  assertThrows(
    () =>
      parseReadinessBoolean(
        "LIFEMATE_REQUIRE_TRANSACTION_POOLER",
        "tru",
        false,
      ),
    Error,
    "must be true or false",
  );
});

Deno.test("restricted readiness URL preserves Supavisor project suffix", () => {
  const value = buildRestrictedReadinessDatabaseUrl(
    "postgresql://postgres.projectref:bootstrap@aws-0-eu-west-1.pooler.supabase.com:6543/postgres",
    "runtime-password-123456789012345678901234567890",
  );
  const parsed = new URL(value);
  assertEquals(
    decodeURIComponent(parsed.username),
    "lifemate_edge_runtime.projectref",
  );
  assertEquals(parsed.port, "6543");
});
