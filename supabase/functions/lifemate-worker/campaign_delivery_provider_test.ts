import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  FcmHttpV1PushProvider,
  KavenegarCampaignSmsProvider,
} from "./campaign_delivery_provider.ts";

Deno.test("Kavenegar campaign provider returns durable provider reference", async () => {
  let requestBody = "";
  const provider = new KavenegarCampaignSmsProvider(
    "12345678abcdef",
    "10004346",
    {
      fetcher: async (_input, init) => {
        requestBody = String(init?.body ?? "");
        return new Response(JSON.stringify({
          return: { status: 200 },
          entries: [{ messageid: 123456789 }],
        }), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      },
    },
  );

  const result = await provider.send({
    phoneE164: "+989121234567",
    message: "LifeMate test campaign",
  });

  assertEquals(result, { kind: "delivered", providerReference: "123456789" });
  assertStringIncludes(requestBody, "receptor=09121234567");
  assertStringIncludes(requestBody, "sender=10004346");
});

Deno.test("Kavenegar transport ambiguity never fabricates delivery", async () => {
  const provider = new KavenegarCampaignSmsProvider(
    "12345678abcdef",
    "10004346",
    {
      fetcher: () => Promise.reject(new Error("network interrupted")),
    },
  );

  assertEquals(
    await provider.send({
      phoneE164: "+989121234567",
      message: "LifeMate test campaign",
    }),
    { kind: "outcome_unknown", code: "kavenegar_transport_outcome_unknown" },
  );
});

Deno.test("Kavenegar provider rejection is bounded and retry-aware", async () => {
  const provider = new KavenegarCampaignSmsProvider(
    "12345678abcdef",
    "10004346",
    {
      fetcher: async () => new Response(JSON.stringify({ return: { status: 409 } }), {
        status: 429,
        headers: { "content-type": "application/json" },
      }),
    },
  );

  assertEquals(
    await provider.send({
      phoneE164: "+989121234567",
      message: "LifeMate test campaign",
    }),
    { kind: "failed", code: "kavenegar_409", retryable: true },
  );
});

Deno.test("FCM HTTP v1 provider returns canonical message reference", async () => {
  let authorization = "";
  const provider = new FcmHttpV1PushProvider(
    "lifemate-prod",
    "oauth-access-token-with-enough-entropy",
    {
      fetcher: async (_input, init) => {
        authorization = new Headers(init?.headers).get("authorization") ?? "";
        return new Response(JSON.stringify({
          name: "projects/lifemate-prod/messages/0:123456789",
        }), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      },
    },
  );

  const result = await provider.send({
    token: "fcm-token-high-entropy-abcdefghijklmnopqrstuvwxyz0123456789",
    title: "LifeMate",
    body: "You have an update",
  });

  assertEquals(result, {
    kind: "delivered",
    providerReference: "projects/lifemate-prod/messages/0:123456789",
  });
  assertEquals(authorization, "Bearer oauth-access-token-with-enough-entropy");
});

Deno.test("FCM rejection never includes provider response payload", async () => {
  const provider = new FcmHttpV1PushProvider(
    "lifemate-prod",
    "oauth-access-token-with-enough-entropy",
    {
      fetcher: async () => new Response(JSON.stringify({
        error: { message: "sensitive provider diagnostic" },
      }), {
        status: 503,
        headers: { "content-type": "application/json" },
      }),
    },
  );

  assertEquals(
    await provider.send({
      token: "fcm-token-high-entropy-abcdefghijklmnopqrstuvwxyz0123456789",
      body: "You have an update",
    }),
    { kind: "failed", code: "fcm_http_503", retryable: true },
  );
});
