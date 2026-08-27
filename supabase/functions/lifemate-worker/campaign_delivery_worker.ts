import {
  decryptContactPoint,
  type ContactEncryptionKeySet,
} from "../_shared/contact_point_crypto.ts";
import {
  decryptMessagingToken,
  type MessagingTokenKeySet,
} from "../_shared/messaging_token_crypto.ts";
import type {
  CampaignProviderResult,
  PushCampaignDelivery,
  PushCampaignProvider,
  SmsCampaignDelivery,
  SmsCampaignProvider,
} from "./campaign_delivery_provider.ts";

export type CampaignDeliveryClaim = {
  jobId: string;
  channel: "SMS" | "Push";
};

export type CampaignDeliveryPayload = {
  jobId: string;
  accountId: string;
  channel: "SMS" | "Push";
  provider: string;
  productCode: string;
  messageTitle: string | null;
  messageBody: string;
  endpointHash: string;
  endpointCiphertextB64: string;
  endpointNonceB64: string;
  endpointKeyVersion: number;
};

export type CampaignDeliveryRecordedResult =
  | "Delivered"
  | "Failed"
  | "PermanentFailed"
  | "OutcomeUnknown";

export interface CampaignDeliveryStore {
  claim(limit: number): Promise<CampaignDeliveryClaim[]>;
  resolve(jobId: string): Promise<CampaignDeliveryPayload | null>;
  record(input: {
    jobId: string;
    result: CampaignDeliveryRecordedResult;
    provider: string;
    providerReferenceHash: string | null;
    reasonCode: string | null;
    occurredAtUtc: string;
  }): Promise<void>;
}

export type CampaignDeliveryProviders = {
  sms: ReadonlyMap<string, SmsCampaignProvider>;
  push: ReadonlyMap<string, PushCampaignProvider>;
};

type EngineOptions = {
  store: CampaignDeliveryStore;
  providers: CampaignDeliveryProviders;
  contactKeys: ContactEncryptionKeySet;
  messagingTokenKeys: MessagingTokenKeySet;
  now?: () => Date;
};

type PreparedDelivery =
  | { kind: "sms"; provider: SmsCampaignProvider; input: SmsCampaignDelivery }
  | { kind: "push"; provider: PushCampaignProvider; input: PushCampaignDelivery };

export async function processCampaignDeliveryBatch(
  options: EngineOptions,
  limit: number,
): Promise<{
  claimed: number;
  delivered: number;
  failed: number;
  permanentFailed: number;
  outcomeUnknown: number;
}> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 200) {
    throw new Error("campaign_delivery_batch_limit_invalid");
  }
  const claims = await options.store.claim(limit);
  let delivered = 0;
  let failed = 0;
  let permanentFailed = 0;
  let outcomeUnknown = 0;

  for (const claim of claims) {
    const occurredAtUtc = (options.now ?? (() => new Date()))().toISOString();
    let payload: CampaignDeliveryPayload;
    let prepared: PreparedDelivery;

    try {
      const resolved = await options.store.resolve(claim.jobId);
      // The database send-time boundary may terminally suppress/cancel a claimed
      // job after a late marketing opt-out, inactive account or endpoint loss.
      // Null therefore means "do not contact this recipient" and must never be
      // converted back into a retryable failure or provider call.
      if (!resolved) continue;
      if (resolved.channel !== claim.channel) {
        throw new Error("campaign_delivery_channel_mismatch");
      }
      payload = resolved;
      prepared = await prepareDelivery(payload, options);
    } catch (error) {
      // No provider call has occurred yet, so bounded retry is safe.
      await options.store.record({
        jobId: claim.jobId,
        result: "Failed",
        provider: "unavailable",
        providerReferenceHash: null,
        reasonCode: safeReason(error),
        occurredAtUtc,
      });
      failed++;
      continue;
    }

    let providerResult: CampaignProviderResult;
    try {
      providerResult = prepared.kind === "sms"
        ? await prepared.provider.send(prepared.input)
        : await prepared.provider.send(prepared.input);
    } catch {
      // An unexpected provider exception may occur after the external endpoint
      // accepted the request. Treat it as outcome-unknown rather than retrying.
      providerResult = {
        kind: "outcome_unknown",
        code: "campaign_provider_unexpected_outcome_unknown",
      };
    }

    const recorded = await toRecordedResult(
      payload.jobId,
      payload.provider,
      providerResult,
      occurredAtUtc,
    );

    // Do not wrap this write in the pre-provider catch above. If persistence
    // fails after an external side effect, the job intentionally remains
    // InFlight and is not automatically reclaimed/sent again.
    await options.store.record(recorded);

    if (recorded.result === "Delivered") delivered++;
    else if (recorded.result === "OutcomeUnknown") outcomeUnknown++;
    else if (recorded.result === "PermanentFailed") permanentFailed++;
    else failed++;
  }

  return {
    claimed: claims.length,
    delivered,
    failed,
    permanentFailed,
    outcomeUnknown,
  };
}

async function prepareDelivery(
  payload: CampaignDeliveryPayload,
  options: EngineOptions,
): Promise<PreparedDelivery> {
  if (payload.channel === "SMS") {
    const provider = options.providers.sms.get(payload.provider);
    if (!provider) throw new Error("campaign_sms_provider_not_configured");
    const key = keyForVersion(options.contactKeys, payload.endpointKeyVersion);
    if (!key) throw new Error("campaign_contact_key_unavailable");
    const phoneE164 = await decryptContactPoint(
      key,
      {
        accountId: payload.accountId,
        kind: "Phone",
        normalizedValueHash: payload.endpointHash,
      },
      {
        ciphertextB64: payload.endpointCiphertextB64,
        nonceB64: payload.endpointNonceB64,
        keyVersion: payload.endpointKeyVersion,
      },
    );
    return {
      kind: "sms",
      provider,
      input: { phoneE164, message: payload.messageBody },
    };
  }

  const provider = options.providers.push.get(payload.provider);
  if (!provider) throw new Error("campaign_push_provider_not_configured");
  const key = keyForVersion(options.messagingTokenKeys, payload.endpointKeyVersion);
  if (!key) throw new Error("campaign_messaging_token_key_unavailable");
  const token = await decryptMessagingToken(
    key,
    {
      accountId: payload.accountId,
      productCode: payload.productCode,
      provider: payload.provider,
      tokenHash: payload.endpointHash,
    },
    {
      ciphertextB64: payload.endpointCiphertextB64,
      nonceB64: payload.endpointNonceB64,
      keyVersion: payload.endpointKeyVersion,
    },
  );
  return {
    kind: "push",
    provider,
    input: {
      token,
      title: payload.messageTitle,
      body: payload.messageBody,
    },
  };
}

function keyForVersion<T extends { keyVersion: number }>(
  keys: { active: T; previous: T | null },
  version: number,
): T | null {
  if (keys.active.keyVersion === version) return keys.active;
  if (keys.previous?.keyVersion === version) return keys.previous;
  return null;
}

async function toRecordedResult(
  jobId: string,
  provider: string,
  result: CampaignProviderResult,
  occurredAtUtc: string,
) {
  if (result.kind === "delivered") {
    return {
      jobId,
      result: "Delivered" as const,
      provider,
      providerReferenceHash: await sha256Hex(result.providerReference),
      reasonCode: null,
      occurredAtUtc,
    };
  }
  if (result.kind === "outcome_unknown") {
    return {
      jobId,
      result: "OutcomeUnknown" as const,
      provider,
      providerReferenceHash: null,
      reasonCode: boundedReason(result.code),
      occurredAtUtc,
    };
  }
  return {
    jobId,
    result: result.retryable ? "Failed" as const : "PermanentFailed" as const,
    provider,
    providerReferenceHash: null,
    reasonCode: boundedReason(result.code),
    occurredAtUtc,
  };
}

async function sha256Hex(value: string): Promise<string> {
  const normalized = value.trim();
  if (!normalized || normalized.length > 512) {
    throw new Error("campaign_provider_reference_invalid");
  }
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(normalized),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

function safeReason(error: unknown): string {
  const raw = error instanceof Error ? error.message : "campaign_delivery_failed";
  return boundedReason(raw.replace(/[^a-zA-Z0-9_.-]/g, "_").toLowerCase());
}

function boundedReason(value: string): string {
  const normalized = value.trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9_.-]{1,79}$/.test(normalized)) {
    return "campaign_delivery_failed";
  }
  return normalized;
}
