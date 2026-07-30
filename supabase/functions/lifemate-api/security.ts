import { ApiError } from "./validation.ts";

const windows = new Map<string, { count: number; resetAt: number }>();

export function enforceRateLimit(
  key: string,
  limit: number,
  windowMs: number,
  now = Date.now(),
): void {
  const current = windows.get(key);
  if (!current || current.resetAt <= now) {
    windows.set(key, { count: 1, resetAt: now + windowMs });
    return;
  }
  if (current.count >= limit) {
    throw new ApiError(
      429,
      "rate_limit_exceeded",
      "Too many requests. Try again later.",
    );
  }
  current.count += 1;

  if (windows.size > 2_000) {
    for (const [entryKey, entry] of windows) {
      if (entry.resetAt <= now) windows.delete(entryKey);
    }
  }
}

export function createToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

export function maskEmail(email: string): string {
  const [name, domain] = email.split("@");
  const visible = name.slice(0, Math.min(2, name.length));
  return `${visible}${
    "*".repeat(Math.max(2, name.length - visible.length))
  }@${domain}`;
}

export function createHmac(secret: string) {
  const secretBytes = new TextEncoder().encode(secret);
  let keyPromise: Promise<CryptoKey> | null = null;

  return async (value: string): Promise<string> => {
    keyPromise ??= crypto.subtle.importKey(
      "raw",
      secretBytes,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const signature = await crypto.subtle.sign(
      "HMAC",
      await keyPromise,
      new TextEncoder().encode(value),
    );
    return Array.from(new Uint8Array(signature))
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join("");
  };
}

export function timingSafeEqual(left: string, right: string): boolean {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  if (leftBytes.length !== rightBytes.length) return false;
  let diff = 0;
  for (let index = 0; index < leftBytes.length; index += 1) {
    diff |= leftBytes[index] ^ rightBytes[index];
  }
  return diff === 0;
}
