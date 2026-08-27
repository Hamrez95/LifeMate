import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  resetCampaignProviderCacheForTest,
  sendPush,
  sendSms,
} from "./campaign_delivery_provider.ts";

Deno.test("Kavenegar adapter sends bounded form payload without logging secret fields", async () => {
  let requestedUrl = "";
  let requestedBody = "";
  const result = await sendSms(
    { provider: "kavenegar", receptor: "+989121234567", message: "LifeMate test" },
    async (input, init) => {
      requestedUrl = String(input);
      requestedBody = String(init?.body ?? "");
      return new Response(JSON.stringify({ entries: [{ messageid: 123456789 }] }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    },
    (name) => new Map([
      ["LIFEMATE_KAVENEGAR_API_KEY", "protected-api-key"],
      ["LIFEMATE_KAVENEGAR_BASE_URL", "https://api.kavenegar.com"],
    ]).get(name),
  );
  assertEquals(result.kind, "delivered");
  assertStringIncludes(requestedUrl, "/v1/protected-api-key/sms/send.json");
  assertStringIncludes(requestedBody, "receptor=%2B989121234567");
  assertStringIncludes(requestedBody, "message=LifeMate+test");
});

Deno.test("Kavenegar ambiguous network failure is outcome-unknown, never blind retry evidence", async () => {
  const result = await sendSms(
    { provider: "kavenegar", receptor: "+989121234567", message: "LifeMate" },
    () => Promise.reject(new Error("network")),
    (name) => name === "LIFEMATE_KAVENEGAR_API_KEY" ? "protected-api-key" : undefined,
  );
  assertEquals(result, { kind: "unknown", code: "provider_outcome_unknown" });
});

Deno.test("FCM HTTP v1 adapter obtains OAuth token and sends provider message", async () => {
  resetCampaignProviderCacheForTest();
  const keyPair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const privateBytes = new Uint8Array(await crypto.subtle.exportKey("pkcs8", keyPair.privateKey));
  let binary = "";
  for (const byte of privateBytes) binary += String.fromCharCode(byte);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(binary).match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----\n`;
  const serviceAccount = JSON.stringify({
    project_id: "lifemate-test-project",
    client_email: "worker@lifemate-test-project.iam.gserviceaccount.com",
    private_key: pem,
    token_uri: "https://oauth2.googleapis.com/token",
  });
  const requests: string[] = [];
  const result = await sendPush(
    { provider: "fcm", token: "fcm-token-high-entropy-12345678901234567890", title: "Title", body: "Body" },
    async (input, init) => {
      requests.push(String(input));
      if (String(input).includes("oauth2.googleapis.com/token")) {
        return new Response(JSON.stringify({ access_token: "oauth-access-token", expires_in: 3600 }), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      }
      assertEquals(new Headers(init?.headers).get("authorization"), "Bearer oauth-access-token");
      const payload = JSON.parse(String(init?.body)) as Record<string, any>;
      assertEquals(payload.message.token, "fcm-token-high-entropy-12345678901234567890");
      return new Response(JSON.stringify({ name: "projects/lifemate-test-project/messages/abc123" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    },
    (name) => name === "LIFEMATE_FCM_SERVICE_ACCOUNT_JSON" ? serviceAccount : undefined,
  );
  assertEquals(result.kind, "delivered");
  assertEquals(requests.length, 2);
  assertStringIncludes(requests[1], "fcm.googleapis.com/v1/projects/lifemate-test-project/messages:send");
});
