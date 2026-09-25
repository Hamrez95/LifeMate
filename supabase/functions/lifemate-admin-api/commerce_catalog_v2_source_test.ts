import { assert, assertStringIncludes } from "jsr:@std/assert";

async function source(path: string): Promise<string> {
  return await Deno.readTextFile(new URL(path, import.meta.url));
}

Deno.test("catalog v2 routes stay behind purpose-specific admin permission", async () => {
  const routes = await source("./commerce_catalog_v2_mutation_routes.ts");
  assertStringIncludes(
    routes,
    'requirePermission(admin, "commerce.catalog.write")',
  );
  assert(!routes.includes("service_role"));
  assert(!routes.includes("supabase.from"));
});

Deno.test("catalog v2 read model exposes versions required for optimistic writes", async () => {
  const service = await source("./commerce_catalog_v2_service.ts");
  assertStringIncludes(service, "p.version");
  assertStringIncludes(service, "version: Number(row.version)");
  assertStringIncludes(service, "version: Number(offer.version)");
  assertStringIncludes(service, "version: Number(policy.version)");
});

Deno.test("catalog v2 mutation migrations are audited idempotent and runtime narrow", async () => {
  const foundation = await source(
    "../../migrations/20260827212000_commerce_catalog_v2_mutations.sql",
  );
  const hardening = await source(
    "../../migrations/20260827212100_commerce_catalog_v2_mutation_hardening.sql",
  );
  const lifecycle = await source(
    "../../migrations/20260827212200_commerce_catalog_v2_lifecycle_integrity.sql",
  );
  const combined = `${foundation}\n${hardening}\n${lifecycle}`;
  assertStringIncludes(combined, "admin.idempotency_keys");
  assertStringIncludes(combined, "admin.audit_events");
  assertStringIncludes(combined, "security definer");
  assertStringIncludes(combined, "commerce.catalog.write");
  assertStringIncludes(
    combined,
    "grant execute on function admin.update_commerce_catalog_product",
  );
  assertStringIncludes(
    combined,
    "grant execute on function admin.update_commerce_catalog_bundle",
  );
  assert(!combined.includes("grant insert on commerce.products"));
  assert(!combined.includes("grant update on commerce.offers"));
  assert(!combined.includes("grant delete on commerce.bundles"));
});

Deno.test("catalog lifecycle uses retirement instead of destructive catalog deletes", async () => {
  const lifecycle = await source(
    "../../migrations/20260827212200_commerce_catalog_v2_lifecycle_integrity.sql",
  );
  assertStringIncludes(
    lifecycle,
    "update commerce.bundles b set status='Retired'",
  );
  assertStringIncludes(
    lifecycle,
    "update commerce.offers set status='Retired'",
  );
  assert(!lifecycle.includes("delete from commerce.products"));
  assert(!lifecycle.includes("delete from commerce.offers"));
  assert(!lifecycle.includes("delete from commerce.bundles"));
});

Deno.test("bundle composition replacement is transactional and bounded", async () => {
  const migration = await source(
    "../../migrations/20260827212000_commerce_catalog_v2_mutations.sql",
  );
  assertStringIncludes(
    migration,
    "delete from commerce.bundle_items where bundle_id=p_bundle",
  );
  assertStringIncludes(
    migration,
    "insert into commerce.bundle_items(bundle_id,offer_id,quantity)",
  );
  assertStringIncludes(migration, "expected_count>32");
});
