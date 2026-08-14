import { ApiError } from "./validation.ts";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Expose-Headers": "Retry-After",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

export function json(
  value: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, ...extraHeaders },
  });
}

export function problem(
  status: number,
  code: string,
  detail: string,
  correlationId?: string,
): Response {
  // Retry-After is deliberately conservative and coarse here. Distributed
  // admission control can use multiple window sizes, while clients only need a
  // safe minimum delay before attempting another bounded retry.
  const retryHeaders = status === 429 ? { "Retry-After": "60" } : {};
  return json(
    {
      type: "about:blank",
      title: code,
      status,
      code,
      detail,
      ...(correlationId ? { correlationId } : {}),
    },
    status,
    retryHeaders,
  );
}

export function safeError(error: unknown): Record<string, unknown> {
  if (error instanceof ApiError) {
    return { name: error.name, code: error.code, status: error.status };
  }
  if (error instanceof Error) {
    return { name: error.name, message: error.message.slice(0, 160) };
  }
  return { name: "UnknownError" };
}
