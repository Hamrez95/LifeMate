import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert";

import {
  hashSupportTicketActionRequest,
  matchSupportTicketActionPath,
  matchSupportTicketDetailPath,
  matchSupportTicketEventsPath,
  parseSupportTicketActionPayload,
  parseSupportTicketEventsQuery,
} from "./support_detail.ts";
import { ApiError } from "./validation.ts";

const TICKET_ID = "91000000-0000-4000-8000-000000000101";
const ASSIGNEE_ID = "91000000-0000-4000-8000-000000000102";

Deno.test("support ticket detail route matches only a safe ticket id", () => {
  assertEquals(
    matchSupportTicketDetailPath(`/api/v1/support/tickets/${TICKET_ID}`),
    TICKET_ID,
  );
  assertEquals(
    matchSupportTicketEventsPath(`/api/v1/support/tickets/${TICKET_ID}/events`),
    TICKET_ID,
  );
  assertThrows(
    () => matchSupportTicketDetailPath("/api/v1/support/tickets/not-a-uuid"),
    ApiError,
  );
});

Deno.test("support ticket action paths resolve to explicit audited operations", () => {
  assertEquals(
    matchSupportTicketActionPath(
      `/api/v1/support/tickets/${TICKET_ID}/actions/note`,
    ),
    { ticketId: TICKET_ID, action: "add_note" },
  );
  assertEquals(
    matchSupportTicketActionPath(
      `/api/v1/support/tickets/${TICKET_ID}/actions/assignee`,
    ),
    { ticketId: TICKET_ID, action: "set_assignee" },
  );
});

Deno.test("support ticket events use bounded server pagination", () => {
  assertEquals(
    parseSupportTicketEventsQuery(
      new URL(
        `https://admin.example/api/v1/support/tickets/${TICKET_ID}/events?page=2&pageSize=25`,
      ),
    ),
    { page: 2, pageSize: 25, offset: 25 },
  );
  assertThrows(
    () =>
      parseSupportTicketEventsQuery(
        new URL(
          `https://admin.example/api/v1/support/tickets/${TICKET_ID}/events?pageSize=1000`,
        ),
      ),
    ApiError,
  );
});

Deno.test("support ticket mutations validate note and assignee payloads", async () => {
  const noteRequest = new Request("https://admin.example", {
    method: "POST",
    body: JSON.stringify({ note: "پیگیری داخلی معتبر برای این تیکت." }),
  });
  assertEquals(await parseSupportTicketActionPayload(noteRequest, "add_note"), {
    note: "پیگیری داخلی معتبر برای این تیکت.",
  });

  const assigneeRequest = new Request("https://admin.example", {
    method: "POST",
    body: JSON.stringify({ assigneeAccountId: ASSIGNEE_ID }),
  });
  assertEquals(
    await parseSupportTicketActionPayload(assigneeRequest, "set_assignee"),
    { assigneeAccountId: ASSIGNEE_ID },
  );

  await assertRejects(
    () =>
      parseSupportTicketActionPayload(
        new Request("https://admin.example", {
          method: "POST",
          body: JSON.stringify({ note: "short" }),
        }),
        "add_note",
      ),
    ApiError,
  );
});

Deno.test("support ticket mutation hash is stable and action-specific", async () => {
  const first = await hashSupportTicketActionRequest(TICKET_ID, "set_status", {
    status: "Pending",
  });
  const replay = await hashSupportTicketActionRequest(TICKET_ID, "set_status", {
    status: "Pending",
  });
  const changed = await hashSupportTicketActionRequest(
    TICKET_ID,
    "set_status",
    {
      status: "Resolved",
    },
  );
  assertEquals(first, replay);
  if (first === changed) {
    throw new Error("mutation hash must change with payload");
  }
});
