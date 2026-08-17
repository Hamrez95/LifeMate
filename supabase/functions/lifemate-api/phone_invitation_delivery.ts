import { ApiError } from "./validation.ts";

export type PhoneInvitationDelivery = {
  requireEnabled(): void;
  deliver(phoneE164: string, token: string): Promise<void>;
};

type FetchLike = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

type DeliveryOptions = {
  enabled: boolean;
  apiKey?: string | null;
  template?: string | null;
  fetcher?: FetchLike;
  timeoutMs?: number;
};

type KavenegarEnvelope = {
  return?: {
    status?: number | string;
    message?: string;
  };
  entries?: unknown;
};

export class KavenegarCareInviteError extends Error {
  constructor(
    readonly code: string,
    readonly retryable: boolean,
    readonly outcomeUnknown: boolean,
    readonly providerStatus?: number,
  ) {
    super(code);
    this.name = "KavenegarCareInviteError";
  }
}

export function createPhoneInvitationDeliveryFromEnvironment(): PhoneInvitationDelivery {
  const rawEnabled = Deno.env.get("ENABLE_PHONE_CARE_INVITES")?.trim()
    .toLowerCase();
  if (rawEnabled != null && rawEnabled !== "true" && rawEnabled !== "false") {
    throw new Error("ENABLE_PHONE_CARE_INVITES must be true or false.");
  }
  return createPhoneInvitationDelivery({
    enabled: rawEnabled === "true",
    apiKey: Deno.env.get("KAVENEGAR_API_KEY"),
    template: Deno.env.get("KAVENEGAR_CARE_INVITE_TEMPLATE"),
  });
}

export function createPhoneInvitationDelivery(
  options: DeliveryOptions,
): PhoneInvitationDelivery {
  const apiKey = options.apiKey?.trim() ?? "";
  const template = options.template?.trim() ?? "";
  const fetcher = options.fetcher ?? fetch;
  const timeoutMs = options.timeoutMs ?? 3_500;

  function requireEnabled(): void {
    if (!options.enabled || !apiKey || !template) {
      throw unavailable();
    }
  }

  async function deliver(phoneE164: string, token: string): Promise<void> {
    requireEnabled();
    try {
      await sendKavenegarTemplateToken(
        apiKey,
        template,
        phoneE164,
        token,
        fetcher,
        timeoutMs,
      );
    } catch (error) {
      if (error instanceof KavenegarCareInviteError) {
        throw unavailable();
      }
      throw unavailable();
    }
  }

  return { requireEnabled, deliver };
}

async function sendKavenegarTemplateToken(
  apiKey: string,
  template: string,
  phoneE164: string,
  token: string,
  fetcher: FetchLike,
  timeoutMs: number,
): Promise<void> {
  const receptor = iranianReceptor(phoneE164);
  validateToken(token);
  validateConfiguration(apiKey, template, timeoutMs);

  const endpoint = new URL(
    `https://api.kavenegar.com/v1/${
      encodeURIComponent(apiKey)
    }/verify/lookup.json`,
  );
  const body = new URLSearchParams();
  body.set("receptor", receptor);
  body.set("token", token);
  body.set("template", template);
  body.set("type", "sms");

  let response: Response;
  try {
    response = await fetcher(endpoint, {
      method: "POST",
      signal: AbortSignal.timeout(timeoutMs),
      headers: {
        accept: "application/json",
        "content-type": "application/x-www-form-urlencoded; charset=utf-8",
      },
      body: body.toString(),
    });
  } catch {
    // No provider response means delivery outcome is ambiguous. Callers must
    // never persist the raw token for a later blind retry.
    throw new KavenegarCareInviteError(
      "kavenegar_transport_error",
      false,
      true,
    );
  }

  let envelope: KavenegarEnvelope | null = null;
  try {
    envelope = await response.json() as KavenegarEnvelope;
  } catch {
    // Provider bodies are intentionally discarded and never forwarded/logged.
  }
  const providerStatus = asStatus(envelope?.return?.status);
  if (!response.ok || providerStatus !== 200) {
    throw mapProviderFailure(providerStatus ?? response.status);
  }
}

function validateToken(token: string): void {
  if (!/^\d{10}$/.test(token)) {
    throw new KavenegarCareInviteError(
      "invalid_invitation_token_shape",
      false,
      false,
    );
  }
}

function validateConfiguration(
  apiKey: string,
  template: string,
  timeoutMs: number,
): void {
  if (!apiKey || apiKey.length > 256 || /[\s/?#]/.test(apiKey)) {
    throw new KavenegarCareInviteError(
      "invalid_kavenegar_api_key",
      false,
      false,
    );
  }
  if (!/^[A-Za-z0-9-]{1,64}$/.test(template)) {
    throw new KavenegarCareInviteError(
      "invalid_kavenegar_template",
      false,
      false,
    );
  }
  if (!Number.isFinite(timeoutMs) || timeoutMs < 500 || timeoutMs > 10_000) {
    throw new KavenegarCareInviteError(
      "invalid_kavenegar_timeout",
      false,
      false,
    );
  }
}

function iranianReceptor(phoneE164: string): string {
  const normalized = phoneE164.replace(/[\s()-]/g, "");
  if (!/^\+989\d{9}$/.test(normalized)) {
    throw new KavenegarCareInviteError("iran_phone_required", false, false);
  }
  return `0${normalized.slice(3)}`;
}

function asStatus(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && /^\d+$/.test(value)) return Number(value);
  return undefined;
}

function mapProviderFailure(status: number): KavenegarCareInviteError {
  switch (status) {
    case 400:
      return providerError("kavenegar_bad_request", false, status);
    case 401:
      return providerError("kavenegar_account_inactive", false, status);
    case 403:
      return providerError("kavenegar_api_key_invalid", false, status);
    case 409:
      return providerError("kavenegar_temporarily_unavailable", true, status);
    case 418:
      return providerError("kavenegar_credit_insufficient", false, status);
    case 422:
      return providerError("kavenegar_token_rejected", false, status);
    case 424:
      return providerError("kavenegar_template_missing", false, status);
    case 426:
      return providerError("kavenegar_advanced_service_required", false, status);
    case 428:
      return providerError("kavenegar_call_token_invalid", false, status);
    case 431:
      return providerError("kavenegar_token_format_invalid", false, status);
    case 432:
      return providerError("kavenegar_template_token_missing", false, status);
    case 607:
      return providerError("kavenegar_tag_invalid", false, status);
    default:
      return providerError(
        status >= 500 || status === 429
          ? "kavenegar_provider_unavailable"
          : "kavenegar_rejected",
        status >= 500 || status === 429,
        status,
      );
  }
}

function providerError(
  code: string,
  retryable: boolean,
  providerStatus: number,
): KavenegarCareInviteError {
  return new KavenegarCareInviteError(
    code,
    retryable,
    false,
    providerStatus,
  );
}

function unavailable(): ApiError {
  return new ApiError(
    503,
    "phone_invitation_delivery_unavailable",
    "Phone invitation delivery is temporarily unavailable.",
  );
}
