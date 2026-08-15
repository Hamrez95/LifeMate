import { assertEquals, assertThrows } from "jsr:@std/assert";

import {
  parseCommerceOverviewQuery,
  SUBSCRIPTION_STATUSES,
} from "./commerce.ts";
import { ApiError } from "./validation.ts";

Deno.test("commerce overview defaults to bounded server pagination", () => {
  assertEquals(
    parseCommerceOverviewQuery(
      new URL("https://admin.example/api/v1/commerce/overview"),
    ),
    {
      page: 1,
      pageSize: 25,
      offset: 0,
      product: null,
      status: null,
    },
  );
});

Deno.test("commerce overview accepts product and subscription status filters", () => {
  for (const status of SUBSCRIPTION_STATUSES) {
    const query = parseCommerceOverviewQuery(
      new URL(
        `https://admin.example/api/v1/commerce/overview?page=2&pageSize=50&product=wellmate&status=${status}`,
      ),
    );
    assertEquals(query.page, 2);
    assertEquals(query.pageSize, 50);
    assertEquals(query.offset, 50);
    assertEquals(query.product, "wellmate");
    assertEquals(query.status, status);
  }
});

Deno.test("commerce overview rejects unsafe or unbounded filters", () => {
  for (
    const url of [
      "https://admin.example/api/v1/commerce/overview?page=0",
      "https://admin.example/api/v1/commerce/overview?pageSize=5000",
      "https://admin.example/api/v1/commerce/overview?product=bad%20product",
      "https://admin.example/api/v1/commerce/overview?status=Unknown",
    ]
  ) {
    assertThrows(() => parseCommerceOverviewQuery(new URL(url)), ApiError);
  }
});
