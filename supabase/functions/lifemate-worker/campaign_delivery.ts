import {
  decryptContactPoint,
  readContactEncryptionKeySet,
} from "../_shared/contact_point_crypto.ts";
import {
  decryptMessagingToken,
  messagingTokenKeyForVersion,
  readMessagingTokenKeySet,
} from "../_shared/messaging_token_crypto.ts";
import {
  type DeliveryProviderResult,
  sendPush,
  sendSms,
} from "./campaign_delivery_provider.ts";

type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
type EnvironmentReader = (name: string) => string | null | undefined;

type ClaimedJob = {
  job_id: string;
};

type DeliveryResolution = {
  job_id: string;
  account_id: string;
  channel: "SMS" | "Push";
  provider: string;
  product_code: string;
  message_title: string | null;
  message_body: string;
  recipient_hash: string;
  recipient_ciphertext_b64: string;
  recipient_nonce_b64: string;
  recipient_key_version: number | string;
};

export type CampaignDeliveryBatchResult = {
  claimed: number;
  delivered: number;
  retryableFailed: number;
  terminalFailed: number;
  suppressedOrInvalidated: number;
};

function boundedBatch(value: string | null | undefined): number {
  const parsed = Number(value ?? "50");
  return Number.isSafeInteger(parsed) && parsed >= 1 && parsed <= 100 ? parsed : 50;
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function contactKeyForVersion(
  keys: ReturnType<typeof readContactEncryptionKeySet>,
  version: number,
) {
  if (keys.active.keyVersion === version) return keys.active;
  if (keys.previous?.keyVersion === version) return keys.previous;
  return null;
}

export async function processCampaignDeliveryBatch(
  sql: any,
  fetcher: Fetcher = fetch,
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): Promise<CampaignDeliveryBatchResult> {
  const batchSize = boundedBatch(readEnvironment("LIFEMATE_CAMPAIGN_DELIVERY_BATCH_SIZE"));
  const claimed = await sql<ClaimedJob[]>`
    select job_id::text from messaging.claim_campaign_delivery_jobs(${batchSize})
  `;
  const result: CampaignDeliveryBatchResult = {
    claimed: claimed.length,
    delivered: 0,
    retryableFailed: 0,
    terminalFailed: 0,
    suppressedOrInvalidated: 0,
  };

  for (const claim of claimed) {
    try {
      const rows = await sql<DeliveryResolution[]>`
        select
          job_id::text,account_id::text,channel,provider,product_code,message_title,message_body,
          recipient_hash,recipient_ciphertext_b64,recipient_nonce_b64,recipient_key_version
        from messaging.resolve_campaign_delivery_job(${claim.job_id}::uuid)
      `;
      const resolved = rows[0];
      if (!resolved) {
        result.suppressedOrInvalidated++;
        continue;
      }

      let providerResult: DeliveryProviderResult;
      if (resolved.channel === "SMS") {
        const version = Number(resolved.recipient_key_version);
        const keys = readContactEncryptionKeySet(readEnvironment);
        const key = contactKeyForVersion(keys, version);
        if (!key) throw new Error("recipient_key_unavailable");
        const receptor = await decryptContactPoint(
          key,
          {
            accountId: resolved.account_id,
            kind: "Phone",
            normalizedValueHash: resolved.recipient_hash,
          },
          {
            ciphertextB64: resolved.recipient_ciphertext_b64,
            nonceB64: resolved.recipient_nonce_b64,
            keyVersion: version,
          },
        );
        providerResult = await sendSms(
          { provider: resolved.provider, receptor, message: resolved.message_body },
          fetcher,
          readEnvironment,
        );
      } else {
        const version = Number(resolved.recipient_key_version);
        const keys = readMessagingTokenKeySet(readEnvironment);
        const key = messagingTokenKeyForVersion(keys, version);
        if (!key) throw new Error("recipient_key_unavailable");
        const token = await decryptMessagingToken(
          key,
          {
            accountId: resolved.account_id,
            productCode: resolved.product_code,
            provider: resolved.provider,
            tokenHash: resolved.recipient_hash,
          },
          {
            ciphertextB64: resolved.recipient_ciphertext_b64,
            nonceB64: resolved.recipient_nonce_b64,
            keyVersion: version,
          },
        );
        providerResult = await sendPush(
          {
            provider: resolved.provider,
            token,
            title: resolved.message_title,
            body: resolved.message_body,
          },
          fetcher,
          readEnvironment,
        );
      }

      if (providerResult.kind === "delivered") {
        await recordResult(
          sql,
          claim.job_id,
          "Delivered",
          resolved.provider,
          await sha256(providerResult.providerReference),
          null,
        );
        result.delivered++;
      } else if (providerResult.kind === "retryable") {
        await recordResult(sql, claim.job_id, "Failed", resolved.provider, null, providerResult.code);
        result.retryableFailed++;
      } else if (providerResult.kind === "permanent") {
        await recordResult(sql, claim.job_id, "Failed", resolved.provider, null, "provider_permanent_failure");
        result.terminalFailed++;
      } else {
        await recordResult(sql, claim.job_id, "Failed", resolved.provider, null, "provider_outcome_unknown");
        result.terminalFailed++;
      }
    } catch (error) {
      // Decryption/configuration failures happen before the provider side effect and
      // are safe to retry after configuration repair. Never include recipient,
      // token, message content or provider secret in logs/errors.
      try {
        await recordResult(sql, claim.job_id, "Failed", "internal", null, "recipient_security_unavailable");
        result.retryableFailed++;
      } catch {
        result.terminalFailed++;
      }
      console.warn("LifeMate campaign delivery failed before provider evidence", {
        errorCode: error instanceof Error && error.message === "recipient_key_unavailable"
          ? "recipient_key_unavailable"
          : "delivery_security_unavailable",
      });
    }
  }
  return result;
}

async function recordResult(
  sql: any,
  jobId: string,
  status: "Delivered" | "Failed",
  provider: string,
  providerReferenceHash: string | null,
  reasonCode: string | null,
): Promise<void> {
  await sql`
    select messaging.record_campaign_delivery_result(
      ${jobId}::uuid,${status}::varchar,${provider}::varchar,
      ${providerReferenceHash}::varchar,${reasonCode}::varchar,now()
    )
  `;
}
