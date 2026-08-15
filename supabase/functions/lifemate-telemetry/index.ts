import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  type ClientErrorTelemetry,
  parseClientErrorTelemetry,
  safeValidationCode,
} from "./privacy_safe_event.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const publishableKey =
  Deno.env.get("SUPABASE_PUBLISHABLE_KEY")?.trim() ??
  Deno.env.get("SUPABASE_ANON_KEY")?.trim() ?? "";

if (!/^https:\/\//.test(supabaseUrl) || publishableKey.length < 20) {
  throw new Error("LifeMate telemetry runtime configuration is incomplete.");
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ code: "method_not_allowed" }, 405);
  }

  const authorization = request.headers.get("authorization")?.trim() ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return json({ code: "unauthorized" }, 401);
  }

  const authenticated = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { Authorization: authorization, apikey: publishableKey },
    signal: AbortSignal.timeout(5_000),
  }).then((response) => response.ok).catch(() => false);
  if (!authenticated) {
    return json({ code: "unauthorized" }, 401);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch (_) {
    return json({ code: "invalid_json" }, 400);
  }
  if (!isRecord(body)) {
    return json({ code: "invalid_payload" }, 400);
  }

  let event: ClientErrorTelemetry;
  try {
    event = parseClientErrorTelemetry(body);
  } catch (error) {
    return json({ code: safeValidationCode(error) }, 400);
  }

  // Never log the authenticated subject, Authorization header, raw exception
  // message, stack trace, request body, health data, or account/person IDs.
  console.error("LifeMate client crash", event);
  return json({ accepted: true, eventId: event.eventId }, 202);
});

function json(value: unknown, status: number): Response {
  return new Response(JSON.stringify(value), { status, headers: corsHeaders });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
