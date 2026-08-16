import { assertEquals, assertNotEquals, assertRejects } from "jsr:@std/assert@1";
import {
  hashMarketingExecutionActionRequest,
  hashMarketingScheduleRequest,
  matchMarketingCancelExecutionPath,
  matchMarketingRetryExecutionPath,
  matchMarketingSchedulePublishPath,
  parseMarketingContentCalendarQuery,
  parseMarketingExecutionActionPayload,
  parseMarketingSchedulePayload,
} from "./marketing_content_calendar.ts";

const CAMPAIGN_ID = "123e4567-e89b-42d3-a456-426614174888";
const EXECUTION_ID = "223e4567-e89b-42d3-a456-426614174888";

Deno.test("ADM-MKT-006 calendar query keeps date range, status and timezone bounded", () => {
  const query = parseMarketingContentCalendarQuery(
    new URL(
      "https://admin.test/api/v1/marketing/content-calendar?from=2026-08-01&to=2026-08-31&timezone=Asia%2FTehran&status=Scheduled",
    ),
  );
  assertEquals(query, {
    from: "2026-08-01",
    to: "2026-08-31",
    timezone: "Asia/Tehran",
    status: "Scheduled",
  });

  assertRejects(() =>
    Promise.resolve(
      parseMarketingContentCalendarQuery(
        new URL(
          "https://admin.test/api/v1/marketing/content-calendar?from=2026-01-01&to=2026-12-31",
        ),
      ),
    )
  );
  assertRejects(() =>
    Promise.resolve(
      parseMarketingContentCalendarQuery(
        new URL(
          "https://admin.test/api/v1/marketing/content-calendar?timezone=../../unsafe",
        ),
      ),
    )
  );
});

Deno.test("ADM-MKT-006 scheduling and execution action routes are explicit", () => {
  assertEquals(
    matchMarketingSchedulePublishPath(
      `/api/v1/marketing/campaigns/${CAMPAIGN_ID}/actions/schedule-publish`,
    ),
    CAMPAIGN_ID,
  );
  assertEquals(
    matchMarketingCancelExecutionPath(
      `/api/v1/marketing/publish-executions/${EXECUTION_ID}/actions/cancel`,
    ),
    EXECUTION_ID,
  );
  assertEquals(
    matchMarketingRetryExecutionPath(
      `/api/v1/marketing/publish-executions/${EXECUTION_ID}/actions/retry`,
    ),
    EXECUTION_ID,
  );
  assertEquals(
    matchMarketingRetryExecutionPath(
      `/api/v1/marketing/publish-executions/${EXECUTION_ID}/actions/cancel`,
    ),
    null,
  );
});

Deno.test("ADM-MKT-006 schedule payload requires local time, visible timezone and audit reason", async () => {
  const payload = await parseMarketingSchedulePayload(
    new Request("https://admin.test", {
      method: "POST",
      body: JSON.stringify({
        scheduledLocal: "2026-08-20T18:30",
        timezone: "Asia/Tehran",
        reason: "Schedule the human-approved revision for the planned launch window.",
      }),
    }),
  );
  assertEquals(payload.scheduledLocal, "2026-08-20T18:30");
  assertEquals(payload.timezone, "Asia/Tehran");

  await assertRejects(() =>
    parseMarketingSchedulePayload(
      new Request("https://admin.test", {
        method: "POST",
        body: JSON.stringify({
          scheduledLocal: "tomorrow evening",
          timezone: "Asia/Tehran",
          reason: "Schedule the approved campaign safely later.",
        }),
      }),
    )
  );
});

Deno.test("ADM-MKT-006 cancel and retry reasons are bounded and action hashes cannot collide", async () => {
  const payload = await parseMarketingExecutionActionPayload(
    new Request("https://admin.test", {
      method: "POST",
      body: JSON.stringify({
        reason: "Cancel this scheduled publish because the launch window changed.",
      }),
    }),
  );
  const cancelHash = await hashMarketingExecutionActionRequest(
    "cancel",
    EXECUTION_ID,
    payload,
  );
  const retryHash = await hashMarketingExecutionActionRequest(
    "retry",
    EXECUTION_ID,
    payload,
  );
  assertEquals(cancelHash.length, 64);
  assertEquals(retryHash.length, 64);
  assertNotEquals(cancelHash, retryHash);
});

Deno.test("ADM-MKT-006 schedule hash binds campaign, timezone, local clock and reason", async () => {
  const first = await hashMarketingScheduleRequest(CAMPAIGN_ID, {
    scheduledLocal: "2026-08-20T18:30",
    timezone: "Asia/Tehran",
    reason: "Schedule the approved content for the planned launch window.",
  });
  const second = await hashMarketingScheduleRequest(CAMPAIGN_ID, {
    scheduledLocal: "2026-08-20T18:30",
    timezone: "UTC",
    reason: "Schedule the approved content for the planned launch window.",
  });
  assertEquals(first.length, 64);
  assertEquals(second.length, 64);
  assertNotEquals(first, second);
});
