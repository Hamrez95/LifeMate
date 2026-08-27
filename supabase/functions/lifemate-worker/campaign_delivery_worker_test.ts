import { assertEquals, assertMatch } from "jsr:@std/assert@1.0.14";
import {
  encryptMessagingToken,
  hashMessagingToken,
} from "../_shared/messaging_token_crypto.ts";
import {
  type CampaignDeliveryPayload,
  type CampaignDeliveryStore,
  processCampaignDeliveryBatch,
} from "./campaign_delivery_worker.ts";

const accountId = "11111111-1111-4111-8111-111111111111";
const jobId = "22222222-2222-4222-8222-222222222222";
const messagingKey = {
  secret: "messaging-token-encryption-secret-32-bytes-minimum",
  keyVersion: 7,
};
const contactKey = {
  secret: "contact-point-encryption-secret-32-bytes-minimum",
  keyVersion: 5,
};

async function pushPayload(): Promise<CampaignDeliveryPayload> {
  const token = "fcm-registration-token-with-high-entropy-123456789";
  const endpointHash = await hashMessagingToken(
    "messaging-token-hashing-secret-32-bytes-minimum",
    token,
  );
  const envelope = await encryptMessagingToken(
    messagingKey,
    { accountId, productCode: "wellmate", provider: "fcm", tokenHash: endpointHash },
    token,
    new Uint8Array(12).fill(9),
  );
  return {
    jobId,
    accountId,
    channel: "Push",
    provider: "fcm",
    productCode: "wellmate",
    messageTitle: "LifeMate",
    messageBody: "You have an update",
    endpointHash,
    endpointCiphertextB64: envelope.ciphertextB64,
    endpointNonceB64: envelope.nonceB64,
    endpointKeyVersion: envelope.keyVersion,
  };
}

function storeFor(payload: CampaignDeliveryPayload) {
  const records: Array<Record<string, unknown>> = [];
  const store: CampaignDeliveryStore = {
    claim: async () => [{ jobId, channel: "Push" }],
    resolve: async () => payload,
    record: async (input) => {
      records.push(input);
    },
  };
  return { store, records };
}

Deno.test("campaign worker preserves permanent provider rejection without retry semantics", async () => {
  const payload = await pushPayload();
  const { store, records } = storeFor(payload);
  const result = await processCampaignDeliveryBatch(
    {
      store,
      providers: {
        sms: new Map(),
        push: new Map([["fcm", {
          send: async () => ({ kind: "failed" as const, code: "fcm_http_400", retryable: false }),
        }]]),
      },
      contactKeys: { active: contactKey, previous: null },
      messagingTokenKeys: { active: messagingKey, previous: null },
      now: () => new Date("2026-08-27T10:00:00.000Z"),
    },
    10,
  );

  assertEquals(result.permanentFailed, 1);
  assertEquals(records[0]?.result, "PermanentFailed");
  assertEquals(records[0]?.reasonCode, "fcm_http_400");
});

Deno.test("campaign worker records transport ambiguity as terminal outcome unknown", async () => {
  const payload = await pushPayload();
  const { store, records } = storeFor(payload);
  const result = await processCampaignDeliveryBatch(
    {
      store,
      providers: {
        sms: new Map(),
        push: new Map([["fcm", {
          send: async () => ({ kind: "outcome_unknown" as const, code: "fcm_transport_outcome_unknown" }),
        }]]),
      },
      contactKeys: { active: contactKey, previous: null },
      messagingTokenKeys: { active: messagingKey, previous: null },
    },
    10,
  );

  assertEquals(result.outcomeUnknown, 1);
  assertEquals(records[0]?.result, "OutcomeUnknown");
});

Deno.test("campaign worker stores only a SHA-256 provider reference hash", async () => {
  const payload = await pushPayload();
  const { store, records } = storeFor(payload);
  await processCampaignDeliveryBatch(
    {
      store,
      providers: {
        sms: new Map(),
        push: new Map([["fcm", {
          send: async () => ({
            kind: "delivered" as const,
            providerReference: "projects/lifemate/messages/0:123456789",
          }),
        }]]),
      },
      contactKeys: { active: contactKey, previous: null },
      messagingTokenKeys: { active: messagingKey, previous: null },
    },
    10,
  );

  assertEquals(records[0]?.result, "Delivered");
  assertMatch(String(records[0]?.providerReferenceHash), /^[0-9a-f]{64}$/);
  assertEquals(
    String(records[0]?.providerReferenceHash).includes("projects/lifemate/messages"),
    false,
  );
});
