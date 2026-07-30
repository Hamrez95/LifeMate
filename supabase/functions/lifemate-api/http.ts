import { ApiError } from "./validation.ts";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

export function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: corsHeaders,
  });
}

export function problem(
  status: number,
  code: string,
  detail: string,
  correlationId?: string,
): Response {
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
