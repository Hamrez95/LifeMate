import { ApiError } from "./validation.ts";

export type AdminPrincipal = {
  providerSubject: string;
  email: string | null;
  aal: "aal1" | "aal2";
};

type TokenClaims = {
  sub?: unknown;
  aal?: unknown;
};

function decodeBase64Url(value: string): string {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  try {
    return atob(padded);
  } catch {
    throw new ApiError(
      401,
      "invalid_session",
      "Authentication session is invalid.",
    );
  }
}

export function readVerifiedSessionClaims(
  token: string,
  verifiedUserId: string,
): { subject: string; aal: "aal1" | "aal2" } {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new ApiError(
      401,
      "invalid_session",
      "Authentication session is invalid.",
    );
  }

  let claims: TokenClaims;
  try {
    claims = JSON.parse(decodeBase64Url(parts[1])) as TokenClaims;
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(
      401,
      "invalid_session",
      "Authentication session is invalid.",
    );
  }

  if (claims.sub !== verifiedUserId) {
    throw new ApiError(
      401,
      "invalid_session",
      "Authentication session is invalid.",
    );
  }
  const aal = claims.aal === "aal2" ? "aal2" : "aal1";
  return { subject: verifiedUserId, aal };
}

export async function authenticate(
  request: Request,
  supabaseUrl: string,
  publishableKey: string,
): Promise<AdminPrincipal> {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ") || authorization.length > 4_096) {
    throw new ApiError(
      401,
      "authorization_missing",
      "Authentication is required.",
    );
  }
  const token = authorization.slice("Bearer ".length).trim();
  if (!token) {
    throw new ApiError(
      401,
      "authorization_missing",
      "Authentication is required.",
    );
  }

  let response: Response;
  try {
    response = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        Authorization: `Bearer ${token}`,
        apikey: publishableKey,
      },
      signal: AbortSignal.timeout(10_000),
    });
  } catch {
    throw new ApiError(
      503,
      "identity_provider_unavailable",
      "Authentication service is temporarily unavailable.",
    );
  }

  if (!response.ok) {
    throw new ApiError(
      401,
      "invalid_session",
      "Authentication session is invalid.",
    );
  }
  const user = await response.json();
  if (!user?.id || typeof user.id !== "string") {
    throw new ApiError(
      401,
      "invalid_session",
      "Authentication session is invalid.",
    );
  }

  // The same bearer token was just verified by Supabase Auth. Reading its AAL claim
  // here does not replace signature verification; it lets the Admin API enforce MFA
  // on the exact token that Auth accepted.
  const claims = readVerifiedSessionClaims(token, user.id);
  return {
    providerSubject: claims.subject,
    email: typeof user.email === "string" ? user.email.toLowerCase() : null,
    aal: claims.aal,
  };
}

export function requireAal2(principal: AdminPrincipal): void {
  if (principal.aal === "aal2") return;

  throw new ApiError(
    403,
    "mfa_required",
    "Multi-factor authentication is required for Command Center access.",
  );
}
