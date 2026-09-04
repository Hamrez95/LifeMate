import { assertEquals } from "jsr:@std/assert@1.0.14";
import { createResearchDatasetRouteHandler } from "./research_dataset_routes.ts";
import { ApiError } from "./validation.ts";

const handler = createResearchDatasetRouteHandler(
  "postgres://unused:unused@127.0.0.1:1/unused",
);
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
      admin: {
        accountId: base.accountId,
        roles: ["product"],
        permissions: ["analytics.read"],
      },
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
    headers: {
      "content-type": "application/json",
      "idempotency-key": "research-dataset-direct-identifier-test",
    },
    body: JSON.stringify({
      name: "Age cohort",
      datasetKind: "HealthObservationAggregate",
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
      admin: {
        accountId: base.accountId,
        roles: ["founder"],
        permissions: ["analytics.read"],
      },
    });
    throw new Error("expected rejection");
  } catch (error) {
    assertEquals(error instanceof ApiError, true);
    assertEquals(
      (error as ApiError).code,
      "research_direct_identifier_forbidden",
    );
  }
});

Deno.test("research route rejects unknown dataset kind before persistence", async () => {
  const request = new Request("https://example.test/api/v1/research/datasets", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "idempotency-key": "research-dataset-kind-test",
    },
    body: JSON.stringify({
      name: "Unsafe generic export",
      datasetKind: "RawSql",
      purpose: "research_deidentified_dataset",
      sourceCategory: "FirstPartyUserInput",
      filters: {},
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
      admin: {
        accountId: base.accountId,
        roles: ["founder"],
        permissions: ["analytics.read"],
      },
    });
    throw new Error("expected rejection");
  } catch (error) {
    assertEquals(error instanceof ApiError, true);
    assertEquals((error as ApiError).code, "research_dataset_kind_invalid");
  }
});

Deno.test("research export route validates founder and bounded format before database access", async () => {
  const datasetId = "00000000-0000-4000-8000-000000000010";
  const path = `/api/v1/research/datasets/${datasetId}/exports`;

  try {
    await handler({
      ...base,
      path,
      request: new Request(`https://example.test${path}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "idempotency-key": "research-export-non-founder",
        },
        body: JSON.stringify({ format: "CSV" }),
      }),
      admin: {
        accountId: base.accountId,
        roles: ["product"],
        permissions: ["analytics.read"],
      },
    });
    throw new Error("expected rejection");
  } catch (error) {
    assertEquals(error instanceof ApiError, true);
    assertEquals((error as ApiError).code, "research_founder_required");
  }

  try {
    await handler({
      ...base,
      path,
      request: new Request(`https://example.test${path}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "idempotency-key": "research-export-format",
        },
        body: JSON.stringify({ format: "PDF" }),
      }),
      admin: {
        accountId: base.accountId,
        roles: ["founder"],
        permissions: ["analytics.read"],
      },
    });
    throw new Error("expected rejection");
  } catch (error) {
    assertEquals(error instanceof ApiError, true);
    assertEquals((error as ApiError).code, "research_export_format_invalid");
  }
});
