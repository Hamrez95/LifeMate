import { assertEquals, assertThrows } from "jsr:@std/assert";

import { parseSupportQueueQuery } from "./support.ts";
import { ApiError } from "./validation.ts";

const ASSIGNEE_ID = "91000000-0000-4000-8000-000000000001";

Deno.test("support queue defaults to bounded server pagination", () => {
  assertEquals(
    parseSupportQueueQuery(
      new URL("https://admin.example/api/v1/support/tickets"),
    ),
    {
      page: 1,
      pageSize: 25,
      offset: 0,
      search: null,
      status: null,
      priority: null,
      product: null,
      sla: null,
      assigneeAccountId: null,
      unassignedOnly: false,
    },
  );
});

Deno.test("support queue accepts operational filters", () => {
  assertEquals(
    parseSupportQueueQuery(
      new URL(
        `https://admin.example/api/v1/support/tickets?page=2&pageSize=50&q=%23123&status=Open&priority=Urgent&product=wellmate&sla=Breached&assignee=${ASSIGNEE_ID}`,
      ),
    ),
    {
      page: 2,
      pageSize: 50,
      offset: 50,
      search: "#123",
      status: "Open",
      priority: "Urgent",
      product: "wellmate",
      sla: "Breached",
      assigneeAccountId: ASSIGNEE_ID,
      unassignedOnly: false,
    },
  );
});

Deno.test("support queue supports the explicit unassigned filter", () => {
  const query = parseSupportQueueQuery(
    new URL(
      "https://admin.example/api/v1/support/tickets?assignee=unassigned",
    ),
  );
  assertEquals(query.assigneeAccountId, null);
  assertEquals(query.unassignedOnly, true);
});

Deno.test("support queue rejects unsafe filters and pagination", () => {
  for (
    const url of [
      "https://admin.example/api/v1/support/tickets?page=0",
      "https://admin.example/api/v1/support/tickets?priority=Critical",
      "https://admin.example/api/v1/support/tickets?sla=Unknown",
      "https://admin.example/api/v1/support/tickets?product=bad%20product",
      "https://admin.example/api/v1/support/tickets?assignee=not-a-uuid",
      "https://admin.example/api/v1/support/tickets?q=x",
    ]
  ) {
    assertThrows(() => parseSupportQueueQuery(new URL(url)), ApiError);
  }
});
