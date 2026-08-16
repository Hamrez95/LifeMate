import { ApiError, requireUuid } from "./validation.ts";

export type CampaignApprovalState = "Pending" | "Approved" | "Revoked";
export type CampaignPublishStatus =
  | "Scheduled"
  | "Queued"
  | "Processing"
  | "Published"
  | "Failed"
  | "OutcomeUnknown"
  | "Cancelled";

export type CampaignContentPayload = {
  brief: string | null;
  audienceSummary: string | null;
  publishText: string | null;
  assetRefs: string[];
  reason: string;
};

export type CampaignApprovalPayload = {
  approved: boolean;
  reason: string;
};

export type CampaignPublishPayload = { reason: string };

const DETAIL_PATH = /^\/api\/v1\/marketing\/campaigns\/([^/]+)$/i;
const CONTENT_PATH = /^\/api\/v1\/marketing\/campaigns\/([^/]+)\/content$/i;
const APPROVAL_PATH =
  /^\/api\/v1\/marketing\/campaigns\/([^/]+)\/actions\/approval$/i;
const PUBLISH_PATH =
  /^\/api\/v1\/marketing\/campaigns\/([^/]+)\/actions\/publish$/i;

function match(path: string, pattern: RegExp): string | null {
  const value = pattern.exec(path)?.[1];
  return value ? requireUuid(value, "campaignId") : null;
}

export function matchMarketingCampaignReadPath(path: string): string | null {
  return match(path, DETAIL_PATH);
}

export function matchMarketingCampaignContentPath(path: string): string | null {
  return match(path, CONTENT_PATH);
}

export function matchMarketingCampaignApprovalPath(
  path: string,
): string | null {
  return match(path, APPROVAL_PATH);
}

export function matchMarketingCampaignPublishPath(path: string): string | null {
  return match(path, PUBLISH_PATH);
}

async function objectBody(request: Request): Promise<Record<string, unknown>> {
  try {
    const body = await request.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new Error("invalid");
    }
    return body as Record<string, unknown>;
  } catch {
    throw new ApiError(
      400,
      "invalid_request",
      "Request body must be a valid JSON object.",
    );
  }
}

function optionalText(
  value: unknown,
  max: number,
  code: string,
): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string") {
    throw new ApiError(400, code, "Text field is invalid.");
  }
  const normalized = value.trim();
  if (!normalized || normalized.length > max) {
    throw new ApiError(400, code, "Text field is invalid.");
  }
  return normalized;
}

function reason(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "marketing_campaign_reason_invalid",
      "Reason is invalid.",
    );
  }
  const normalized = value.trim();
  if (normalized.length < 10 || normalized.length > 1000) {
    throw new ApiError(
      400,
      "marketing_campaign_reason_invalid",
      "A reason between 10 and 1000 characters is required.",
    );
  }
  return normalized;
}

export async function parseCampaignContentPayload(
  request: Request,
): Promise<CampaignContentPayload> {
  const body = await objectBody(request);
  if (body.assetRefs != null && !Array.isArray(body.assetRefs)) {
    throw new ApiError(
      400,
      "marketing_campaign_assets_invalid",
      "Asset references must be an array.",
    );
  }
  const assetRefs = (body.assetRefs ?? []) as unknown[];
  if (
    assetRefs.length > 20 ||
    assetRefs.some((item) =>
      typeof item !== "string" || item.trim().length < 1 ||
      item.trim().length > 500
    )
  ) {
    throw new ApiError(
      400,
      "marketing_campaign_assets_invalid",
      "Asset references are invalid.",
    );
  }
  return {
    brief: optionalText(body.brief, 4000, "marketing_campaign_brief_invalid"),
    audienceSummary: optionalText(
      body.audienceSummary,
      2000,
      "marketing_campaign_audience_invalid",
    ),
    publishText: optionalText(
      body.publishText,
      4096,
      "marketing_campaign_publish_text_invalid",
    ),
    assetRefs: assetRefs.map((item) => (item as string).trim()),
    reason: reason(body.reason),
  };
}

export async function parseCampaignApprovalPayload(
  request: Request,
): Promise<CampaignApprovalPayload> {
  const body = await objectBody(request);
  if (typeof body.approved !== "boolean") {
    throw new ApiError(
      400,
      "marketing_campaign_approval_invalid",
      "Approval state is invalid.",
    );
  }
  return { approved: body.approved, reason: reason(body.reason) };
}

export async function parseCampaignPublishPayload(
  request: Request,
): Promise<CampaignPublishPayload> {
  const body = await objectBody(request);
  return { reason: reason(body.reason) };
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export function hashCampaignContentRequest(
  campaignId: string,
  payload: CampaignContentPayload,
): Promise<string> {
  return sha256(`v1\ncontent\n${campaignId}\n${JSON.stringify(payload)}`);
}

export function hashCampaignApprovalRequest(
  campaignId: string,
  payload: CampaignApprovalPayload,
): Promise<string> {
  return sha256(
    `v1\napproval\n${campaignId}\n${payload.approved}\n${payload.reason}`,
  );
}

export function hashCampaignPublishRequest(
  campaignId: string,
  payload: CampaignPublishPayload,
): Promise<string> {
  return sha256(`v1\npublish\n${campaignId}\n${payload.reason}`);
}
