import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { createSendSmsHookHandler } from "./handler.ts";
import { KavenegarProviderError, type PhoneOtpProvider } from "./provider.ts";

const API_KEY = "syntheticApiKey123";
const TEMPLATE = "lifemate-login";
const SECRET_BYTES = new TextEncoder().encode("lifemate-test-webhook-secret");
const SECRET_BASE64 = toBase64(SECRET_BYTES);
const HOOK_SECRET = `v1,whsec_${SECRET_BASE64}`;
const SYNTHETIC_PHONE = "+989000000000";
const SYNTHETIC_OLD_PHONE = "+989111111111";
const SYNTHETIC_OTP = "654321";

Deno.test("Send SMS hook rejects non-POST requests with no-store", async () => {
  const handler = createSendSmsHookHandler({
    apiKey: API_KEY,
    template: TEMPLATE,
    hookSecrets: HOOK_SECRET,
  });

  const response = await handler(new Request("https://example.invalid/hook"));

  assertEquals(response.status, 405);
  assertEquals(response.headers.get("cache-control"), "no-store");
});

Deno.test("Send SMS hook fails closed on missing configuration before provider creation", async () => {
  let providerCreations = 0;
  const handler = createSendSmsHookHandler({
    apiKey: API_KEY,
    template: TEMPLATE,
    hookSecrets: "",
    providerFactory: () => {
      providerCreations++;
      return successfulProvider();
    },
  });

  const response = await handler(
    new Request("https://example.invalid/hook", {
      method: "POST",
      body: "{}",
    }),
  );

  assertEquals(response.status, 503);
  assertEquals(response.headers.get("retry-after"), null);
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(providerCreations, 0);
});

Deno.test("Send SMS hook rejects oversized payload before provider invocation", async () => {
  let providerCreations = 0;
  const handler = createSendSmsHookHandler({
    apiKey: API_KEY,
    template: TEMPLATE,
    hookSecrets: HOOK_SECRET,
    providerFactory: () => {
      providerCreations++;
      return successfulProvider();
    },
  });

  const response = await handler(
    new Request("https://example.invalid/hook", {
      method: "POST",
      body: "x".repeat(20_001),
    }),
  );

  assertEquals(response.status, 400);
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(providerCreations, 0);
});

Deno.test("Send SMS hook rejects invalid Standard Webhooks signature before provider invocation", async () => {
  let providerCreations = 0;
  const handler = createSendSmsHookHandler({
    apiKey: API_KEY,
    template: TEMPLATE,
    hookSecrets: HOOK_SECRET,
    providerFactory: () => {
      providerCreations++;
      return successfulProvider();
    },
  });
  const payload = validPayload();
  const request = new Request("https://example.invalid/hook", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "webhook-id": "msg_invalid_signature",
      "webhook-timestamp": `${Math.floor(Date.now() / 1000)}`,
      "webhook-signature": "v1,invalid",
    },
    body: payload,
  });

  const response = await handler(request);

  assertEquals(response.status, 401);
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(providerCreations, 0);
});

Deno.test("Send SMS hook rejects malformed phone and OTP before provider invocation", async () => {
  const invalidEvents = [
    { user: { phone: "+12025550123" }, sms: { otp: SYNTHETIC_OTP } },
    { user: { phone: SYNTHETIC_PHONE }, sms: { otp: "abc123" } },
    {
      user: { phone: SYNTHETIC_PHONE, new_phone: "+12025550123" },
      sms: { otp: SYNTHETIC_OTP },
    },
  ];

  for (const event of invalidEvents) {
    let providerCreations = 0;
    const handler = createSendSmsHookHandler({
      apiKey: API_KEY,
      template: TEMPLATE,
      hookSecrets: HOOK_SECRET,
      providerFactory: () => {
        providerCreations++;
        return successfulProvider();
      },
    });
    const request = await signedRequest(JSON.stringify(event));

    const response = await handler(request);

    assertEquals(response.status, 400);
    assertEquals(response.headers.get("cache-control"), "no-store");
    assertEquals(providerCreations, 0);
  }
});

Deno.test("Send SMS hook accepts a valid signed event and calls provider exactly once", async () => {
  let providerCreations = 0;
  let sends = 0;
  const handler = createSendSmsHookHandler({
    apiKey: API_KEY,
    template: TEMPLATE,
    hookSecrets: HOOK_SECRET,
    providerFactory: () => {
      providerCreations++;
      return {
        sendOtp: (phone, otp) => {
          sends++;
          assertEquals(phone, SYNTHETIC_PHONE);
          assertEquals(otp, SYNTHETIC_OTP);
          return Promise.resolve();
        },
      };
    },
  });

  const response = await handler(await signedRequest(validPayload()));

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {});
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(providerCreations, 1);
  assertEquals(sends, 1);
});

Deno.test("Send SMS hook sends phone-change OTP to new_phone on the same user", async () => {
  let providerCreations = 0;
  let sends = 0;
  const handler = createSendSmsHookHandler({
    apiKey: API_KEY,
    template: TEMPLATE,
    hookSecrets: HOOK_SECRET,
    providerFactory: () => {
      providerCreations++;
      return {
        sendOtp: (phone, otp) => {
          sends++;
          assertEquals(phone, SYNTHETIC_PHONE);
          assertEquals(otp, SYNTHETIC_OTP);
          return Promise.resolve();
        },
      };
    },
  });
  const payload = JSON.stringify({
    user: { phone: SYNTHETIC_OLD_PHONE, new_phone: SYNTHETIC_PHONE },
    sms: { otp: SYNTHETIC_OTP },
  });

  const response = await handler(await signedRequest(payload));

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {});
  assertEquals(providerCreations, 1);
  assertEquals(sends, 1);
});

Deno.test("Send SMS hook sends first phone attachment OTP to new_phone when phone is empty", async () => {
  let sends = 0;
  const handler = createSendSmsHookHandler({
    apiKey: API_KEY,
    template: TEMPLATE,
    hookSecrets: HOOK_SECRET,
    providerFactory: () => ({
      sendOtp: (phone, otp) => {
        sends++;
        assertEquals(phone, SYNTHETIC_PHONE);
        assertEquals(otp, SYNTHETIC_OTP);
        return Promise.resolve();
      },
    }),
  });
  const payload = JSON.stringify({
    user: { phone: "", new_phone: SYNTHETIC_PHONE },
    sms: { otp: SYNTHETIC_OTP },
  });

  const response = await handler(await signedRequest(payload));

  assertEquals(response.status, 200);
  assertEquals(sends, 1);
});

Deno.test("Send SMS hook maps retryable provider failures to generic 503 with Retry-After", async () => {
  const handler = createSendSmsHookHandler({
    apiKey: API_KEY,
    template: TEMPLATE,
    hookSecrets: HOOK_SECRET,
    providerFactory: () => ({
      sendOtp: () =>
        Promise.reject(
          new KavenegarProviderError(
            "kavenegar_temporarily_unavailable",
            true,
            409,
          ),
        ),
    }),
    warn: () => {},
  });

  const response = await handler(await signedRequest(validPayload()));
  const body = await response.text();

  assertEquals(response.status, 503);
  assert(response.headers.get("retry-after"));
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertStringIncludes(body, "SMS delivery is temporarily unavailable.");
  assert(!body.includes(SYNTHETIC_PHONE));
  assert(!body.includes(SYNTHETIC_OTP));
});

Deno.test("Send SMS hook maps permanent provider failures to redacted 424", async () => {
  const warnings: string[] = [];
  const handler = createSendSmsHookHandler({
    apiKey: API_KEY,
    template: TEMPLATE,
    hookSecrets: HOOK_SECRET,
    providerFactory: () => ({
      sendOtp: () =>
        Promise.reject(
          new KavenegarProviderError(
            "kavenegar_credit_insufficient",
            false,
            418,
          ),
        ),
    }),
    warn: (message, metadata) => {
      warnings.push(JSON.stringify({ message, metadata }));
    },
  });

  const response = await handler(await signedRequest(validPayload()));
  const body = await response.text();
  const warningText = warnings.join("\n");

  assertEquals(response.status, 424);
  assertEquals(response.headers.get("retry-after"), null);
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertStringIncludes(body, "SMS provider is not ready for delivery.");
  for (const sensitive of [SYNTHETIC_PHONE, SYNTHETIC_OTP, API_KEY]) {
    assert(!body.includes(sensitive));
    assert(!warningText.includes(sensitive));
  }
  assert(!body.includes("kavenegar_credit_insufficient"));
  assertEquals(warnings.length, 1);
});

Deno.test("Send SMS hook maps invalid provider receptor to a generic 400", async () => {
  const handler = createSendSmsHookHandler({
    apiKey: API_KEY,
    template: TEMPLATE,
    hookSecrets: HOOK_SECRET,
    providerFactory: () => ({
      sendOtp: () =>
        Promise.reject(
          new KavenegarProviderError(
            "kavenegar_receptor_invalid",
            false,
            411,
          ),
        ),
    }),
    warn: () => {},
  });

  const response = await handler(await signedRequest(validPayload()));
  const body = await response.text();

  assertEquals(response.status, 400);
  assertEquals(response.headers.get("retry-after"), null);
  assertStringIncludes(body, "Phone number is not eligible");
  assert(!body.includes(SYNTHETIC_PHONE));
  assert(!body.includes(SYNTHETIC_OTP));
});

function validPayload(): string {
  return JSON.stringify({
    user: { phone: SYNTHETIC_PHONE },
    sms: { otp: SYNTHETIC_OTP },
  });
}

function successfulProvider(): PhoneOtpProvider {
  return { sendOtp: () => Promise.resolve() };
}

async function signedRequest(payload: string): Promise<Request> {
  const webhookId = "msg_lifemate_hook_test";
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
