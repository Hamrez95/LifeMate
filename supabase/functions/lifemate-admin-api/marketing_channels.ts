import { ApiError } from "./validation.ts";

export const MARKETING_CHANNEL_SETUP_STATUSES = [
  "SetupRequired",
  "CredentialAvailable",
  "Disabled",
] as const;
export type MarketingChannelSetupStatus =
  (typeof MARKETING_CHANNEL_SETUP_STATUSES)[number];

export type MarketingChannelOperatorStatus = "Enabled" | "Disabled";

export type MarketingChannelItem = {
  providerCode: string;
  displayName: string;
  operatorStatus: MarketingChannelOperatorStatus;
  setupStatus: MarketingChannelSetupStatus;
  credentialAvailable: boolean;
  providerConnectivity: "NotVerified";
  updatedAtUtc: string;
};

export type MarketingChannelStatusPayload = {
  enabled: boolean;
  reason: string;
};

const PROVIDER_PATTERN = /^[a-z0-9][a-z0-9_.:-]{0,63}$/;
const STATUS_PATH =
  /^\/api\/v1\/marketing\/channels\/([^/]+)\/actions\/status$/i;

function requiredReason(value: unknown): string {
  if (typeof value !== "string") {
    throw new ApiError(
      400,
      "marketing_channel_reason_invalid",
      "Channel status reason is invalid.",
    );
  }
  const normalized = value.trim();
  if (normalized.length < 10 || normalized.length > 1000) {
    throw new ApiError(
      400,
      "marketing_channel_reason_invalid",
      "Channel status reason is invalid.",
    );
  }
  return normalized;
}

async function requestObject(
  request: Request,
): Promise<Record<string, unknown>> {
  try {
    const value = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("invalid");
    }
    return value as Record<string, unknown>;
  } catch {
    throw new ApiError(
      400,
      "invalid_request",
      "Request body must be a valid JSON object.",
    );
  }
}

export function matchMarketingChannelStatusPath(path: string): string | null {
  const match = STATUS_PATH.exec(path);
  if (!match) return null;
  const provider = match[1].trim().toLowerCase();
  if (!PROVIDER_PATTERN.test(provider)) {
    throw new ApiError(
      400,
      "marketing_channel_invalid",
      "Channel provider is invalid.",
    );
  }
  return provider;
}

export async function parseMarketingChannelStatusPayload(
  request: Request,
): Promise<MarketingChannelStatusPayload> {
  const body = await requestObject(request);
  if (typeof body.enabled !== "boolean") {
    throw new ApiError(
      400,
      "marketing_channel_status_invalid",
      "Channel enabled state is invalid.",
    );
  }
  return {
    enabled: body.enabled,
    reason: requiredReason(body.reason),
  };
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function hashMarketingChannelStatusRequest(
  providerCode: string,
  payload: MarketingChannelStatusPayload,
): Promise<string> {
  return sha256(
    `v1\nchannel-status\n${providerCode}\n${payload.enabled}\n${payload.reason}`,
  );
}
