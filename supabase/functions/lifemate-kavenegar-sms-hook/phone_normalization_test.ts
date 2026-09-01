import { assertEquals } from "jsr:@std/assert@1";
import { createSendSmsHookHandler } from "./handler.ts";

const API_KEY = "syntheticApiKey123";
const TEMPLATE = "lifemate-login";
const SECRET_BYTES = new TextEncoder().encode("lifemate-test-webhook-secret");
const HOOK_SECRET = `v1,whsec_${toBase64(SECRET_BYTES)}`;
const EXPECTED_PHONE = "+989000000000";
const OTP = "654321";

Deno.test("Send SMS hook canonicalizes supported Iranian phone formats", async () => {
  const cases = [
    "09000000000",
    "989000000000",
    "+989000000000",
    "00989000000000",
    "۰۹۰۰۰۰۰۰۰۰۰",
  ];

  for (const rawPhone of cases) {
    let sentPhone = "";
    const handler = createSendSmsHookHandler({
      apiKey: API_KEY,
      template: TEMPLATE,
      hookSecrets: HOOK_SECRET,
      providerFactory: () => ({
        sendOtp: (phone) => {
          sentPhone = phone;
          return Promise.resolve();
        },
      }),
    });

    const payload = JSON.stringify({
      user: { phone: "", new_phone: rawPhone },
      sms: { otp: OTP },
    });

    const response = await handler(await signedRequest(payload));

    assertEquals(response.status, 200);
    assertEquals(sentPhone, EXPECTED_PHONE);
  }
});

Deno.test("Send SMS hook still rejects non-Iranian pending destinations", async () => {
  let sends = 0;
  const handler = createSendSmsHookHandler({
    apiKey: API_KEY,
    template: TEMPLATE,
    hookSecrets: HOOK_SECRET,
    providerFactory: () => ({
      sendOtp: () => {
        sends++;
        return Promise.resolve();
      },
    }),
  });

  const payload = JSON.stringify({
    user: { phone: EXPECTED_PHONE, new_phone: "+12025550123" },
    sms: { otp: OTP },
  });

  const response = await handler(await signedRequest(payload));

  assertEquals(response.status, 400);
  assertEquals(sends, 0);
});

async function signedRequest(payload: string): Promise<Request> {
  const webhookId = "msg_lifemate_phone_normalization_test";
  const timestamp = `${Math.floor(Date.now() / 1000)}`;
  const signedContent = `${webhookId}.${timestamp}.${payload}`;
  const key = await crypto.subtle.importKey(
    "raw",
    SECRET_BYTES,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(signedContent),
    ),
  );

  return new Request("https://example.invalid/hook", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "webhook-id": webhookId,
      "webhook-timestamp": timestamp,
      "webhook-signature": `v1,${toBase64(signature)}`,
    },
    body: payload,
  });
}

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
