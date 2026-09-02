import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { KavenegarOtpProvider, KavenegarProviderError } from "./provider.ts";

Deno.test("Kavenegar OTP uses POST body and does not put phone/token in URL", async () => {
  let capturedUrl = "";
  let capturedInit: RequestInit | undefined;
  const provider = new KavenegarOtpProvider(
    "testApiKey123",
    "lifemate-login",
    {
      fetcher: async (input, init) => {
        capturedUrl = input.toString();
        capturedInit = init;
        return new Response(
          JSON.stringify({
            return: { status: 200, message: "ok" },
            entries: [{ messageid: 42, status: 5 }],
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        );
      },
    },
  );

  await provider.sendOtp("+989121234567", "852596");

  assertEquals(capturedInit?.method, "POST");
  assert(!capturedUrl.includes("09121234567"));
  assert(!capturedUrl.includes("852596"));
  const form = new URLSearchParams(capturedInit?.body?.toString());
  assertEquals(form.get("receptor"), "09121234567");
  assertEquals(form.get("token"), "852596");
  assertEquals(form.get("template"), "lifemate-login");
  assertEquals(form.get("type"), "sms");
  assertEquals(form.has("tag"), false);
});

Deno.test("Kavenegar OTP rejects template names with underscore before network", async () => {
  let calls = 0;
  const provider = new KavenegarOtpProvider(
    "testApiKey123",
    "lifemate_login",
    {
      fetcher: async () => {
        calls++;
        return new Response("{}", { status: 200 });
      },
    },
  );

  const error = await assertRejects(
    () => provider.sendOtp("+989121234567", "852596"),
    KavenegarProviderError,
  );
  assertEquals(error.code, "invalid_kavenegar_template");
  assertEquals(error.retryable, false);
  assertEquals(calls, 0);
});

Deno.test("Kavenegar OTP maps missing template to non-retryable provider failure", async () => {
  const provider = providerReturning(424);
  const error = await assertRejects(
    () => provider.sendOtp("+989121234567", "852596"),
    KavenegarProviderError,
  );
  assertEquals(error.code, "kavenegar_template_missing");
  assertEquals(error.retryable, false);
  assertEquals(error.providerStatus, 424);
});

Deno.test("Kavenegar OTP maps invalid receptor to a permanent recipient failure", async () => {
  const provider = providerReturning(411);
  const error = await assertRejects(
    () => provider.sendOtp("+989121234567", "852596"),
    KavenegarProviderError,
  );
  assertEquals(error.code, "kavenegar_receptor_invalid");
  assertEquals(error.retryable, false);
  assertEquals(error.providerStatus, 411);
});

Deno.test("Kavenegar OTP maps insufficient credit to a permanent operator failure", async () => {
  const provider = providerReturning(418);
  const error = await assertRejects(
    () => provider.sendOtp("+989121234567", "852596"),
    KavenegarProviderError,
  );
  assertEquals(error.code, "kavenegar_credit_insufficient");
  assertEquals(error.retryable, false);
  assertEquals(error.providerStatus, 418);
});

Deno.test("Kavenegar OTP maps provider rate limiting as retryable", async () => {
  const provider = providerReturning(429);
  const error = await assertRejects(
    () => provider.sendOtp("+989121234567", "852596"),
    KavenegarProviderError,
  );
  assertEquals(error.code, "kavenegar_rate_limited");
  assertEquals(error.retryable, true);
  assertEquals(error.providerStatus, 429);
});

Deno.test("Kavenegar OTP maps temporary provider outage as retryable", async () => {
  const provider = providerReturning(409);
  const error = await assertRejects(
    () => provider.sendOtp("+989121234567", "852596"),
    KavenegarProviderError,
  );
  assertEquals(error.code, "kavenegar_temporarily_unavailable");
  assertEquals(error.retryable, true);
});

Deno.test("Kavenegar OTP maps 607 to documented invalid tag failure", async () => {
  const provider = providerReturning(607, 200);
  const error = await assertRejects(
    () => provider.sendOtp("+989121234567", "852596"),
    KavenegarProviderError,
  );
  assertEquals(error.code, "kavenegar_tag_invalid");
  assertEquals(error.retryable, false);
  assertEquals(error.providerStatus, 607);
});

Deno.test("Kavenegar OTP rejects non-Iran phone before network", async () => {
  let calls = 0;
  const provider = new KavenegarOtpProvider(
    "testApiKey123",
    "lifemate-login",
    {
      fetcher: async () => {
        calls++;
        return new Response("{}", { status: 200 });
      },
    },
  );

  const error = await assertRejects(
    () => provider.sendOtp("+994501234567", "852596"),
    KavenegarProviderError,
  );
  assertEquals(error.code, "iran_phone_required");
  assertEquals(calls, 0);
});

Deno.test("Kavenegar OTP treats network failures as retryable without leaking payload", async () => {
  const provider = new KavenegarOtpProvider(
    "testApiKey123",
    "lifemate-login",
    {
      fetcher: () => Promise.reject(new Error("network details")),
    },
  );

  const error = await assertRejects(
    () => provider.sendOtp("+989121234567", "852596"),
    KavenegarProviderError,
  );
  assertEquals(error.code, "kavenegar_transport_error");
  assertEquals(error.retryable, true);
  assert(!error.message.includes("852596"));
  assert(!error.message.includes("09121234567"));
});

function providerReturning(
  providerStatus: number,
  httpStatus = providerStatus,
): KavenegarOtpProvider {
  return new KavenegarOtpProvider(
    "testApiKey123",
    "lifemate-login",
    {
      fetcher: async () =>
        new Response(
          JSON.stringify({
            return: { status: providerStatus, message: "redacted" },
          }),
          {
            status: httpStatus,
            headers: { "content-type": "application/json" },
          },
        ),
    },
  );
}
