import {
  matchCampaignExecutionAction,
  parseCancelExecution,
  parsePrepareCampaignExecution,
  parseScheduleExecution,
} from "./campaign_orchestrator.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

function expectCode(run: () => unknown, code: string): void {
  try {
    run();
  } catch (error) {
    assert(
      typeof error === "object" && error !== null && "code" in error &&
        (error as { code?: string }).code === code,
      `Expected ${code}.`,
    );
    return;
  }
  throw new Error(`Expected ${code}.`);
}

const executionId = "123e4567-e89b-42d3-a456-426614174000";
const campaignId = "123e4567-e89b-42d3-a456-426614174001";
const snapshotId = "123e4567-e89b-42d3-a456-426614174002";

Deno.test("campaign orchestrator is wired through canonical marketing dispatcher", async () => {
  const routes = await Deno.readTextFile(
    new URL("./marketing_campaigns_routes.ts", import.meta.url),
  );
  assert(
    routes.includes("createCampaignOrchestratorRouteHandler"),
    "canonical marketing dispatcher must construct campaign orchestrator",
  );
  assert(
    routes.includes("campaignOrchestratorRouteHandler(context)"),
    "canonical marketing dispatcher must forward authenticated context",
  );
});

Deno.test("campaign preparation is product-scoped and persists only after validation", async () => {
  const migration = await Deno.readTextFile(
    new URL(
      "../../migrations/20260827043100_campaign_orchestrator_bounded_prepare.sql",
      import.meta.url,
    ),
  );
  assert(
    migration.includes("pr.product_code=v_campaign.product_code"),
    "push reachability must use the campaign product",
  );
  const costCheck = migration.indexOf("campaign_cost_overflow");
  const executionInsert = migration.indexOf(
    "insert into messaging.campaign_executions",
  );
  assert(costCheck >= 0, "bounded cost check must exist");
  assert(
    executionInsert > costCheck,
    "execution/jobs must not persist before controlled cost validation",
  );
});

Deno.test("campaign prepare normalizes channels and optional SMS pricing", () => {
  const payload = parsePrepareCampaignExecution({
    campaignId,
    audienceSnapshotId: snapshotId,
    campaignUpdatedAtUtc: "2026-08-27T04:00:00Z",
    channels: ["SMS", "Push"],
    smsProvider: "Kavenegar",
    smsCurrency: "irr",
  });
  assert(payload.campaignId === campaignId, "campaign id must survive");
  assert(payload.channels.length === 2, "both channels must survive");
  assert(payload.smsProvider === "kavenegar", "provider must normalize");
  assert(payload.smsCurrency === "IRR", "currency must normalize");
});

Deno.test("campaign prepare rejects duplicate/unknown channels", () => {
  expectCode(
    () =>
      parsePrepareCampaignExecution({
        campaignId,
        audienceSnapshotId: snapshotId,
        campaignUpdatedAtUtc: "2026-08-27T04:00:00Z",
        channels: ["SMS", "SMS"],
      }),
    "campaign_channels_invalid",
  );
  expectCode(
    () =>
      parsePrepareCampaignExecution({
        campaignId,
        audienceSnapshotId: snapshotId,
        campaignUpdatedAtUtc: "2026-08-27T04:00:00Z",
        channels: ["Email"],
      }),
    "campaign_channels_invalid",
  );
});

Deno.test("SMS pricing cannot be selected for push-only execution", () => {
  expectCode(
    () =>
      parsePrepareCampaignExecution({
        campaignId,
        audienceSnapshotId: snapshotId,
        campaignUpdatedAtUtc: "2026-08-27T04:00:00Z",
        channels: ["Push"],
        smsProvider: "kavenegar",
        smsCurrency: "IRR",
      }),
    "campaign_sms_pricing_invalid",
  );
});

Deno.test("campaign schedule requires positive version and timestamp", () => {
  const payload = parseScheduleExecution(executionId, {
    expectedVersion: 2,
    scheduledAtUtc: "2026-08-28T08:30:00+03:30",
  });
  assert(payload.expectedVersion === 2, "version must survive");
  assert(payload.scheduledAtUtc.endsWith("Z"), "timestamp must canonicalize");
  expectCode(
    () =>
      parseScheduleExecution(executionId, {
        expectedVersion: 0,
        scheduledAtUtc: "2026-08-28T08:30:00Z",
      }),
    "campaign_execution_version_invalid",
  );
});

Deno.test("campaign cancellation reason and route action are bounded", () => {
  const payload = parseCancelExecution(executionId, {
    expectedVersion: 1,
    reason: "Campaign cancelled after review.",
  });
  assert(payload.reason.startsWith("Campaign"), "reason must survive");
  const action = matchCampaignExecutionAction(
    `/api/v1/marketing/campaign-executions/${executionId}/confirm`,
  );
  assert(action?.action === "confirm", "confirm path must match");
  expectCode(
    () =>
      parseCancelExecution(executionId, {
        expectedVersion: 1,
        reason: "short",
      }),
    "campaign_cancel_reason_invalid",
  );
});
