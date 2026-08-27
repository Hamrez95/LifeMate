type EnvironmentReader = (name: string) => string | null | undefined;
type Fetcher = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export type DeliveryProviderResult =
  | { kind: "delivered"; providerReference: string }
  | { kind: "retryable"; code: string }
  | { kind: "permanent"; code: string }
  | { kind: "unknown"; code: string };

export type SmsDeliveryInput = {
  provider: string;
  receptor: string;
  message: string;
};

export type PushDeliveryInput = {
  provider: string;
  token: string;
  title: string | null;
  body: string;
};

type FcmServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

const encoder = new TextEncoder();
let cachedFcmToken: { token: string; expiresAt: number } | null = null;

function envRequired(
  name: string,
  readEnvironment: EnvironmentReader,
  minimum = 1,
): string {
  const value = (readEnvironment(name) ?? "").trim();
  if (value.length < minimum) throw new Error(`provider_configuration_missing:${name}`);
  return value;
}

function base64Url(bytes: Uint8Array): string {
  let raw = "";
  for (const byte of bytes) raw += String.fromCharCode(byte);
  return btoa(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64UrlText(value: string): string {
  return base64Url(encoder.encode(value));
}

function pemPkcs8(value: string): ArrayBuffer {
  const normalized = value
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
  return bytes.buffer as ArrayBuffer;
}

async function signServiceAccountJwt(account: FcmServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlText(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64UrlText(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: account.token_uri ?? "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemPkcs8(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

function readFcmServiceAccount(readEnvironment: EnvironmentReader): FcmServiceAccount {
  const raw = envRequired("LIFEMATE_FCM_SERVICE_ACCOUNT_JSON", readEnvironment, 20);
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("provider_configuration_missing:fcm_service_account_json");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("provider_configuration_missing:fcm_service_account_json");
  }
  const value = parsed as Record<string, unknown>;
  if (
    typeof value.project_id !== "string" || !/^[a-z0-9][a-z0-9-]{3,62}$/i.test(value.project_id) ||
    typeof value.client_email !== "string" || !value.client_email.includes("@") ||
    typeof value.private_key !== "string" || !value.private_key.includes("BEGIN PRIVATE KEY")
  ) {
    throw new Error("provider_configuration_missing:fcm_service_account_json");
  }
  return {
    project_id: value.project_id,
    client_email: value.client_email,
    private_key: value.private_key,
    token_uri: typeof value.token_uri === "string" && value.token_uri.startsWith("https://")
      ? value.token_uri
      : undefined,
  };
}

async function fcmAccessToken(
  account: FcmServiceAccount,
  fetcher: Fetcher,
): Promise<string> {
  if (cachedFcmToken && cachedFcmToken.expiresAt > Date.now() + 60_000) {
    return cachedFcmToken.token;
  }
  const tokenUri = account.token_uri ?? "https://oauth2.googleapis.com/token";
  let response: Response;
  try {
    response = await fetcher(tokenUri, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: await signServiceAccountJwt(account),
      }),
    });
  } catch {
    throw new Error("provider_auth_retryable");
  }
  if (!response.ok) {
    if (response.status === 408 || response.status === 429 || response.status >= 500) {
      throw new Error("provider_auth_retryable");
    }
    throw new Error("provider_configuration_missing:fcm_oauth");
  }
  const value = await response.json().catch(() => null) as Record<string, unknown> | null;
  const token = typeof value?.access_token === "string" ? value.access_token : "";
  const expiresIn = Number(value?.expires_in ?? 3600);
  if (!token || !Number.isFinite(expiresIn) || expiresIn < 60) {
    throw new Error("provider_auth_retryable");
  }
  cachedFcmToken = { token, expiresAt: Date.now() + Math.min(expiresIn, 3600) * 1000 };
  return token;
}

export async function sendSms(
  input: SmsDeliveryInput,
  fetcher: Fetcher = fetch,
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): Promise<DeliveryProviderResult> {
  if (input.provider !== "kavenegar") {
    return { kind: "permanent", code: "unsupported_provider" };
  }
  const apiKey = envRequired("LIFEMATE_KAVENEGAR_API_KEY", readEnvironment, 8);
  const baseUrl = (readEnvironment("LIFEMATE_KAVENEGAR_BASE_URL") ?? "https://api.kavenegar.com").trim();
  let base: URL;
  try {
    base = new URL(baseUrl);
  } catch {
    throw new Error("provider_configuration_missing:kavenegar_base_url");
  }
  if (base.protocol !== "https:") throw new Error("provider_configuration_missing:kavenegar_base_url");
  const url = new URL(`/v1/${encodeURIComponent(apiKey)}/sms/send.json`, base);
  const body = new URLSearchParams({ receptor: input.receptor, message: input.message });
  const sender = (readEnvironment("LIFEMATE_KAVENEGAR_SENDER") ?? "").trim();
  if (sender) body.set("sender", sender);

  let response: Response;
  try {
    response = await fetcher(url, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body,
    });
  } catch {
    return { kind: "unknown", code: "provider_outcome_unknown" };
  }
  if (response.status === 408 || response.status === 429 || response.status >= 500) {
    return { kind: "retryable", code: `provider_http_${response.status}` };
  }
  if (!response.ok) return { kind: "permanent", code: `provider_http_${response.status}` };
  const value = await response.json().catch(() => null) as Record<string, unknown> | null;
  const entries = Array.isArray(value?.entries) ? value.entries as Record<string, unknown>[] : [];
  const reference = entries.length > 0 && entries[0]?.messageid != null
    ? String(entries[0].messageid)
    : "";
  if (!reference) return { kind: "unknown", code: "provider_outcome_unknown" };
  return { kind: "delivered", providerReference: reference };
}

export async function sendPush(
  input: PushDeliveryInput,
  fetcher: Fetcher = fetch,
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): Promise<DeliveryProviderResult> {
  if (input.provider !== "fcm") {
    return { kind: "permanent", code: "unsupported_provider" };
  }
  let account: FcmServiceAccount;
  let accessToken: string;
  try {
    account = readFcmServiceAccount(readEnvironment);
    accessToken = await fcmAccessToken(account, fetcher);
  } catch (error) {
    const code = error instanceof Error ? error.message : "provider_configuration_missing";
    if (code === "provider_auth_retryable") return { kind: "retryable", code };
    return { kind: "permanent", code: "provider_configuration_missing" };
  }

  const url = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`;
  let response: Response;
  try {
    response = await fetcher(url, {
      method: "POST",
      headers: {
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: input.token,
          notification: {
            ...(input.title ? { title: input.title } : {}),
            body: input.body,
          },
        },
      }),
    });
  } catch {
    return { kind: "unknown", code: "provider_outcome_unknown" };
  }
  if (response.status === 408 || response.status === 429 || response.status >= 500) {
    return { kind: "retryable", code: `provider_http_${response.status}` };
  }
  const value = await response.json().catch(() => null) as Record<string, unknown> | null;
  if (!response.ok) {
    return { kind: "permanent", code: `provider_http_${response.status}` };
  }
  const name = typeof value?.name === "string" ? value.name : "";
  if (!name) return { kind: "unknown", code: "provider_outcome_unknown" };
  return { kind: "delivered", providerReference: name };
}

export function resetCampaignProviderCacheForTest(): void {
  cachedFcmToken = null;
}
