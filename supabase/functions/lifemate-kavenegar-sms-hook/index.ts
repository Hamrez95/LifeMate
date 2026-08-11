import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { KavenegarOtpProvider, KavenegarProviderError } from "./provider.ts";

type SendSmsEvent = {
  user: { phone?: unknown };
  sms: { otp?: unknown };
};

const apiKey = Deno.env.get("KAVENEGAR_API_KEY")?.trim();
const template = Deno.env.get("KAVENEGAR_VERIFY_TEMPLATE")?.trim();
const hookSecrets = Deno.env.get("SEND_SMS_HOOK_SECRETS")?.trim();

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return json(405, {
      error: { http_code: 405, message: "Invalid hook method." },
    });
  }
  if (!apiKey || !template || !hookSecrets) {
    return serviceUnavailable("SMS provider is not configured.", false);
  }

  const payload = await request.text();
  if (new TextEncoder().encode(payload).length > 20_000) {
    return json(400, {
      error: { http_code: 400, message: "Hook payload is too large." },
    });
  }

  let event: SendSmsEvent | null = null;
  for (
    const configured of hookSecrets.split("|").map((value) => value.trim())
      .filter(Boolean)
  ) {
    const base64Secret = configured.replace(/^v1,whsec_/, "");
    if (!base64Secret) continue;
    try {
      const webhook = new Webhook(base64Secret);
      event = webhook.verify(
        payload,
        Object.fromEntries(request.headers),
      ) as SendSmsEvent;
      break;
    } catch {
      // Try the next rotation secret. Never log the hook body, phone or OTP.
    }
  }
  if (!event) {
    return json(401, {
      error: { http_code: 401, message: "Invalid hook signature." },
    });
  }

  const phone = typeof event.user?.phone === "string" ? event.user.phone : "";
  const otp = typeof event.sms?.otp === "string" ? event.sms.otp : "";
  if (!phone || !/^\d{6,10}$/.test(otp)) {
    return json(400, {
      error: { http_code: 400, message: "Invalid SMS hook payload." },
    });
  }

  try {
    const provider = new KavenegarOtpProvider(apiKey, template);
    await provider.sendOtp(phone, otp);
    // Supabase Send SMS hooks treat a successful 2xx response as delivery
    // acceptance. Keep the response empty of authentication data.
    return json(200, {});
  } catch (error) {
    if (error instanceof KavenegarProviderError) {
      if (
        error.code === "iran_phone_required" ||
        error.code === "invalid_otp_shape"
      ) {
        return json(400, {
          error: {
            http_code: 400,
            message: "Phone number is not eligible for the Iran SMS provider.",
          },
        });
      }

      // Provider status/code are operational metadata only. Never log the phone,
      // token, template contents, API key, provider response body, or hook body.
      console.warn("LifeMate OTP provider failed", {
        code: safeCode(error.code),
        providerStatus: error.providerStatus,
        retryable: error.retryable,
      });
      return serviceUnavailable(
        "SMS delivery is temporarily unavailable.",
        error.retryable,
      );
    }

    console.warn("LifeMate OTP provider failed", {
      code: "sms_provider_error",
      retryable: true,
    });
    return serviceUnavailable("SMS delivery is temporarily unavailable.", true);
  }
});

function serviceUnavailable(message: string, retryable: boolean): Response {
  const response = json(503, { error: { http_code: 503, message } });
  if (retryable) response.headers.set("retry-after", "2");
  return response;
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function safeCode(value: string): string {
  return value.replace(/[^a-zA-Z0-9:_-]/g, "_").slice(0, 80) ||
    "sms_provider_error";
}
