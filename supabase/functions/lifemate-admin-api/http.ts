import { ApiError } from "./validation.ts";

const baseHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
};

export function assertAllowedOrigin(
  request: Request,
  allowedOrigins: ReadonlySet<string>,
): string | null {
  const origin = request.headers.get("origin");
  if (!origin) return null;
  if (!allowedOrigins.has(origin)) {
    throw new ApiError(403, "origin_denied", "Request origin is not allowed.");
  }
  return origin;
}

export function responseHeaders(origin: string | null): HeadersInit {
  return {
    ...baseHeaders,
    ...(origin
      ? {
        "access-control-allow-origin": origin,
        "access-control-allow-credentials": "true",
        vary: "Origin",
      }
      : {}),
  };
}

export function preflight(origin: string): Response {
  return new Response(null, {
    status: 204,
    headers: {
      ...responseHeaders(origin),
      "access-control-allow-methods": "GET,POST,OPTIONS",
      "access-control-allow-headers": "authorization,content-type,idempotency-key",
      "access-control-max-age": "600",
    },
  });
}

export function json(
  value: unknown,
  status: number,
  origin: string | null,
): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: responseHeaders(origin),
  });
}

export function problem(
  status: number,
  code: string,
  message: string,
  correlationId: string,
  origin: string | null,
): Response {
  return json(
    {
      type: `https://lifemate.app/problems/${code}`,
      title: message,
      status,
      code,
      correlationId,
    },
    status,
    origin,
  );
}

export function safeError(error: unknown): Record<string, unknown> {
  if (!error || typeof error !== "object") return { kind: typeof error };
  const value = error as Record<string, unknown>;
  return {
    name: typeof value.name === "string" ? value.name.slice(0, 80) : "Error",
    code: typeof value.code === "string" ? value.code.slice(0, 40) : undefined,
  };
}
