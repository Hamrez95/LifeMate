import { assertEquals, assertThrows } from "jsr:@std/assert@1";

import { parseCommerceOverviewQuery } from "./commerce.ts";
import { parseCommerceDetailQuery } from "./commerce_detail.ts";
import { parseCommercePromotionsQuery } from "./commerce_promotions.ts";
import { parseCommerceTransactionsQuery } from "./commerce_transactions.ts";
import { parseUserDirectoryQuery } from "./directory.ts";
import { parseGlobalSearchQuery } from "./global_search.ts";
import { json } from "./http.ts";
import { parseRelationshipLedgerQuery } from "./relationship_ledger.ts";
import { parseRelationshipOverviewQuery } from "./relationships.ts";
import { parseSupportQueueQuery } from "./support.ts";
import { parseSupportTicketEventsQuery } from "./support_detail.ts";
import { parseUserActivityQuery } from "./user_detail.ts";
import {
  ADMIN_MAX_JSON_RESPONSE_BYTES,
  ADMIN_MAX_PAGE,
  ADMIN_MAX_PAGE_SIZE,
  ApiError,
} from "./validation.ts";

function url(pathAndQuery: string): URL {
  return new URL(`https://admin-api.test${pathAndQuery}`);
}

Deno.test("all current admin list surfaces reject deep pagination", () => {
  const tooDeep = ADMIN_MAX_PAGE + 1;
  const cases: Array<() => unknown> = [
    () => parseUserDirectoryQuery(url(`/api/v1/users?page=${tooDeep}`)),
    () => parseUserActivityQuery(url(`/api/v1/users/id/activity?page=${tooDeep}`)),
    () => parseRelationshipOverviewQuery(url(`/api/v1/relationships?page=${tooDeep}`)),
    () => parseRelationshipLedgerQuery(url(`/api/v1/relationships/ledger?page=${tooDeep}`)),
    () => parseSupportQueueQuery(url(`/api/v1/support/tickets?page=${tooDeep}`)),
    () => parseSupportTicketEventsQuery(url(`/api/v1/support/tickets/id/events?page=${tooDeep}`)),
    () => parseCommerceOverviewQuery(url(`/api/v1/commerce?page=${tooDeep}`)),
    () => parseCommerceDetailQuery(url(`/api/v1/commerce/plans/id?page=${tooDeep}`)),
    () => parseCommerceTransactionsQuery(url(`/api/v1/commerce/transactions?page=${tooDeep}`)),
    () => parseCommercePromotionsQuery(url(`/api/v1/commerce/promotions?page=${tooDeep}`)),
    () => parseGlobalSearchQuery(url(`/api/v1/search?q=ali&page=${tooDeep}`)),
  ];

  for (const parse of cases) {
    assertThrows(parse, ApiError);
  }
});

Deno.test("admin list page size is globally capped", () => {
  const tooLarge = ADMIN_MAX_PAGE_SIZE + 1;
  assertThrows(
    () => parseUserDirectoryQuery(url(`/api/v1/users?pageSize=${tooLarge}`)),
    ApiError,
  );
  assertThrows(
    () => parseCommercePromotionsQuery(url(`/api/v1/commerce/promotions?pageSize=${tooLarge}`)),
    ApiError,
  );
});

Deno.test("large synthetic list response stays bounded and no-store", async () => {
  const item = { id: "x".repeat(64), summary: "y".repeat(3500) };
  const response = json({ items: Array.from({ length: 100 }, () => item) }, 200, null);
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("cache-control"), "no-store");
  const body = await response.text();
  assertEquals(new TextEncoder().encode(body).byteLength < ADMIN_MAX_JSON_RESPONSE_BYTES, true);
});

Deno.test("oversized admin response fails closed before browser delivery", () => {
  assertThrows(
    () => json({ data: "x".repeat(ADMIN_MAX_JSON_RESPONSE_BYTES) }, 200, null),
    ApiError,
  );
});
