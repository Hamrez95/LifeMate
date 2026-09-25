import { ApiError, requireUuid } from "./validation.ts";

export type GiftTestFinalizePayload = {
  giftIntentId: string;
  transactionId: string;
  claimTokenHash: string;
  claimTtlHours: number;
};

async function objectBody(request: Request): Promise<Record<string, unknown>> {
  try {
    const value: unknown = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("invalid");
    }
    return value as Record<string, unknown>;
  } catch {
    throw new ApiError(
      400,
      "invalid_request",
      "Request body must be a JSON object.",
    );
  }
}

export async function parseGiftTestFinalizePayload(
  request: Request,
): Promise<GiftTestFinalizePayload> {
  const body = await objectBody(request);
  const claimTokenHash = String(body.claimTokenHash ?? "").trim().toLowerCase();
  if (!/^[0-9a-f]{64,128}$/.test(claimTokenHash)) {
    throw new ApiError(
      400,
      "gift_claim_token_hash_invalid",
      "claimTokenHash is invalid.",
    );
  }
  const claimTtlHours = body.claimTtlHours == null
    ? 168
    : Number(body.claimTtlHours);
  if (
    !Number.isInteger(claimTtlHours) || claimTtlHours < 1 || claimTtlHours > 720
  ) {
    throw new ApiError(
      400,
      "gift_claim_ttl_invalid",
      "claimTtlHours must be between 1 and 720.",
    );
  }
  return {
    giftIntentId: requireUuid(String(body.giftIntentId ?? ""), "giftIntentId"),
    transactionId: requireUuid(
      String(body.transactionId ?? ""),
      "transactionId",
    ),
    claimTokenHash,
    claimTtlHours,
  };
}

function stable(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  return `{${
    Object.entries(value as Record<string, unknown>).sort(([a], [b]) =>
      a.localeCompare(b)
    ).map(([key, item]) => `${JSON.stringify(key)}:${stable(item)}`).join(",")
  }}`;
}

export async function hashGiftTestFinalizePayload(
  payload: GiftTestFinalizePayload,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(stable(payload)),
  );
  return [...new Uint8Array(digest)].map((value) =>
    value.toString(16).padStart(2, "0")
  ).join("");
}
