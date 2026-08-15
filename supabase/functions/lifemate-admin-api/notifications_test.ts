import {
  assertSafeNotificationDeepLink,
  authorizedNotificationSources,
  hashNotificationReadStateRequest,
  notificationPermission,
  notificationSources,
  parseNotificationCountQuery,
  parseNotificationQuery,
  parseNotificationReadStateRequest,
} from "./notifications.ts";

function assertEquals(actual: unknown, expected: unknown, message?: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

async function assertRejects(
  fn: () => unknown | Promise<unknown>,
  code: string,
) {
  try {
    await fn();
  } catch (error) {
    if (
      error && typeof error === "object" && "code" in error &&
      error.code === code
    ) return;
    throw error;
  }
  throw new Error(`Expected rejection with ${code}`);
}

Deno.test("notification queries are allow-listed and bounded", async () => {
  const query = parseNotificationQuery(
    new URL(
      "https://admin.test/api/v1/notifications?page=2&pageSize=10&sources=support,operations&unreadOnly=true",
    ),
  );
  assertEquals(query, {
    page: 2,
    pageSize: 10,
    sources: ["support", "operations"],
    unreadOnly: true,
  });
  assertEquals(
    parseNotificationCountQuery(
      new URL("https://admin.test/api/v1/notifications/count?sources=security"),
    ),
    { sources: ["security"] },
  );

  await assertRejects(
    () =>
      parseNotificationQuery(
        new URL(
          "https://admin.test/api/v1/notifications?sources=support,health",
        ),
      ),
    "notification_sources_invalid",
  );
  await assertRejects(
    () =>
      parseNotificationQuery(
        new URL("https://admin.test/api/v1/notifications?sources=women_health"),
      ),
    "notification_sources_invalid",
  );
  await assertRejects(
    () =>
      parseNotificationQuery(
        new URL(
          "https://admin.test/api/v1/notifications?sources=support,support",
        ),
      ),
    "notification_sources_invalid",
  );
  await assertRejects(
    () =>
      parseNotificationQuery(
        new URL("https://admin.test/api/v1/notifications?unreadOnly=1"),
      ),
    "notification_unread_filter_invalid",
  );
  await assertRejects(
    () =>
      parseNotificationQuery(
        new URL("https://admin.test/api/v1/notifications?page=11"),
      ),
    "invalid_request",
  );
  await assertRejects(
    () =>
      parseNotificationCountQuery(
        new URL("https://admin.test/api/v1/notifications/count?debug=true"),
      ),
    "invalid_request",
  );
});

Deno.test("notification source permissions fail closed without leaking hidden domains", () => {
  assertEquals(notificationSources, [
    "support",
    "security",
    "operations",
    "finance",
    "product",
  ]);
  assertEquals(notificationPermission.support, "support.read");
  assertEquals(notificationPermission.security, "security.audit.read");
  assertEquals(notificationPermission.operations, "operations.read");
  assertEquals(notificationPermission.finance, "finance.read");
  assertEquals(notificationPermission.product, "analytics.read");
  assertEquals(
    authorizedNotificationSources(notificationSources, [
      "support.read",
      "operations.read",
    ]),
    ["support", "operations"],
  );
  assertEquals(authorizedNotificationSources(notificationSources, []), []);
});

Deno.test("notification deep links stay internal and source-scoped", async () => {
  const supportId = "11111111-1111-4111-8111-111111111111";
  assertEquals(
    assertSafeNotificationDeepLink("support", `/support/${supportId}`),
    `/support/${supportId}`,
  );
  assertEquals(
    assertSafeNotificationDeepLink("operations", "/operations"),
    "/operations",
  );
  assertEquals(assertSafeNotificationDeepLink("security", null), null);

  await assertRejects(
    () =>
      assertSafeNotificationDeepLink("support", "https://evil.test/support/1"),
    "notification_deep_link_invalid",
  );
  await assertRejects(
    () => assertSafeNotificationDeepLink("operations", `/support/${supportId}`),
    "notification_deep_link_invalid",
  );
  await assertRejects(
    () => assertSafeNotificationDeepLink("security", "//evil.test/security"),
    "notification_deep_link_invalid",
  );
});

Deno.test("notification read state requires exact safe source/key pairing", async () => {
  const payload = await parseNotificationReadStateRequest(
    new Request("https://admin.test/api/v1/notifications/actions/read-state", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        alertKey: "operations:outbox:dead-letter",
        source: "operations",
        read: true,
      }),
    }),
  );
  assertEquals(payload, {
    alertKey: "operations:outbox:dead-letter",
    source: "operations",
    read: true,
  });

  await assertRejects(
    () =>
      parseNotificationReadStateRequest(
        new Request("https://admin.test", {
          method: "POST",
          body: JSON.stringify({
            alertKey: "support:ticket:11111111-1111-4111-8111-111111111111:sla",
            source: "security",
            read: true,
          }),
        }),
      ),
    "notification_state_invalid",
  );
  await assertRejects(
    () =>
      parseNotificationReadStateRequest(
        new Request("https://admin.test", {
          method: "POST",
          body: JSON.stringify({
            alertKey: "health:person:secret",
            source: "health",
            read: true,
          }),
        }),
      ),
    "notification_state_invalid",
  );
});

Deno.test("notification read-state idempotency hash changes with state", async () => {
  const base = {
    alertKey: "operations:outbox:dead-letter",
    source: "operations" as const,
  };
  const readHash = await hashNotificationReadStateRequest({
    ...base,
    read: true,
  });
  const replayHash = await hashNotificationReadStateRequest({
    ...base,
    read: true,
  });
  const unreadHash = await hashNotificationReadStateRequest({
    ...base,
    read: false,
  });
  assertEquals(readHash.length, 64);
  assertEquals(readHash, replayHash);
  if (readHash === unreadHash) {
    throw new Error("Read and unread hashes must differ");
  }
});
