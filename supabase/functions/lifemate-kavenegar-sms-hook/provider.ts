export interface PhoneOtpProvider {
  sendOtp(phoneE164: string, otp: string): Promise<void>;
}

type FetchLike = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

export class KavenegarProviderError extends Error {
  constructor(
    readonly code: string,
    readonly retryable: boolean,
    readonly providerStatus?: number,
  ) {
    super(code);
    this.name = "KavenegarProviderError";
  }
}

type KavenegarProviderOptions = {
  fetcher?: FetchLike;
  timeoutMs?: number;
};

type KavenegarEnvelope = {
  return?: {
    status?: number;
    message?: string;
  };
  entries?: unknown;
};

/**
 * Delivery adapter for Kavenegar's verification-template endpoint.
 *
 * LifeMate/Supabase owns OTP generation and verification. Kavenegar only
 * receives the already-generated token and delivers it; the provider must
 * never generate, persist, verify, or log OTP values itself.
 */
export class KavenegarOtpProvider implements PhoneOtpProvider {
  private readonly fetcher: FetchLike;
  private readonly timeoutMs: number;

  constructor(
    private readonly apiKey: string,
    private readonly template: string,
    options: KavenegarProviderOptions = {},
  ) {
    this.fetcher = options.fetcher ?? fetch;
    // Supabase Auth HTTP hooks have an enclosing deadline. Keep enough budget
    // for Edge startup, webhook verification, parsing and the final response so
    // a slow provider cannot deliver an OTP after Supabase already timed out.
    this.timeoutMs = options.timeoutMs ?? 3_500;
  }

  async sendOtp(phoneE164: string, otp: string): Promise<void> {
    const receptor = iranianReceptor(phoneE164);
    validateOtp(otp);
    validateConfiguration(this.apiKey, this.template);

    const endpoint = new URL(
      `https://api.kavenegar.com/v1/${
        encodeURIComponent(this.apiKey)
      }/verify/lookup.json`,
    );

    // Use form-encoded POST rather than query-string GET so the phone number
    // and OTP are not copied into ordinary request URLs/proxy access logs.
    const body = new URLSearchParams();
    body.set("receptor", receptor);
    body.set("token", otp);
    body.set("template", this.template);
    body.set("type", "sms");

    let response: Response;
    try {
      response = await this.fetcher(endpoint, {
        method: "POST",
        signal: AbortSignal.timeout(this.timeoutMs),
        headers: {
          accept: "application/json",
          "content-type": "application/x-www-form-urlencoded; charset=utf-8",
        },
        body: body.toString(),
      });
    } catch {
      throw new KavenegarProviderError("kavenegar_transport_error", true);
    }

    let envelope: KavenegarEnvelope | null = null;
    try {
      envelope = await response.json() as KavenegarEnvelope;
    } catch {
      // A malformed/non-JSON provider response is never forwarded to callers.
    }

    const providerStatus = asStatus(envelope?.return?.status);
    if (!response.ok || providerStatus !== 200) {
      throw mapProviderFailure(providerStatus ?? response.status);
    }
  }
}

function validateOtp(otp: string): void {
  if (!/^\d{6,10}$/.test(otp)) {
    throw new KavenegarProviderError("invalid_otp_shape", false);
  }
}

function validateConfiguration(apiKey: string, template: string): void {
  if (!apiKey.trim() || apiKey.length > 256 || /[\s/?#]/.test(apiKey)) {
    throw new KavenegarProviderError("invalid_kavenegar_api_key", false);
  }

  if (!/^[A-Za-z0-9-]{1,64}$/.test(template)) {
    throw new KavenegarProviderError("invalid_kavenegar_template", false);
  }
}

function asStatus(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && /^\d+$/.test(value)) return Number(value);
  return undefined;
}

function mapProviderFailure(status: number): KavenegarProviderError {
  switch (status) {
    case 400:
    case 406:
      return new KavenegarProviderError("kavenegar_bad_request", false, status);
    case 401:
      return new KavenegarProviderError(
        "kavenegar_account_inactive",
        false,
        status,
      );
    case 403:
    case 407:
    case 427:
      return new KavenegarProviderError(
        "kavenegar_api_access_denied",
        false,
        status,
      );
    case 402:
      return new KavenegarProviderError(
        "kavenegar_operation_failed",
        true,
        status,
      );
    case 409:
      return new KavenegarProviderError(
        "kavenegar_temporarily_unavailable",
        true,
        status,
      );
    case 411:
      return new KavenegarProviderError(
        "kavenegar_receptor_invalid",
        false,
        status,
      );
    case 418:
      return new KavenegarProviderError(
        "kavenegar_credit_insufficient",
        false,
        status,
      );
    case 422:
      return new KavenegarProviderError(
        "kavenegar_token_rejected",
        false,
        status,
      );
    case 424:
      return new KavenegarProviderError(
        "kavenegar_template_missing",
        false,
        status,
      );
    case 426:
      return new KavenegarProviderError(
        "kavenegar_advanced_service_required",
        false,
        status,
      );
    case 428:
      return new KavenegarProviderError(
        "kavenegar_call_token_invalid",
        false,
        status,
      );
    case 429:
      return new KavenegarProviderError(
        "kavenegar_rate_limited",
        true,
        status,
      );
    case 431:
      return new KavenegarProviderError(
        "kavenegar_token_format_invalid",
        false,
        status,
      );
    case 432:
      return new KavenegarProviderError(
        "kavenegar_template_token_missing",
        false,
        status,
      );
    case 607:
      return new KavenegarProviderError(
        "kavenegar_tag_invalid",
        false,
        status,
      );
    default:
      return new KavenegarProviderError(
        status >= 500 ? "kavenegar_provider_unavailable" : "kavenegar_rejected",
        status >= 500,
        status,
      );
  }
}

function iranianReceptor(phoneE164: string): string {
  const normalized = phoneE164.replace(/[\s()-]/g, "");
  if (!/^\+989\d{9}$/.test(normalized)) {
    throw new KavenegarProviderError("iran_phone_required", false);
  }
  return `0${normalized.slice(3)}`;
}
