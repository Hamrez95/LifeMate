export type MarketingPublishInput = {
  providerCode: string;
  publishText: string;
  assetRefs: string[];
  credentialSecret: string;
};

export type MarketingPublishResult =
  | { kind: "published"; providerPostRef: string }
  | { kind: "rejected"; code: string }
  | { kind: "unknown"; code: string };

type FetchLike = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

type TelegramCredential = { botToken: string; chatId: string };

function parseTelegramCredential(value: string): TelegramCredential | null {
  try {
    const parsed = JSON.parse(value) as Record<string, unknown>;
    const botToken = typeof parsed.botToken === "string" ? parsed.botToken.trim() : "";
    const chatId = typeof parsed.chatId === "string" ? parsed.chatId.trim() : "";
    if (!/^\d{5,12}:[A-Za-z0-9_-]{20,128}$/.test(botToken)) return null;
    if (!/^(@[A-Za-z0-9_]{5,32}|-?\d{1,20})$/.test(chatId)) return null;
    return { botToken, chatId };
  } catch {
    return null;
  }
}

export async function publishMarketingContent(
  input: MarketingPublishInput,
  fetchImpl: FetchLike = fetch,
): Promise<MarketingPublishResult> {
  if (input.providerCode !== "telegram") {
    return { kind: "rejected", code: "provider_adapter_not_ready" };
  }
  if (!input.publishText || input.publishText.length > 4096) {
    return { kind: "rejected", code: "publish_text_invalid" };
  }
  if (input.assetRefs.length > 0) {
    return { kind: "rejected", code: "telegram_asset_publish_not_ready" };
  }

  const credential = parseTelegramCredential(input.credentialSecret);
  if (!credential) return { kind: "rejected", code: "provider_configuration_invalid" };

  try {
    const response = await fetchImpl(
      `https://api.telegram.org/bot${credential.botToken}/sendMessage`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          chat_id: credential.chatId,
          text: input.publishText,
        }),
      },
    );

    if (response.status >= 400 && response.status < 500) {
      return { kind: "rejected", code: `provider_rejected_${response.status}` };
    }
    if (!response.ok) {
      return { kind: "unknown", code: `provider_ambiguous_${response.status}` };
    }

    let body: unknown;
    try {
      body = await response.json();
    } catch {
      return { kind: "unknown", code: "provider_response_invalid" };
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return { kind: "unknown", code: "provider_response_invalid" };
    }
    const payload = body as Record<string, unknown>;
    if (payload.ok !== true || !payload.result || typeof payload.result !== "object" || Array.isArray(payload.result)) {
      return { kind: "rejected", code: "provider_rejected" };
    }
    const messageId = (payload.result as Record<string, unknown>).message_id;
    if (!Number.isInteger(messageId)) {
      return { kind: "unknown", code: "provider_reference_missing" };
    }
    return { kind: "published", providerPostRef: `telegram:${messageId}` };
  } catch {
    return { kind: "unknown", code: "provider_request_outcome_unknown" };
  }
}
