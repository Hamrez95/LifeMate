import { ApiError } from "./validation.ts";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const providerPattern = /^[a-z0-9][a-z0-9_.-]{1,39}$/;
const currencyPattern = /^[A-Z]{3}$/;

function text(value: unknown, field: string, max: number): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "campaign_execution_invalid",
      `${field} is invalid.`,
    );
  }
  const next = value.trim();
  if (!next || new TextEncoder().encode(next).byteLength > max) {
    throw new ApiError(
      400,
      "campaign_execution_invalid",
      `${field} is invalid.`,
    );
  }
  return next;
}

function uuid(value: unknown, field: string): string {
  const next = text(value, field, 64).toLowerCase();
  if (!uuidPattern.test(next)) {
    throw new ApiError(
      400,
      "campaign_execution_invalid",
      `${field} is invalid.`,
    );
  }
  return next;
}

function positiveVersion(value: unknown): number {
  if (!Number.isSafeInteger(value) || Number(value) < 1) {
    throw new ApiError(
      400,
      "campaign_execution_version_invalid",
      "expectedVersion is invalid.",
    );
  }
  return Number(value);
}

export function parsePrepareCampaignExecution(body: Record<string, unknown>) {
  const campaignId = uuid(body.campaignId, "campaignId");
  const audienceSnapshotId = uuid(
    body.audienceSnapshotId,
    "audienceSnapshotId",
  );
  const campaignUpdatedAtUtc = text(
    body.campaignUpdatedAtUtc,
    "campaignUpdatedAtUtc",
    64,
  );
  const date = new Date(campaignUpdatedAtUtc);
  if (Number.isNaN(date.getTime())) {
    throw new ApiError(
      400,
      "campaign_execution_invalid",
      "campaignUpdatedAtUtc is invalid.",
    );
  }
  if (
    !Array.isArray(body.channels) || body.channels.length < 1 ||
    body.channels.length > 2
  ) {
    throw new ApiError(
      400,
      "campaign_channels_invalid",
      "channels is invalid.",
    );
  }
  const channels = body.channels.map((item) => text(item, "channel", 16));
  if (
    channels.some((item) => item !== "SMS" && item !== "Push") ||
    new Set(channels).size !== channels.length
  ) {
    throw new ApiError(
      400,
      "campaign_channels_invalid",
      "channels is invalid.",
    );
  }

  let smsProvider: string | null = null;
  let smsCurrency: string | null = null;
  if (body.smsProvider != null || body.smsCurrency != null) {
    smsProvider = text(body.smsProvider, "smsProvider", 40).toLowerCase();
    smsCurrency = text(body.smsCurrency, "smsCurrency", 3).toUpperCase();
    if (
      !providerPattern.test(smsProvider) || !currencyPattern.test(smsCurrency)
    ) {
      throw new ApiError(
        400,
        "campaign_sms_pricing_invalid",
        "SMS pricing selection is invalid.",
      );
    }
    if (!channels.includes("SMS")) {
      throw new ApiError(
        400,
        "campaign_sms_pricing_invalid",
        "SMS pricing cannot be selected without the SMS channel.",
      );
    }
  }

  return {
    campaignId,
    audienceSnapshotId,
    campaignUpdatedAtUtc: date.toISOString(),
    channels,
    smsProvider,
    smsCurrency,
  };
}

export function parseExecutionTransition(
  executionId: string,
  body: Record<string, unknown>,
) {
  return {
    executionId: uuid(executionId, "executionId"),
    expectedVersion: positiveVersion(body.expectedVersion),
  };
}

export function parseScheduleExecution(
  executionId: string,
  body: Record<string, unknown>,
) {
  const common = parseExecutionTransition(executionId, body);
  const raw = text(body.scheduledAtUtc, "scheduledAtUtc", 64);
  const scheduled = new Date(raw);
  if (Number.isNaN(scheduled.getTime())) {
    throw new ApiError(
      400,
      "campaign_schedule_invalid",
      "scheduledAtUtc is invalid.",
    );
  }
  return { ...common, scheduledAtUtc: scheduled.toISOString() };
}

export function parseCancelExecution(
  executionId: string,
  body: Record<string, unknown>,
) {
  const common = parseExecutionTransition(executionId, body);
  const reason = text(body.reason, "reason", 1000);
  if (reason.length < 10) {
    throw new ApiError(
      400,
      "campaign_cancel_reason_invalid",
      "reason is too short.",
    );
  }
  return { ...common, reason };
}

export function matchCampaignExecutionAction(path: string): {
  executionId: string;
  action: "confirm" | "schedule" | "cancel";
} | null {
  const match = path.match(
    /^\/api\/v1\/marketing\/campaign-executions\/([0-9a-f-]{36})\/(confirm|schedule|cancel)$/i,
  );
  if (!match || !uuidPattern.test(match[1])) return null;
  return {
    executionId: match[1].toLowerCase(),
    action: match[2].toLowerCase() as "confirm" | "schedule" | "cancel",
  };
}
