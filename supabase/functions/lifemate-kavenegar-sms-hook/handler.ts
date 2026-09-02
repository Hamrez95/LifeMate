import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import {
  KavenegarOtpProvider,
  KavenegarProviderError,
  type PhoneOtpProvider,
} from "./provider.ts";

type SendSmsEvent = {
  user?: { phone?: unknown; new_phone?: unknown };
  sms?: { otp?: unknown };
};

type ProviderFactory = (
  apiKey: string,
  template: string,
) => PhoneOtpProvider;

type WarningSink = (
  message: string,
  metadata: Record<string, unknown>,
) => void;

export type SendSmsHookOptions = {
  apiKey?: string | null;
  template?: string | null;
  hookSecrets?: string | null;
  providerFactory?: ProviderFactory;
  warn?: WarningSink;
};

export function createSendSmsHookHandler(
  options: SendSmsHookOptions,
): (request: Request) => Promise<Response> {
  const apiKey = options.apiKey?.trim();
  const template = options.template?.trim();
  const hookSecrets = options.hookSecrets?.trim();
  const providerFactory = options.providerFactory ??
    ((key, verifyTemplate) => new KavenegarOtpProvider(key, verifyTemplate));
  const warn = options.warn ??
    ((message, metadata) => console.warn(message, metadata));

  return async (request: Request): Promise<Response> => {
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

    const event = verifyEvent(payload, request.headers, hookSecrets);
    if (!event) {
      return json(401, {
        error: { http_code: 401, message: "Invalid hook signature." },
      });
    }

    const phone = normalizeIranPhone(smsDestinationPhone(event));
    const otp = typeof event.sms?.otp === "string" ? event.sms.otp : "";
    if (!phone || !/^\d{6,10}$/.test(otp)) {
      return json(400, {
        error: { http_code: 400, message: "Invalid SMS hook payload." },
      });
    }

    try {
      const provider = providerFactory(apiKey, template);
      await provider.sendOtp(phone, otp);
      return json(200, {});
    } catch (error) {
      if (error instanceof KavenegarProviderError) {
        if (
          error.code === "iran_phone_required" ||
          error.code === "invalid_otp_shape" ||
          error.code === "kavenegar_receptor_invalid"
        ) {
          return json(400, {
            error: {
              http_code: 400,
              message:
                "Phone number is not eligible for the Iran SMS provider.",
            },
          });
        }

        // Provider status/code are operational metadata only. Never log the hook
        // body, phone or OTP, template contents, API key, or provider body.
        warn("LifeMate OTP provider failed", {
          code: safeCode(error.code),
          providerStatus: error.providerStatus,
          retryable: error.retryable,
        });

        if (!error.retryable) {
          // Permanent provider/account/template failures require operator action.
          // Returning 424 keeps them distinct from temporary 503 outages and
          // prevents treating a known permanent failure as an endlessly
          // retryable transport incident.
          return failedDependency("SMS provider is not ready for delivery.");
        }

        return serviceUnavailable(
          "SMS delivery is temporarily unavailable.",
          true,
        );
      }

      warn("LifeMate OTP provider failed", {
        code: "sms_provider_error",
        retryable: true,
      });
      return serviceUnavailable(
        "SMS delivery is temporarily unavailable.",
        true,
      );
    }
  };
}

function smsDestinationPhone(event: SendSmsEvent): string {
  const pendingPhone = event.user?.new_phone;
  if (typeof pendingPhone === "string" && pendingPhone.length > 0) {
    return pendingPhone;
  }
  return typeof event.user?.phone === "string" ? event.user.phone : "";
}

function normalizeIranPhone(raw: string): string {
  let value = raw.trim()
    .replace(/[\s()-]/g, "")
    .replace(/[۰-۹]/g, (digit) => String(digit.charCodeAt(0) - 1776))
    .replace(/[٠-٩]/g, (digit) => String(digit.charCodeAt(0) - 1632));

  if (/^00989\d{9}$/.test(value)) value = `+${value.slice(2)}`;
  else if (/^989\d{9}$/.test(value)) value = `+${value}`;
  else if (/^09\d{9}$/.test(value)) value = `+98${value.slice(1)}`;
  else if (/^9\d{9}$/.test(value)) value = `+98${value}`;

  return /^\+989\d{9}$/.test(value) ? value : "";
}

function verifyEvent(
  payload: string,
  headers: Headers,
  hookSecrets: string,
): SendSmsEvent | null {
  for (
    const configured of hookSecrets.split("|").map((value) => value.trim())
      .filter(Boolean)
  ) {
    const base64Secret = configured.replace(/^v1,whsec_/, "");
    if (!base64Secret) continue;
    try {
      const webhook = new Webhook(base64Secret);
      return webhook.verify(
        payload,
        Object.fromEntries(headers),
      ) as SendSmsEvent;
    } catch {
      // Try the next rotation secret. Never log the hook body, phone or OTP.
    }
  }
  return null;
}

function serviceUnavailable(message: string, retryable: boolean): Response {
  const response = json(503, { error: { http_code: 503, message } });
  if (retryable) response.headers.set("retry-after", "2");
  return response;
}

function failedDependency(message: string): Response {
  return json(424, { error: { http_code: 424, message } });
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
