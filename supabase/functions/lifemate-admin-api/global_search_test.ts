import {
  authorizedSearchDomains,
  globalSearchPermission,
  parseGlobalSearchQuery,
  safeSearchLogFields,
} from "./global_search.ts";

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

async function assertRejects(
  fn: () => unknown | Promise<unknown>,
  code: string,
) {
  try {
    await fn();
  } catch (error) {
    if (
      error && typeof error === "object" && "code" in error &&
      error.code === code
    ) return;
    throw error;
  }
  throw new Error(`Expected rejection with ${code}`);
}

Deno.test("global search parser enforces minimum query and bounded pagination", async () => {
  const query = parseGlobalSearchQuery(
    new URL(
      "https://admin.test/api/v1/search?q=%D8%AD%D9%85%DB%8C%D8%AF&types=users,support&page=2&pageSize=10",
    ),
  );
  assertEquals(query.q, "حمید");
  assertEquals(query.domains, ["users", "support"]);
  assertEquals(query.page, 2);
  assertEquals(query.pageSize, 10);

  await assertRejects(
    () =>
      parseGlobalSearchQuery(new URL("https://admin.test/api/v1/search?q=ab")),
    "search_query_invalid",
  );
  await assertRejects(
    () =>
      parseGlobalSearchQuery(
        new URL("https://admin.test/api/v1/search?q=valid&types=users,health"),
      ),
    "search_types_invalid",
  );
  await assertRejects(
    () =>
      parseGlobalSearchQuery(
        new URL(
          "https://admin.test/api/v1/search?q=valid&types=users,women_health",
        ),
      ),
    "search_types_invalid",
  );
});

Deno.test("global search authorization is domain scoped and fail closed", () => {
  const requested = ["users", "support", "commerce", "campaigns"] as const;
  assertEquals(
    authorizedSearchDomains(requested, ["users.read.basic", "commerce.read"]),
    ["users", "commerce"],
  );
  assertEquals(authorizedSearchDomains(requested, []), []);
  assertEquals(globalSearchPermission.campaigns, "marketing.read");
});

Deno.test("safe search log metadata never contains raw query text", () => {
  const query = parseGlobalSearchQuery(
    new URL(
      "https://admin.test/api/v1/search?q=Sensitive%20Operator%20Query&types=users",
    ),
  );
  const fields = safeSearchLogFields(query, ["users"]);
  const serialized = JSON.stringify(fields);
  if (serialized.includes("Sensitive Operator Query")) {
    throw new Error("Raw search query leaked into log metadata");
  }
  assertEquals(fields.queryLength, 24);
  assertEquals(fields.authorizedDomains, ["users"]);
});
