import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  buildRestrictedDatabaseUrl,
  selectContactHashingSecret,
} from "./runtime_config.ts";

const environmentSecret = "environment-dedicated-secret-1234567890";
const dictionarySecret = "dictionary-dedicated-secret-12345678901";
const vaultSecret = "vault-dedicated-secret-1234567890123456";
const serviceRole = "service-role-secret-123456789012345678";

Deno.test("environment dedicated secret has highest priority", () => {
  assertEquals(
    selectContactHashingSecret({
      environment: environmentSecret,
      dictionary: dictionarySecret,
      vault: vaultSecret,
      serviceRole,
    }),
    environmentSecret,
  );
});

Deno.test("dictionary contact_hashing secret is accepted when environment is absent", () => {
  assertEquals(
    selectContactHashingSecret({
      dictionary: dictionarySecret,
      vault: vaultSecret,
      serviceRole,
    }),
    dictionarySecret,
  );
});

Deno.test("vault secret replaces a candidate equal to service role", () => {
  assertEquals(
    selectContactHashingSecret({
      environment: serviceRole,
      dictionary: serviceRole,
      vault: vaultSecret,
      serviceRole,
      defaultSecret: serviceRole,
    }),
    vaultSecret,
  );
});

Deno.test("generic default secret is never selected", () => {
  assertThrows(
    () =>
      selectContactHashingSecret({
        defaultSecret: "generic-default-secret-123456789012345",
        serviceRole,
      }),
    Error,
    "dedicated LifeMate contact hashing secret",
  );
});

Deno.test("short or missing dedicated secrets fail closed", () => {
  assertThrows(
    () =>
      selectContactHashingSecret({
        environment: "too-short",
        dictionary: null,
        vault: null,
        serviceRole,
      }),
    Error,
    "at least 32 characters",
  );
});

Deno.test("restricted database URL replaces direct postgres login", () => {
  const value = buildRestrictedDatabaseUrl(
    "postgresql://postgres:admin-password@db.example.test:5432/postgres?sslmode=require",
    "lifemate_edge_runtime",
    "runtime-password-123456789012345678901234567890",
  );
  const parsed = new URL(value);
  assertEquals(decodeURIComponent(parsed.username), "lifemate_edge_runtime");
  assertEquals(
    decodeURIComponent(parsed.password),
    "runtime-password-123456789012345678901234567890",
  );
  assertEquals(parsed.hostname, "db.example.test");
  assertEquals(parsed.port, "5432");
  assertEquals(parsed.pathname, "/postgres");
  assertEquals(parsed.searchParams.get("sslmode"), "require");
});

Deno.test("restricted database URL preserves Supabase pooler project suffix", () => {
  const value = buildRestrictedDatabaseUrl(
    "postgresql://postgres.projectref:admin-password@pooler.example.test:6543/postgres",
    "lifemate_edge_runtime",
    "runtime-password-123456789012345678901234567890",
  );
  const parsed = new URL(value);
  assertEquals(
    decodeURIComponent(parsed.username),
    "lifemate_edge_runtime.projectref",
  );
});

Deno.test("restricted database URL rejects weak credentials", () => {
  assertThrows(
    () =>
      buildRestrictedDatabaseUrl(
        "postgresql://postgres:admin@db.example.test/postgres",
        "lifemate_edge_runtime",
        "short",
      ),
    Error,
    "at least 32 characters",
  );
});
