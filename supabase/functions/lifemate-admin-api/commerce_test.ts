import { parseCommerceDashboardQuery } from "./commerce.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("commerce dashboard defaults are bounded", () => {
  const query = parseCommerceDashboardQuery(
    new URL("https://admin.example/api/v1/commerce/dashboard"),
  );
  assert(query.page === 1, "default page must be 1");
  assert(query.pageSize === 25, "default page size must be 25");
  assert(query.offset === 0, "default offset must be 0");
  assert(query.product === null, "product must default to null");
  assert(query.plan === null, "plan must default to null");
  assert(query.status === null, "status must default to null");
});

Deno.test("commerce dashboard accepts canonical filters", () => {
  const query = parseCommerceDashboardQuery(
    new URL(
      "https://admin.example/api/v1/commerce/dashboard?page=3&pageSize=50&product=WellMate&plan=Premium_Annual&status=Active",
    ),
  );
  assert(query.page === 3, "page filter must be parsed");
  assert(query.pageSize === 50, "page size filter must be parsed");
  assert(query.offset === 100, "offset must derive from page and size");
  assert(query.product === "wellmate", "product code must normalize");
  assert(query.plan === "premium_annual", "plan code must normalize");
  assert(query.status === "Active", "status must remain canonical");
});

Deno.test("commerce dashboard rejects unbounded or unsafe filters", () => {
  for (const url of [
    "https://admin.example/api/v1/commerce/dashboard?pageSize=1000",
    "https://admin.example/api/v1/commerce/dashboard?status=Unknown",
    "https://admin.example/api/v1/commerce/dashboard?product=wellmate%2F..",
  ]) {
    let rejected = false;
    try {
      parseCommerceDashboardQuery(new URL(url));
    } catch {
      rejected = true;
    }
    assert(rejected, `query must reject unsafe input: ${url}`);
  }
});

Deno.test("commerce source never exposes provider reference hashes or payment secrets", async () => {
  const source = await Deno.readTextFile(
    new URL("./commerce_store.ts", import.meta.url),
  );
  assert(
    !source.includes("provider_reference_hash"),
    "dashboard must not select provider reference hashes",
  );
  assert(!source.includes("card_number"), "dashboard must not select card numbers");
  assert(!source.includes("payment_secret"), "dashboard must not select payment secrets");
  assert(
    source.includes("coalesce(s.owner_account_id, s.payer_account_id)"),
    "dashboard should expose only the minimum account identifier needed for navigation",
  );
});

Deno.test("commerce endpoint remains permission gated and server-side", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(
    source.includes('path === "/api/v1/commerce/dashboard"'),
    "commerce dashboard route must be registered",
  );
  assert(
    source.includes('requirePermission(admin, "commerce.read")'),
    "commerce dashboard must require commerce.read",
  );
});
