import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  type ClientErrorTelemetry,
  parseClientErrorTelemetry,
  parseProductTelemetry,
  type ProductTelemetry,
  safeValidationCode,
  SubjectTelemetryRateLimiter,
} from "./privacy_safe_event.ts";
import { persistProductActivity } from "./product_activity_persistence.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim().replace(/\/$/, "") ??
  "";
const publishableKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY")?.trim() ??
  Deno.env.get("SUPABASE_ANON_KEY")?.trim() ?? "";
const admission = new SubjectTelemetryRateLimiter();

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

  const subject = await authenticatedSubject(authorization);
  if (subject === null) {
    return json({ code: "unauthorized" }, 401);
  }
  if (!admission.allow(subject)) {
    return json({ code: "telemetry_rate_limited" }, 429, {
      "Retry-After": "60",
    });
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

  try {
    if (body.kind === "product") {
      const event: ProductTelemetry = parseProductTelemetry(body);
      try {
        const persistence = await persistProductActivity(event, {
          supabaseUrl,
          publishableKey,
          authorization,
        });
        // Log only bounded event classification. Never log authenticated
        // subject/account identifiers, Authorization, free text or raw payloads.
        console.info("LifeMate product activity accepted", {
          eventName: event.eventName,
          application: event.application,
          platform: event.platform,
          persistence,
        });
        return json({ accepted: true, eventId: event.eventId }, 202);
      } catch (_) {
        console.error("LifeMate product activity persistence failed", {
          eventName: event.eventName,
          application: event.application,
        });
        return json({ code: "product_activity_persistence_failed" }, 503);
      }
    }

    const event: ClientErrorTelemetry = parseClientErrorTelemetry(body);
    // Never log the authenticated subject, Authorization header, raw exception
    // message, stack trace, request body, health data, or account/person IDs.
    console.error("LifeMate client crash", event);
    return json({ accepted: true, eventId: event.eventId }, 202);
  } catch (error) {
    return json({ code: safeValidationCode(error) }, 400);
  }
});

async function authenticatedSubject(
  authorization: string,
): Promise<string | null> {
  try {
    const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { Authorization: authorization, apikey: publishableKey },
      signal: AbortSignal.timeout(5_000),
    });
    if (!response.ok) return null;
    const body: unknown = await response.json();
    if (!isRecord(body) || typeof body.id !== "string") return null;
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(body.id)
      ? body.id.toLowerCase()
      : null;
  } catch (_) {
    return null;
  }
}

function json(
  value: unknown,
  status: number,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, ...extraHeaders },
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
