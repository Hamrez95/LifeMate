import { assertEquals, assertThrows } from "jsr:@std/assert";

import { parseRelationshipLedgerQuery } from "./relationship_ledger.ts";
import { ApiError } from "./validation.ts";

const NOW = new Date("2026-08-14T06:00:00.000Z");

Deno.test("relationship ledger defaults to a bounded 90-day Tehran window", () => {
  const query = parseRelationshipLedgerQuery(
    new URL("https://admin.example/api/v1/relationships/ledger"),
    NOW,
  );
  assertEquals(query, {
    page: 1,
    pageSize: 25,
    kind: null,
    status: null,
    from: "2026-05-17",
    to: "2026-08-14",
  });
});

Deno.test("relationship ledger accepts type status and date filters", () => {
  const query = parseRelationshipLedgerQuery(
    new URL(
      "https://admin.example/api/v1/relationships/ledger?page=2&pageSize=50&kind=access_grant&status=Revoked&from=2026-08-01&to=2026-08-14",
    ),
    NOW,
  );
  assertEquals(query, {
    page: 2,
    pageSize: 50,
    kind: "access_grant",
    status: "Revoked",
    from: "2026-08-01",
    to: "2026-08-14",
  });
});

Deno.test("relationship ledger rejects invalid type status and date bounds", () => {
  assertThrows(
    () =>
      parseRelationshipLedgerQuery(
        new URL(
          "https://admin.example/api/v1/relationships/ledger?kind=permission",
        ),
        NOW,
      ),
    ApiError,
  );
  assertThrows(
    () =>
      parseRelationshipLedgerQuery(
        new URL(
          "https://admin.example/api/v1/relationships/ledger?status=Active%20or%201=1",
        ),
        NOW,
      ),
    ApiError,
  );
  assertThrows(
    () =>
      parseRelationshipLedgerQuery(
        new URL(
          "https://admin.example/api/v1/relationships/ledger?from=2025-01-01&to=2026-08-14",
        ),
        NOW,
      ),
    ApiError,
  );
});
