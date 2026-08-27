import { readContactEncryptionKeySet } from "../_shared/contact_point_crypto.ts";
import { readMessagingTokenKeySet } from "../_shared/messaging_token_crypto.ts";
import {
  FcmHttpV1PushProvider,
  KavenegarCampaignSmsProvider,
} from "./campaign_delivery_provider.ts";
import {
  type CampaignDeliveryPayload,
  type CampaignDeliveryStore,
  processCampaignDeliveryBatch,
} from "./campaign_delivery_worker.ts";

type EnvironmentReader = (name: string) => string | null | undefined;

type SqlLike = any;

export function campaignDeliveryEnabled(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): boolean {
  const raw = (readEnvironment("LIFEMATE_CAMPAIGN_DELIVERY_ENABLED") ?? "false")
    .trim()
    .toLowerCase();
  if (raw === "true") return true;
  if (raw === "false" || raw === "") return false;
  throw new Error("LIFEMATE_CAMPAIGN_DELIVERY_ENABLED must be true or false.");
}

export function createCampaignDeliveryRuntime(
  sql: SqlLike,
  options: {
    readEnvironment?: EnvironmentReader;
    fetcher?: typeof fetch;
    now?: () => Date;
  } = {},
) {
  const readEnvironment = options.readEnvironment ?? ((name: string) => Deno.env.get(name));
  if (!campaignDeliveryEnabled(readEnvironment)) return null;

  const contactKeys = readContactEncryptionKeySet(readEnvironment);
  const messagingTokenKeys = readMessagingTokenKeySet(readEnvironment);
  const providers = providerRegistry(readEnvironment, options.fetcher);
  if (providers.sms.size === 0 && providers.push.size === 0) {
    throw new Error("Campaign delivery is enabled but no provider is configured.");
  }
  const store = createCampaignDeliveryStore(sql);

  return {
    run: (limit: number) =>
      processCampaignDeliveryBatch(
        {
          store,
          providers,
          contactKeys,
          messagingTokenKeys,
          now: options.now,
        },
        limit,
      ),
  };
}

function providerRegistry(
  readEnvironment: EnvironmentReader,
  fetcher?: typeof fetch,
) {
  const sms = new Map();
  const push = new Map();

  const kavenegarApiKey = readEnvironment("KAVENEGAR_API_KEY") ?? "";
  const kavenegarSender = readEnvironment("LIFEMATE_CAMPAIGN_KAVENEGAR_SENDER") ?? "";
  if ((kavenegarApiKey.length > 0) !== (kavenegarSender.length > 0)) {
    throw new Error("Kavenegar campaign API key and sender must be configured together.");
  }
  if (kavenegarApiKey && kavenegarSender) {
    sms.set(
      "kavenegar",
      new KavenegarCampaignSmsProvider(kavenegarApiKey, kavenegarSender, {
        fetcher,
      }),
    );
  }

  // FCM OAuth access tokens are intentionally supplied through protected runtime
  // configuration. Production activation must provide a rotation/refresh owner;
  // this source never embeds a service-account private key.
  const fcmProjectId = readEnvironment("LIFEMATE_CAMPAIGN_FCM_PROJECT_ID") ?? "";
  const fcmAccessToken = readEnvironment("LIFEMATE_CAMPAIGN_FCM_ACCESS_TOKEN") ?? "";
  if ((fcmProjectId.length > 0) !== (fcmAccessToken.length > 0)) {
    throw new Error("FCM campaign project and access token must be configured together.");
  }
  if (fcmProjectId && fcmAccessToken) {
    push.set(
      "fcm",
      new FcmHttpV1PushProvider(fcmProjectId, fcmAccessToken, { fetcher }),
    );
  }

  return { sms, push };
}

export function createCampaignDeliveryStore(sql: SqlLike): CampaignDeliveryStore {
  return {
    async claim(limit) {
      const rows = await sql`
        select * from messaging.claim_campaign_delivery_jobs(${limit})
      `;
      return rows.map((row: Record<string, unknown>) => ({
        jobId: requiredUuid(row.job_id, "campaign_delivery_job_invalid"),
        channel: requiredChannel(row.channel),
      }));
    },

    async resolve(jobId) {
      const rows = await sql`
        select * from messaging.resolve_campaign_delivery_job(${jobId}::uuid)
      `;
      if (!rows[0]) return null;
      return payload(rows[0]);
    },

    async record(input) {
      const rows = await sql`
        select messaging.record_campaign_delivery_result_v2(
          ${input.jobId}::uuid,
          ${input.result}::varchar,
          ${input.provider}::varchar,
          ${input.providerReferenceHash}::varchar,
          ${input.reasonCode}::varchar,
          ${input.occurredAtUtc}::timestamptz
        ) as result
      `;
      if (!rows[0]?.result) throw new Error("campaign_delivery_result_not_recorded");
    },
  };
}

function payload(row: Record<string, unknown>): CampaignDeliveryPayload {
  const title = row.message_title;
  return {
    jobId: requiredUuid(row.job_id, "campaign_delivery_job_invalid"),
    accountId: requiredUuid(row.account_id, "campaign_delivery_account_invalid"),
    channel: requiredChannel(row.channel),
    provider: boundedCode(row.provider, "campaign_delivery_provider_invalid", 40),
    productCode: boundedCode(row.product_code, "campaign_delivery_product_invalid", 64),
    messageTitle: title == null ? null : boundedText(title, "campaign_delivery_title_invalid", 160),
    messageBody: boundedText(row.message_body, "campaign_delivery_body_invalid", 2000),
    endpointHash: hexHash(row.endpoint_hash),
    endpointCiphertextB64: boundedText(
      row.endpoint_ciphertext_b64,
      "campaign_delivery_endpoint_invalid",
      12000,
    ),
    endpointNonceB64: boundedText(
      row.endpoint_nonce_b64,
      "campaign_delivery_endpoint_invalid",
      64,
    ),
    endpointKeyVersion: keyVersion(row.endpoint_key_version),
  };
}

function requiredUuid(value: unknown, code: string): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
  ) throw new Error(code);
  return value.toLowerCase();
}

function requiredChannel(value: unknown): "SMS" | "Push" {
  if (value !== "SMS" && value !== "Push") throw new Error("campaign_delivery_channel_invalid");
  return value;
}

function boundedCode(value: unknown, code: string, max: number): string {
  if (typeof value !== "string" || value.length < 2 || value.length > max ||
      !/^[a-z0-9][a-z0-9_.:-]*$/.test(value)) throw new Error(code);
  return value;
}

function boundedText(value: unknown, code: string, max: number): string {
  if (typeof value !== "string") throw new Error(code);
  const normalized = value.trim();
  if (!normalized || new TextEncoder().encode(normalized).byteLength > max) throw new Error(code);
  return normalized;
}

function hexHash(value: unknown): string {
  if (typeof value !== "string" || !/^[0-9a-f]{64}$/i.test(value)) {
    throw new Error("campaign_delivery_endpoint_hash_invalid");
  }
  return value.toLowerCase();
}

function keyVersion(value: unknown): number {
  const result = Number(value);
  if (!Number.isSafeInteger(result) || result < 1 || result > 32767) {
    throw new Error("campaign_delivery_key_version_invalid");
  }
  return result;
}
