import { assertEquals, assertNotEquals, assertRejects } from "jsr:@std/assert@1";
import {
  hashCampaignApprovalRequest,
  hashCampaignContentRequest,
  hashCampaignPublishRequest,
  matchMarketingCampaignApprovalPath,
  matchMarketingCampaignContentPath,
  matchMarketingCampaignPublishPath,
  matchMarketingCampaignReadPath,
  parseCampaignApprovalPayload,
  parseCampaignContentPayload,
  parseCampaignPublishPayload,
} from "./marketing_campaign_detail.ts";

const CAMPAIGN_ID = "123e4567-e89b-42d3-a456-426614174888";

Deno.test("ADM-MKT-003 campaign detail routes are explicit", () => {
  assertEquals(matchMarketingCampaignReadPath(`/api/v1/marketing/campaigns/${CAMPAIGN_ID}`), CAMPAIGN_ID);
  assertEquals(matchMarketingCampaignContentPath(`/api/v1/marketing/campaigns/${CAMPAIGN_ID}/content`), CAMPAIGN_ID);
  assertEquals(matchMarketingCampaignApprovalPath(`/api/v1/marketing/campaigns/${CAMPAIGN_ID}/actions/approval`), CAMPAIGN_ID);
  assertEquals(matchMarketingCampaignPublishPath(`/api/v1/marketing/campaigns/${CAMPAIGN_ID}/actions/publish`), CAMPAIGN_ID);
});

Deno.test("ADM-MKT-003 content payload is bounded and normalized", async () => {
  const payload = await parseCampaignContentPayload(new Request("https://admin.test", {
    method: "PUT",
    body: JSON.stringify({
      brief: "  Launch brief  ",
      audienceSummary: "  Early access audience  ",
      publishText: "  LifeMate is live  ",
      assetRefs: [" asset:hero "],
      reason: "Prepare the human-reviewed campaign content.",
    }),
  }));
  assertEquals(payload.brief, "Launch brief");
  assertEquals(payload.publishText, "LifeMate is live");
  assertEquals(payload.assetRefs, ["asset:hero"]);
});

Deno.test("ADM-MKT-003 content payload rejects unsafe asset lists", async () => {
  await assertRejects(() => parseCampaignContentPayload(new Request("https://admin.test", {
    method: "PUT",
    body: JSON.stringify({
      publishText: "content",
      assetRefs: Array.from({ length: 21 }, (_, index) => `asset:${index}`),
      reason: "This reason is sufficiently long for validation.",
    }),
  })));
});

Deno.test("ADM-MKT-003 approval and publish require explicit human reasons", async () => {
  const approval = await parseCampaignApprovalPayload(new Request("https://admin.test", {
    method: "POST",
    body: JSON.stringify({ approved: true, reason: "Human reviewer approved this exact content revision." }),
  }));
  assertEquals(approval.approved, true);

  const publish = await parseCampaignPublishPayload(new Request("https://admin.test", {
    method: "POST",
    body: JSON.stringify({ reason: "Publish the approved revision to the configured channel." }),
  }));
  assertEquals(publish.reason.startsWith("Publish"), true);
});

Deno.test("ADM-MKT-003 idempotency hashes bind action, target and payload", async () => {
  const content = { brief: null, audienceSummary: null, publishText: "LifeMate", assetRefs: [], reason: "Prepare approved content for publishing." };
  const contentHash = await hashCampaignContentRequest(CAMPAIGN_ID, content);
  const approvalHash = await hashCampaignApprovalRequest(CAMPAIGN_ID, { approved: true, reason: "Approve the current campaign content revision." });
  const publishHash = await hashCampaignPublishRequest(CAMPAIGN_ID, { reason: "Publish the approved revision after human confirmation." });
  assertEquals(contentHash.length, 64);
  assertEquals(approvalHash.length, 64);
  assertEquals(publishHash.length, 64);
  assertNotEquals(contentHash, approvalHash);
  assertNotEquals(approvalHash, publishHash);
});
