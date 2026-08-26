import { parseCommerceCatalogV2Query } from "./commerce_catalog_v2.ts";

function assertEquals(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

async function assertRejects(fn: () => unknown | Promise<unknown>, expectedCode: string) {
  try {
    await fn();
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === expectedCode) return;
    throw error;
  }
  throw new Error(`Expected rejection with ${expectedCode}`);
}

Deno.test("catalog v2 defaults to published catalog only", () => {
  assertEquals(
    parseCommerceCatalogV2Query(new URL("https://admin.test/api/v1/commerce/catalog-v2")),
    { product: null, includeHidden: false },
  );
});

Deno.test("catalog v2 normalizes product and supports explicit hidden admin view", () => {
  assertEquals(
    parseCommerceCatalogV2Query(new URL("https://admin.test/api/v1/commerce/catalog-v2?product=WellMate-CareMate&includeHidden=true")),
    { product: "wellmate-caremate", includeHidden: true },
  );
});

Deno.test("catalog v2 rejects invalid product and boolean query values", async () => {
  await assertRejects(
    () => parseCommerceCatalogV2Query(new URL("https://admin.test/api/v1/commerce/catalog-v2?product=bad%20code")),
    "commerce_product_invalid",
  );
  await assertRejects(
    () => parseCommerceCatalogV2Query(new URL("https://admin.test/api/v1/commerce/catalog-v2?includeHidden=yes")),
    "commerce_include_hidden_invalid",
  );
});
