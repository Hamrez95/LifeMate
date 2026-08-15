import "jsr:@supabase/functions-js/edge-runtime.d.ts";

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

export type ClientErrorTelemetry = {
  eventId: string;
  application: "wellmate" | "caremate";
  releaseVersion: string;
  platform: "android" | "ios" | "web" | "windows" | "macos" | "linux" | "unknown";
  source: "flutter_framework" | "platform_dispatcher" | "zone";
  errorType: string;
  stackFingerprint: string;
  fatal: boolean;
};

export function parseClientErrorTelemetry(input: Record<string, unknown>): ClientErrorTelemetry {
  const allowed = new Set([
    "eventId",
    "application",
    "releaseVersion",
    "platform",
    "source",
    "errorType",
    "stackFingerprint",
    "fatal",
  ]);
  for (const key of Object.keys(input)) {
    if (!allowed.has(key)) invalid("client_telemetry_field_forbidden");
  }

  const eventId = stringValue(input.eventId, "event_id_invalid");
  const application = stringValue(input.application, "application_invalid");
  const releaseVersion = stringValue(input.releaseVersion, "release_version_invalid");
  const platform = stringValue(input.platform, "platform_invalid");
  const source = stringValue(input.source, "source_invalid");
  const errorType = stringValue(input.errorType, "error_type_invalid");
  const stackFingerprint = stringValue(input.stackFingerprint, "stack_fingerprint_invalid").toLowerCase();

  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(eventId)) invalid("event_id_invalid");
  if (application !== "wellmate" && application !== "caremate") invalid("application_invalid");
  if (!/^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$/.test(releaseVersion)) invalid("release_version_invalid");
  if (!["android", "ios", "web", "windows", "macos", "linux", "unknown"].includes(platform)) invalid("platform_invalid");
  if (!["flutter_framework", "platform_dispatcher", "zone"].includes(source)) invalid("source_invalid");
  if (!/^[A-Za-z_][A-Za-z0-9_.]{0,79}$/.test(errorType)) invalid("error_type_invalid");
  if (!/^[0-9a-f]{16}$/.test(stackFingerprint)) invalid("stack_fingerprint_invalid");
  if (typeof input.fatal !== "boolean") invalid("fatal_invalid");

  return {
    eventId,
    application: application as ClientErrorTelemetry["application"],
    releaseVersion,
    platform: platform as ClientErrorTelemetry["platform"],
    source: source as ClientErrorTelemetry["source"],
    errorType,
    stackFingerprint,
    fatal: input.fatal,
  };
}

function json(value: unknown, status: number): Response {
  return new Response(JSON.stringify(value), { status, headers: corsHeaders });
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function stringValue(value: unknown, code: string): string {
  if (typeof value !== "string") invalid(code);
  return value;
}
function invalid(code: string): never {
  throw new Error(code);
}
function safeValidationCode(error: unknown): string {
  const message = error instanceof Error ? error.message : "invalid_payload";
  return /^[a-z0-9_]{3,48}$/.test(message) ? message : "invalid_payload";
}
