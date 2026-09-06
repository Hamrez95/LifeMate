import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { parseHealthDocumentListQuery } from "./health_documents.ts";

Deno.test("Health Record list query is bounded and accepts only reviewed filters", () => {
  const query = parseHealthDocumentListQuery(
    new URLSearchParams({
      category: "lab_result",
      sourceProduct: "wellmate",
      fromDate: "2026-09-01",
      toDate: "2026-09-05",
      limit: "25",
    }),
  );
  assertEquals(query.category, "lab_result");
  assertEquals(query.sourceProduct, "wellmate");
  assertEquals(query.limit, 25);
  assertThrows(() =>
    parseHealthDocumentListQuery(new URLSearchParams({ limit: "101" }))
  );
  assertThrows(() =>
    parseHealthDocumentListQuery(new URLSearchParams({ category: "all" }))
  );
  assertThrows(() =>
    parseHealthDocumentListQuery(
      new URLSearchParams({ fromDate: "2026-09-06", toDate: "2026-09-05" }),
    )
  );
});

Deno.test("Health Record list cursor is opaque but structurally validated", () => {
  const cursor = btoa(JSON.stringify({
    createdAtUtc: "2026-09-05T12:00:00.000Z",
    id: "018f5e6a-7e91-4c26-8e18-a83c5531d111",
  }));
  assertEquals(
    parseHealthDocumentListQuery(new URLSearchParams({ cursor })).cursor,
    cursor,
  );
  assertThrows(() =>
    parseHealthDocumentListQuery(
      new URLSearchParams({ cursor: "not-a-cursor" }),
    )
  );
});
