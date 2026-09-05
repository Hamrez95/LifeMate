import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { createFeedbackAdminRouteHandler } from "./feedback_admin_routes.ts";
import { ApiError } from "./validation.ts";

const handler = createFeedbackAdminRouteHandler(
  "postgres://u:p@127.0.0.1:65432/db",
);
const accountId = "11111111-1111-4111-8111-111111111111";
const itemId = "22222222-2222-4222-8222-222222222222";

function context(request: Request, permissions: string[]) {
  return {
    request,
    path: new URL(request.url).pathname,
    accountId,
    admin: { accountId, roles: ["product"], permissions },
    correlationId: "33333333-3333-4333-8333-333333333333",
    origin: null,
  };
}

Deno.test("feedback Admin read fails closed without feedback.read", async () => {
  const request = new Request("https://admin.test/api/v1/feedback");
  const error = await assertRejects(
    () => handler(context(request, [])),
    ApiError,
  );
  assertEquals(error.status, 403);
  assertEquals(error.code, "admin_permission_denied");
});

Deno.test("feedback Admin filters reject unsupported product shape before database access", async () => {
  const request = new Request(
    "https://admin.test/api/v1/feedback?product=bad%20product",
  );
  const error = await assertRejects(
    () => handler(context(request, ["feedback.read"])),
    ApiError,
  );
  assertEquals(error.status, 400);
  assertEquals(error.code, "feedback_product_invalid");
});

Deno.test("feedback Admin action rejects URL-shaped product issue references", async () => {
  const request = new Request(
    `https://admin.test/api/v1/feedback/${itemId}/actions`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "idempotency-key": "feedback-action-001",
      },
      body: JSON.stringify({
        expectedStatus: "Triaged",
        action: "LinkProductIssue",
        reason: "Link to the reviewed internal product issue.",
        productIssueRef: "https://github.com/example/issue/1",
      }),
    },
  );
  const error = await assertRejects(
    () => handler(context(request, ["feedback.write"])),
    ApiError,
  );
  assertEquals(error.status, 400);
  assertEquals(error.code, "feedback_product_issue_ref_invalid");
});

Deno.test("feedback Admin action requires support id only for LinkSupport", async () => {
  const request = new Request(
    `https://admin.test/api/v1/feedback/${itemId}/actions`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "idempotency-key": "feedback-action-002",
      },
      body: JSON.stringify({
        expectedStatus: "Submitted",
        action: "Acknowledge",
        reason: "Acknowledge the user feedback for triage.",
        supportTicketId: "44444444-4444-4444-8444-444444444444",
      }),
    },
  );
  const error = await assertRejects(
    () => handler(context(request, ["feedback.write"])),
    ApiError,
  );
  assertEquals(error.status, 400);
  assertEquals(error.code, "feedback_support_link_forbidden");
});
