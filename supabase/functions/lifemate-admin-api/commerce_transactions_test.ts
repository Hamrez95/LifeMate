import { assertEquals, assertThrows } from "jsr:@std/assert";

import {
  parseCommerceTransactionsQuery,
  TRANSACTION_STATUSES,
} from "./commerce_transactions.ts";
import { ApiError } from "./validation.ts";

Deno.test("commerce transaction status vocabulary is explicit", () => {
  assertEquals(TRANSACTION_STATUSES, [
    "Pending",
    "Succeeded",
    "Failed",
    "Cancelled",
    "Refunded",
    "Chargeback",
  ]);
});

Deno.test("commerce transaction query is bounded", () => {
  assertEquals(
    parseCommerceTransactionsQuery(new URL("https://admin.example/transactions")),
    {
      page: 1,
      pageSize: 25,
      offset: 0,
      product: null,
      provider: null,
      status: null,
      fromUtc: null,
      toUtc: null,
      referenceId: null,
    },
  );

  const parsed = parseCommerceTransactionsQuery(
    new URL(
      "https://admin.example/transactions?page=2&pageSize=50&product=wellmate&provider=zarinpal&status=Succeeded&from=2026-08-01T00:00:00Z&to=2026-08-15T00:00:00Z&q=550e8400-e29b-41d4-a716-446655440000",
    ),
  );
  assertEquals(parsed.page, 2);
  assertEquals(parsed.pageSize, 50);
  assertEquals(parsed.offset, 50);
  assertEquals(parsed.product, "wellmate");
  assertEquals(parsed.provider, "zarinpal");
  assertEquals(parsed.status, "Succeeded");
  assertEquals(parsed.referenceId, "550e8400-e29b-41d4-a716-446655440000");
});

Deno.test("commerce transaction query rejects unsafe provider reference search", () => {
  assertThrows(
    () =>
      parseCommerceTransactionsQuery(
        new URL("https://admin.example/transactions?q=provider-payment-123"),
      ),
    ApiError,
  );
});

Deno.test("commerce transaction query rejects invalid range and status", () => {
  assertThrows(
    () =>
      parseCommerceTransactionsQuery(
        new URL("https://admin.example/transactions?status=Paid"),
      ),
    ApiError,
  );
  assertThrows(
    () =>
      parseCommerceTransactionsQuery(
        new URL(
          "https://admin.example/transactions?from=2026-08-15T00:00:00Z&to=2026-08-01T00:00:00Z",
        ),
      ),
    ApiError,
  );
});

Deno.test("transaction read model never selects raw provider references or account identifiers", async () => {
  const source = await Deno.readTextFile(new URL("./commerce_transactions_service.ts", import.meta.url));
  assertEquals(source.includes("provider_reference_hash"), false);
  assertEquals(source.includes("provider_event_reference_hash"), false);
  assertEquals(source.includes("select t.account_id"), false);
  assertEquals(source.includes("accountLinked"), true);
  assertEquals(source.includes("observation_state"), true);
});
