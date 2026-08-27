type FetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

export type CampaignProviderResult =
  | { kind: "delivered"; providerReference: string }
  | { kind: "failed"; code: string; retryable: boolean }
  | { kind: "outcome_unknown"; code: string };

export type SmsCampaignDelivery = {
  phoneE164: string;
  message: string;
};

export type PushCampaignDelivery = {
  token: string;
  title?: string | null;
  body: string;
};

export interface SmsCampaignProvider {
  send(input: SmsCampaignDelivery): Promise<CampaignProviderResult>;
}

export interface PushCampaignProvider {
  send(input: PushCampaignDelivery): Promise<CampaignProviderResult>;
}

function boundedText(value: string, min: number, max: number, code: string): string {
  const normalized = value.trim();
  const size = new TextEncoder().encode(normalized).byteLength;
  if (size < min || size > max) throw new Error(code);
  return normalized;
}

function iranianReceptor(phoneE164: string): string {
  const normalized = phoneE164.replace(/[\s()-]/g, "");
  if (!/^\+989\d{9}$/.test(normalized)) throw new Error("campaign_sms_phone_invalid");
  return `0${normalized.slice(3)}`;
}

function providerReference(value: unknown): string | null {
  if (typeof value === "number" && Number.isSafeInteger(value) && value > 0) return String(value);
  if (typeof value === "string" && /^[A-Za-z0-9._:-]{1,256}$/.test(value)) return value;
  return null;
}

export class KavenegarCampaignSmsProvider implements SmsCampaignProvider {
  private readonly fetcher: FetchLike;
  private readonly timeoutMs: number;

  constructor(
    private readonly apiKey: string,
    private readonly sender: string,
    options: { fetcher?: FetchLike; timeoutMs?: number } = {},
  ) {
    this.fetcher = options.fetcher ?? fetch;
    this.timeoutMs = options.timeoutMs ?? 5_000;
  }

  async send(input: SmsCampaignDelivery): Promise<CampaignProviderResult> {
    const receptor = iranianReceptor(input.phoneE164);
    const message = boundedText(input.message, 1, 2000, "campaign_sms_message_invalid");
    const apiKey = boundedText(this.apiKey, 8, 256, "campaign_sms_provider_config_invalid");
    const sender = boundedText(this.sender, 3, 32, "campaign_sms_provider_config_invalid");
    if (/[\s/?#]/.test(apiKey) || !/^[0-9+]{3,32}$/.test(sender)) {
      throw new Error("campaign_sms_provider_config_invalid");
    }
    const endpoint = new URL(`https://api.kavenegar.com/v1/${encodeURIComponent(apiKey)}/sms/send.json`);
    const body = new URLSearchParams({ receptor, sender, message });
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
      // A transport timeout may occur after the provider accepted the side effect.
      return { kind: "outcome_unknown", code: "kavenegar_transport_outcome_unknown" };
    }

    let payload: unknown;
    try {
      payload = await response.json();
    } catch {
      return response.ok
        ? { kind: "outcome_unknown", code: "kavenegar_response_invalid" }
        : { kind: "failed", code: "kavenegar_response_invalid", retryable: response.status >= 500 };
    }
    const envelope = payload as { return?: { status?: number | string }; entries?: Array<{ messageid?: unknown }> };
    const providerStatus = Number(envelope.return?.status ?? response.status);
    if (!response.ok || providerStatus !== 200) {
      const retryable = response.status === 429 || response.status >= 500 || providerStatus === 409;
      return { kind: "failed", code: `kavenegar_${Number.isFinite(providerStatus) ? providerStatus : "rejected"}`, retryable };
    }
    const reference = providerReference(envelope.entries?.[0]?.messageid);
    if (!reference) return { kind: "outcome_unknown", code: "kavenegar_reference_missing" };
    return { kind: "delivered", providerReference: reference };
  }
}

export class FcmHttpV1PushProvider implements PushCampaignProvider {
  private readonly fetcher: FetchLike;
  private readonly timeoutMs: number;

  constructor(
    private readonly projectId: string,
    private readonly oauthAccessToken: string,
    options: { fetcher?: FetchLike; timeoutMs?: number } = {},
  ) {
    this.fetcher = options.fetcher ?? fetch;
    this.timeoutMs = options.timeoutMs ?? 5_000;
  }

  async send(input: PushCampaignDelivery): Promise<CampaignProviderResult> {
    const projectId = boundedText(this.projectId, 3, 128, "campaign_push_provider_config_invalid");
    const accessToken = boundedText(this.oauthAccessToken, 20, 8192, "campaign_push_provider_config_invalid");
    const token = boundedText(input.token, 20, 4096, "campaign_push_token_invalid");
    const body = boundedText(input.body, 1, 2000, "campaign_push_body_invalid");
    const title = input.title == null ? undefined : boundedText(input.title, 1, 160, "campaign_push_title_invalid");
    if (!/^[a-z0-9][a-z0-9-]{1,126}[a-z0-9]$/i.test(projectId) || /\s/.test(accessToken)) {
      throw new Error("campaign_push_provider_config_invalid");
    }
    const endpoint = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`;
    let response: Response;
    try {
      response = await this.fetcher(endpoint, {
        method: "POST",
        signal: AbortSignal.timeout(this.timeoutMs),
        headers: {
          authorization: `Bearer ${accessToken}`,
          accept: "application/json",
          "content-type": "application/json",
        },
        body: JSON.stringify({ message: { token, notification: { ...(title ? { title } : {}), body } } }),
      });
    } catch {
      return { kind: "outcome_unknown", code: "fcm_transport_outcome_unknown" };
    }
    let payload: unknown = null;
    try {
      payload = await response.json();
    } catch {
      // Handled below without exposing provider body.
    }
    if (!response.ok) {
      return {
        kind: "failed",
        code: `fcm_http_${response.status}`,
        retryable: response.status === 429 || response.status >= 500,
      };
    }
    const reference = providerReference((payload as { name?: unknown } | null)?.name);
    if (!reference) return { kind: "outcome_unknown", code: "fcm_reference_missing" };
    return { kind: "delivered", providerReference: reference };
  }
}
