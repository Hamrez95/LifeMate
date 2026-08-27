import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import { createSupportConversationRouteHandler } from "./support_conversations_routes.ts";
import { ApiError } from "./validation.ts";

const appUserId = "11111111-1111-4111-8111-111111111111";
const ticketId = "22222222-2222-4222-8222-222222222222";
const messageId = "33333333-3333-4333-8333-333333333333";

Deno.test("support route never accepts requester account identity from client", async () => {
  const calls: unknown[] = [];
  const handler = createSupportConversationRouteHandler({
    async open(owner: string, input: unknown) {
      calls.push({ owner, input });
      return { ticketId, messageId, replayed: false };
    },
    async send() { throw new Error("unexpected"); },
    async list() { return []; },
    async markRead() { return { ok: true }; },
  } as any);

  const response = await handler({
    request: new Request("https://example.test/api/v1/support/conversations", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        requesterAccountId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        productCode: "WellMate",
        category: "billing_issue",
        body: "  لطفاً در مورد اشتراک من راهنمایی کنید.  ",
        clientMessageId: messageId,
      }),
    }),
    path: "/api/v1/support/conversations",
    appUserId,
  });

  assertEquals(response?.status, 201);
  assertEquals(calls, [{
    owner: appUserId,
    input: {
      productCode: "wellmate",
      category: "billing_issue",
      body: "لطفاً در مورد اشتراک من راهنمایی کنید.",
      clientMessageId: messageId,
    },
  }]);
});

Deno.test("support category validation matches canonical ticket schema", async () => {
  const handler = createSupportConversationRouteHandler({
    async open() { throw new Error("should_not_reach_store"); },
    async send() { throw new Error("unexpected"); },
    async list() { return []; },
    async markRead() { return { ok: true }; },
  } as any);

  await assertRejects(
    () => handler({
      request: new Request("https://example.test/api/v1/support/conversations", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          category: "billing.issue",
          body: "hello",
          clientMessageId: messageId,
        }),
      }),
      path: "/api/v1/support/conversations",
      appUserId,
    }),
    ApiError,
    "Support category is invalid.",
  );
});

Deno.test("support list is bounded and owner-scoped through store input", async () => {
  const calls: unknown[] = [];
  const handler = createSupportConversationRouteHandler({
    async open() { throw new Error("unexpected"); },
    async send() { throw new Error("unexpected"); },
    async list(owner: string, ticket: string, beforeAt: string | null, limit: number) {
      calls.push({ owner, ticket, beforeAt, limit });
      return [{ messageId, senderKind: "Staff", body: "سلام", createdAtUtc: "2026-08-27T10:00:00.000Z" }];
    },
    async markRead() { return { ok: true }; },
  } as any);

  const response = await handler({
    request: new Request(`https://example.test/api/v1/support/conversations/${ticketId}?limit=25&beforeAt=2026-08-27T10:01:00Z`),
    path: `/api/v1/support/conversations/${ticketId}`,
    appUserId,
  });
  assertEquals(response?.status, 200);
  assertEquals(calls, [{
    owner: appUserId,
    ticket: ticketId,
    beforeAt: "2026-08-27T10:01:00.000Z",
    limit: 25,
  }]);
});
