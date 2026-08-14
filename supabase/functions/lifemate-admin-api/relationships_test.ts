import { assertEquals, assertThrows } from "jsr:@std/assert";

import { parseRelationshipOverviewQuery } from "./relationships.ts";
import { ApiError } from "./validation.ts";

Deno.test("relationship overview query defaults to bounded pagination", () => {
  const query = parseRelationshipOverviewQuery(
    new URL("https://admin.example/api/v1/relationships/overview"),
  );
  assertEquals(query, {
    page: 1,
    pageSize: 25,
    kind: null,
    status: null,
  });
});

Deno.test("relationship overview query accepts approved kind and status", () => {
  const query = parseRelationshipOverviewQuery(
    new URL(
      "https://admin.example/api/v1/relationships/overview?page=2&pageSize=50&kind=consent&status=Granted",
    ),
  );
  assertEquals(query, {
    page: 2,
    pageSize: 50,
    kind: "consent",
    status: "Granted",
  });
});

Deno.test("relationship overview query accepts all canonical kinds", () => {
  for (const kind of ["relationship", "consent", "access_grant"] as const) {
    const query = parseRelationshipOverviewQuery(
      new URL(`https://admin.example/api/v1/relationships/overview?kind=${kind}`),
    );
    assertEquals(query.kind, kind);
  }
});

Deno.test("relationship overview query rejects unknown kinds and malformed status", () => {
  assertThrows(
    () =>
      parseRelationshipOverviewQuery(
        new URL("https://admin.example/api/v1/relationships/overview?kind=permission"),
      ),
    ApiError,
  );
  assertThrows(
    () =>
      parseRelationshipOverviewQuery(
        new URL(
          "https://admin.example/api/v1/relationships/overview?status=Granted%20or%201=1",
        ),
      ),
    ApiError,
  );
});

Deno.test("relationship overview query rejects unbounded page sizes", () => {
  assertThrows(
    () =>
      parseRelationshipOverviewQuery(
        new URL(
          "https://admin.example/api/v1/relationships/overview?pageSize=5000",
        ),
      ),
    ApiError,
  );
});
