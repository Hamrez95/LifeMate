import {
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1";

import {
  hashCreateMarketingCampaignRequest,
  hashMarketingCampaignStatusRequest,
  MARKETING_CAMPAIGN_STATUSES,
  matchMarketingCampaignDetailPath,
  matchMarketingCampaignStatusPath,
  parseMarketingCampaignQuery,
  parseMarketingCampaignStatusPayload,
  parseMarketingCampaignWritePayload,
} from "./marketing_campaigns.ts";

const CAMPAIGN_ID = "123e4567-e89b-42d3-a456-426614174888";
const OWNER_ID = "123e4567-e89b-42d3-a456-426614174889";

Deno.test("ADM-MKT-002 campaign query uses bounded pagination and channel filters", () => {
  const query = parseMarketingCampaignQuery(
    new URL(
      "https://admin.test/api/v1/marketing/campaigns?page=100&pageSize=100&status=Active&product=wellmate&channel=instagram",
    ),
  );

  assertEquals(query.page, 100);
  assertEquals(query.pageSize, 100);
  assertEquals(query.offset, 9900);
  assertEquals(query.status, "Active");
  assertEquals(query.product, "wellmate");
  assertEquals(query.channel, "instagram");
});

Deno.test("ADM-MKT-002 campaign query rejects deep pages and provider publishing states", () => {
  assertThrows(() =>
    parseMarketingCampaignQuery(
      new URL(
        "https://admin.test/api/v1/marketing/campaigns?page=101&pageSize=25",
      ),
    )
  );
  assertThrows(() =>
    parseMarketingCampaignQuery(
      new URL(
        "https://admin.test/api/v1/marketing/campaigns?status=Published",
      ),
    )
  );
});

Deno.test("ADM-MKT-002 campaign workflow keeps provider publishing outside campaign state", () => {
  assertEquals(MARKETING_CAMPAIGN_STATUSES, [
    "Draft",
    "Ready",
    "Active",
    "Paused",
    "Completed",
    "Cancelled",
  ]);
});

Deno.test("ADM-MKT-002 campaign write payload normalizes safe planning metadata", async () => {
  const payload = await parseMarketingCampaignWritePayload(
    new Request("https://admin.test/api/v1/marketing/campaigns", {
      method: "POST",
      body: JSON.stringify({
        name: "  Launch WellMate  ",
        objective: "  Early-access acquisition  ",
        productCode: "WellMate",
        channelCode: "Instagram",
        ownerAdminAccountId: OWNER_ID,
        startsAtUtc: "2026-08-20T08:00:00+03:30",
        endsAtUtc: "2026-08-25T08:00:00+03:30",
        reason: "Prepare the reviewed early access campaign.",
      }),
    }),
  );

  assertEquals(payload.name, "Launch WellMate");
  assertEquals(payload.objective, "Early-access acquisition");
  assertEquals(payload.productCode, "wellmate");
  assertEquals(payload.channelCode, "instagram");
  assertEquals(payload.ownerAdminAccountId, OWNER_ID);
  assertEquals(payload.startsAtUtc, "2026-08-20T04:30:00.000Z");
  assertEquals(payload.endsAtUtc, "2026-08-25T04:30:00.000Z");
});

Deno.test("ADM-MKT-002 campaign write rejects invalid windows and short reasons", async () => {
  await assertRejects(() =>
    parseMarketingCampaignWritePayload(
      new Request("https://admin.test/api/v1/marketing/campaigns", {
        method: "POST",
        body: JSON.stringify({
          name: "Launch",
          startsAtUtc: "2026-08-25T00:00:00Z",
          endsAtUtc: "2026-08-20T00:00:00Z",
          reason: "too short",
        }),
      }),
    )
  );
});

Deno.test("ADM-MKT-002 status payload and paths are explicit", async () => {
  assertEquals(
    matchMarketingCampaignDetailPath(
      `/api/v1/marketing/campaigns/${CAMPAIGN_ID}`,
    ),
    CAMPAIGN_ID,
  );
  assertEquals(
    matchMarketingCampaignStatusPath(
      `/api/v1/marketing/campaigns/${CAMPAIGN_ID}/actions/status`,
    ),
    CAMPAIGN_ID,
  );

  const payload = await parseMarketingCampaignStatusPayload(
    new Request(
      `https://admin.test/api/v1/marketing/campaigns/${CAMPAIGN_ID}/actions/status`,
      {
        method: "POST",
        body: JSON.stringify({
          status: "Ready",
          reason: "Human review completed for this campaign plan.",
        }),
      },
    ),
  );
  assertEquals(payload.status, "Ready");
});

Deno.test("ADM-MKT-002 idempotency hashes bind payload and target campaign", async () => {
  const payload = {
    name: "Launch",
    objective: null,
    productCode: "wellmate",
    channelCode: "instagram",
    ownerAdminAccountId: null,
    startsAtUtc: null,
    endsAtUtc: null,
    reason: "Create a reviewed marketing campaign draft.",
  };
  const createHash = await hashCreateMarketingCampaignRequest(payload);
  const statusHash = await hashMarketingCampaignStatusRequest(CAMPAIGN_ID, {
    status: "Ready",
    reason: "Human review completed for this campaign plan.",
  });

  assertEquals(createHash.length, 64);
  assertEquals(statusHash.length, 64);
  assertNotEquals(createHash, statusHash);
});
