import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import postgres from "postgres";
import { createClient } from "supabase";

import { loadWorkforceAuthConfig } from "./runtime_config.ts";

const config = await loadWorkforceAuthConfig();
const sql = postgres(config.databaseUrl, {
  max: 5,
  idle_timeout: 10,
  connect_timeout: 10,
  prepare: false,
});
const publicAuth = createClient(config.supabaseUrl, config.anonKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
});
const adminAuth = createClient(config.supabaseUrl, config.serviceRoleKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
});

const usernamePattern = /^[a-z0-9][a-z0-9._-]{2,31}$/;

type Payload = Record<string, unknown>;

function normalizeUsername(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  return usernamePattern.test(normalized) ? normalized : null;
}

function headers(origin: string): HeadersInit {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "private, no-store",
    "Content-Type": "application/json; charset=utf-8",
    Vary: "Origin",
    "X-Content-Type-Options": "nosniff",
  };
}

function json(
  origin: string,
  status: number,
  payload: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: headers(origin),
  });
}

function allowedOrigin(request: Request): string | null {
  const origin = request.headers.get("origin")?.trim() ?? "";
  return origin && config.allowedOrigins.has(origin) ? origin : null;
}

function clientAddress(request: Request): string {
  return (
    request.headers.get("cf-connecting-ip") ??
      request.headers.get("x-real-ip") ??
      request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      "unknown"
  ).slice(0, 128);
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

async function consumeAttempt(
  request: Request,
  kind: string,
  username: string,
  limit: number,
) {
  const fingerprint = await sha256(
    `${kind}|${clientAddress(request)}|${username}`,
  );
  const rows = await sql`
    select admin.consume_workforce_auth_attempt(${fingerprint}, ${limit}, 600) as allowed
  `;
  return rows[0]?.allowed === true;
}

async function body(request: Request): Promise<Payload | null> {
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > 16_384) return null;
  try {
    const parsed: unknown = await request.json();
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Payload
      : null;
  } catch {
    return null;
  }
}

async function genericAuthDelay() {
  await new Promise((resolve) =>
    setTimeout(resolve, 180 + Math.floor(Math.random() * 90))
  );
}

async function accessState(
  username: string,
): Promise<"mfa_required" | "pending_role"> {
  const rows = await sql`
    select
      m.status,
      exists (
        select 1
        from admin.member_roles mr
        join admin.roles r on r.id=mr.role_id
        where mr.account_id=m.account_id
          and r.status='Active'
          and mr.revoked_at_utc is null
          and mr.starts_at_utc <= now()
          and (mr.expires_at_utc is null or mr.expires_at_utc > now())
      ) as has_role
    from admin.staff_profiles sp
    join admin.members m on m.account_id=sp.account_id
    where lower(sp.username)=${username}
    limit 1
  `;
  const row = rows[0];
  if (row?.status !== "Active" || row?.has_role !== true) {
    return "pending_role";
  }
  // Authentication never grants Admin access on its own. Every authorized
  // workforce identity, including Founder, must elevate the Supabase session
  // to AAL2 before the Admin API can be used.
  return "mfa_required";
}

async function sessionResponse(
  origin: string,
  username: string,
  email: string,
  password: string,
): Promise<Response> {
  const { data, error } = await publicAuth.auth.signInWithPassword({
    email,
    password,
  });
  if (error || !data.session) {
    await genericAuthDelay();
    return json(origin, 401, { ok: false, code: "invalid_credentials" });
  }

  return json(origin, 200, {
    ok: true,
    access_state: await accessState(username),
    session: {
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
      expires_at: data.session.expires_at ?? null,
      expires_in: data.session.expires_in,
      token_type: data.session.token_type,
    },
  });
}

async function login(
  request: Request,
  origin: string,
  payload: Payload,
): Promise<Response> {
  const username = normalizeUsername(payload.username);
  const password = typeof payload.password === "string" ? payload.password : "";
  if (!username || password.length < 1 || password.length > 256) {
    await genericAuthDelay();
    return json(origin, 401, { ok: false, code: "invalid_credentials" });
  }

  if (!(await consumeAttempt(request, "login", username, 8))) {
    return json(origin, 429, { ok: false, code: "try_again_later" });
  }

  const identityRows = await sql`
    select admin.resolve_workforce_auth_subject(${username}) as auth_user_id
  `;
  const authUserId = identityRows[0]?.auth_user_id;
  if (typeof authUserId !== "string") {
    await genericAuthDelay();
    return json(origin, 401, { ok: false, code: "invalid_credentials" });
  }

  const { data: userData, error: userError } = await adminAuth.auth.admin
    .getUserById(authUserId);
  const email = userData.user?.email;
  if (userError || !email) {
    await genericAuthDelay();
    return json(origin, 401, { ok: false, code: "invalid_credentials" });
  }

  return await sessionResponse(origin, username, email, password);
}

async function activateFounder(
  request: Request,
  origin: string,
  payload: Payload,
): Promise<Response> {
  const username = normalizeUsername(payload.username);
  const password = typeof payload.password === "string" ? payload.password : "";
  const activationCode = typeof payload.activationCode === "string"
    ? payload.activationCode.trim()
    : "";

  if (
    !username || password.length < 6 || password.length > 128 ||
    activationCode.length < 8 || activationCode.length > 128
  ) {
    await genericAuthDelay();
    return json(origin, 400, { ok: false, code: "invalid_activation" });
  }

  if (!(await consumeAttempt(request, "founder_activation", username, 5))) {
    return json(origin, 429, { ok: false, code: "try_again_later" });
  }

  const tokenHash = await sha256(activationCode);
  const rows = await sql`
    select admin.resolve_founder_password_activation(${username}, ${tokenHash}) as auth_user_id
  `;
  const authUserId = rows[0]?.auth_user_id;
  if (typeof authUserId !== "string") {
    await genericAuthDelay();
    return json(origin, 401, { ok: false, code: "invalid_activation" });
  }

  const { data: userData, error: userError } = await adminAuth.auth.admin
    .getUserById(authUserId);
  const email = userData.user?.email;
  if (userError || !email) {
    return json(origin, 503, { ok: false, code: "activation_unavailable" });
  }

  const { error: updateError } = await adminAuth.auth.admin.updateUserById(
    authUserId,
    { password },
  );
  if (updateError) {
    return json(origin, 503, { ok: false, code: "activation_unavailable" });
  }

  const consumeRows = await sql`
    select admin.consume_founder_password_activation(${username}, ${tokenHash}) as consumed
  `;
  if (consumeRows[0]?.consumed !== true) {
    return json(origin, 409, { ok: false, code: "activation_already_used" });
  }

  return await sessionResponse(origin, username, email, password);
}

Deno.serve(async (request: Request) => {
  const origin = allowedOrigin(request);
  if (!origin) {
    return new Response(JSON.stringify({ ok: false, code: "origin_denied" }), {
      status: 403,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
      },
    });
  }

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: headers(origin) });
  }
  if (request.method !== "POST") {
    return json(origin, 405, { ok: false, code: "method_not_allowed" });
  }

  try {
    const payload = await body(request);
    if (!payload) {
      return json(origin, 400, { ok: false, code: "invalid_request" });
    }
    if (payload.action === "login") {
      return await login(request, origin, payload);
    }
    if (payload.action === "activate_founder") {
      return await activateFounder(request, origin, payload);
    }
    // Workforce access is invite-only/default-deny. The unauthenticated edge
    // boundary must never create a new Auth user or admin.members row.
    return json(origin, 400, { ok: false, code: "invalid_action" });
  } catch {
    return json(origin, 503, { ok: false, code: "auth_service_unavailable" });
  }
});
