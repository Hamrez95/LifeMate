const encoder = new TextEncoder();

export type IdentityLinkTokenInput = {
  provider: string;
  issuer: string;
  subject: string;
  keyVersion: number;
};

export type IdentityLinkKey = {
  secret: string;
  keyVersion: number;
};

export type IdentityLinkKeySet = {
  active: IdentityLinkKey;
  previous: IdentityLinkKey | null;
};

type EnvironmentReader = (name: string) => string | null | undefined;

function requiredSegment(
  name: string,
  value: string,
  maximumLength: number,
): string {
  const normalized = value.trim();
  if (!normalized || normalized.length > maximumLength) {
    throw new Error(`${name} is invalid.`);
  }
  return normalized;
}

function requiredKeyVersion(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 65535) {
    throw new Error("Identity-link key version is invalid.");
  }
  return value;
}

function toHex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Derives a deterministic opaque lookup token for an external authentication
 * subject. The HMAC key must live outside PostgreSQL/database backups.
 *
 * The raw provider subject is never returned and must not be persisted by new
 * identity-link storage. Key version is part of the authenticated message so a
 * rotation can run old/new versions side-by-side during a bounded migration.
 */
export async function deriveIdentityLinkToken(
  secret: string,
  input: IdentityLinkTokenInput,
): Promise<string> {
  const keyBytes = encoder.encode(secret);
  if (keyBytes.byteLength < 32) {
    throw new Error(
      "Identity-link key must contain at least 32 UTF-8 bytes and must be stored outside PostgreSQL.",
    );
  }

  const provider = requiredSegment("provider", input.provider, 80);
  const issuer = requiredSegment("issuer", input.issuer, 255);
  const subject = requiredSegment("subject", input.subject, 512);
  const keyVersion = requiredKeyVersion(input.keyVersion);

  // JSON with fixed key order avoids delimiter ambiguity while keeping the
  // canonical message portable across runtimes.
  const canonical = JSON.stringify({
    version: keyVersion,
    provider,
    issuer,
    subject,
  });
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(canonical),
  );
  return toHex(digest);
}

export function readIdentityLinkKeyFromEnvironment(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): IdentityLinkKey {
  const secret = readEnvironment("LIFEMATE_IDENTITY_LINK_KEY") ?? "";
  const keyVersionRaw = readEnvironment("LIFEMATE_IDENTITY_LINK_KEY_VERSION") ??
    "";
  if (encoder.encode(secret).byteLength < 32) {
    throw new Error(
      "LIFEMATE_IDENTITY_LINK_KEY must be configured as an external runtime secret with at least 32 UTF-8 bytes.",
    );
  }
  if (!/^\d+$/.test(keyVersionRaw)) {
    throw new Error("LIFEMATE_IDENTITY_LINK_KEY_VERSION must be configured.");
  }
  return {
    secret,
    keyVersion: requiredKeyVersion(Number(keyVersionRaw)),
  };
}

/**
 * Loads one bounded previous identity-link key for a rolling rotation window.
 * The previous key is optional, but its secret/version must be configured as a
 * pair and its version must differ from the active version. Both secrets remain
 * external runtime configuration; PostgreSQL stores only keyed token digests.
 */
export function readIdentityLinkKeySetFromEnvironment(
  readEnvironment: EnvironmentReader = (name) => Deno.env.get(name),
): IdentityLinkKeySet {
  const active = readIdentityLinkKeyFromEnvironment(readEnvironment);
  const previousSecret =
    readEnvironment("LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY") ?? "";
  const previousVersionRaw =
    readEnvironment("LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY_VERSION") ?? "";
  const hasPreviousSecret = previousSecret.length > 0;
  const hasPreviousVersion = previousVersionRaw.trim().length > 0;

  if (hasPreviousSecret !== hasPreviousVersion) {
    throw new Error(
      "LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY and LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY_VERSION must be configured together.",
    );
  }
  if (!hasPreviousSecret) {
    return { active, previous: null };
  }
  if (encoder.encode(previousSecret).byteLength < 32) {
    throw new Error(
      "LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY must contain at least 32 UTF-8 bytes and must be stored outside PostgreSQL.",
    );
  }
  if (!/^\d+$/.test(previousVersionRaw)) {
    throw new Error(
      "LIFEMATE_IDENTITY_LINK_PREVIOUS_KEY_VERSION must be configured as an integer.",
    );
  }
  const previous = {
    secret: previousSecret,
    keyVersion: requiredKeyVersion(Number(previousVersionRaw)),
  };
  if (previous.keyVersion === active.keyVersion) {
    throw new Error(
      "Previous identity-link key version must differ from the active key version.",
    );
  }
  return { active, previous };
}
