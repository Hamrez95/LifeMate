import { assertEquals } from "jsr:@std/assert@1.0.14";
import { createResearchDatasetRouteHandler } from "./research_dataset_routes.ts";
import { ApiError } from "./validation.ts";

const handler = createResearchDatasetRouteHandler("postgres://unused:unused@127.0.0.1:1/unused");
const base = {
  path: "/api/v1/research/datasets",
  accountId: "00000000-0000-4000-8000-000000000001",
  correlationId: "00000000-0000-4000-8000-000000000002",
  origin: null,
};

Deno.test("research route rejects non-founder before database access", async () => {
  try {
    await handler({
      ...base,
      request: new Request("https://example.test/api/v1/research/datasets"),
      admin: { accountId: base.accountId, roles: ["product"], permissions: ["analytics.read"] },
    });
    throw new Error("expected rejection");
  } catch (error) {
    assertEquals(error instanceof ApiError, true);
    assertEquals((error as ApiError).status, 403);
    assertEquals((error as ApiError).code, "research_founder_required");
  }
});

Deno.test("research route rejects direct identifiers before persistence", async () => {
  const request = new Request("https://example.test/api/v1/research/datasets", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      name: "Age cohort",
      purpose: "research_deidentified_dataset",
      sourceCategory: "FirstPartyUserInput",
      filters: { email: "person@example.test" },
      ageBucketYears: 2,
      minimumCohortSize: 20,
      smallCellThreshold: 5,
      quasiIdentifierRules: {},
      rowMode: "Aggregate",
    }),
  });
  try {
    await handler({
      ...base,
      request,
      admin: { accountId: base.accountId, roles: ["founder"], permissions: ["analytics.read"] },
    });
    throw new Error("expected rejection");
  } catch (error) {
    assertEquals(error instanceof ApiError, true);
    assertEquals((error as ApiError).code, "research_direct_identifier_forbidden");
  }
});
