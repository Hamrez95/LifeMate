import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { authenticate, requireAal2 } from "./auth.ts";
import { requirePermission } from "./authorization.ts";
import { isPostgresUnavailable } from "./database_client.ts";
import {
  assertAllowedOrigin,
  json,
  preflight,
  problem,
  safeError,
} from "./http.ts";
import { loadRuntimeConfig } from "./runtime_config.ts";
import { createAdminStore } from "./store.ts";
import {
  ApiError,
  boundedInteger,
  normalizePath,
  requireIdempotencyKey,
} from "./validation.ts";

const config = await loadRuntimeConfig();
const store = createAdminStore(config.databaseUrl);

Deno.serve(async (request: Request) => {
  const correlationId = crypto.randomUUID();
  const path = normalizePath(new URL(request.url).pathname);
  let origin: string | null = null;

  try {
    origin = assertAllowedOrigin(request, config.allowedOrigins);
    if (request.method === "OPTIONS") {
      if (!origin) {
        throw new ApiError(
          403,
          "origin_denied",
          "Request origin is not allowed.",
        );
      }
      return preflight(origin);
    }

    if (request.method === "GET" && path === "/health") {
      await store.health();
      return json(
        {
          status: "ok",
          service: "lifemate-admin-api",
          database: "ready",
          version: config.releaseVersion,
        },
        200,
        origin,
      );
    }

    const principal = await authenticate(
      request,
      config.supabaseUrl,
      config.publishableKey,
    );
    requireAal2(principal);
    const accountId = await store.resolveAccountId(principal.providerSubject);

    if (request.method === "POST" && path === "/api/v1/bootstrap") {
      if (
        !config.bootstrapAuthSubject ||
        principal.providerSubject !== config.bootstrapAuthSubject
      ) {
        throw new ApiError(
          403,
          "admin_bootstrap_denied",
          "Admin bootstrap is not permitted.",
        );
      }
      const idempotencyKey = requireIdempotencyKey(request);
      const result = await store.bootstrapFounder(
        accountId,
        correlationId,
        idempotencyKey,
      );
      return json(
        {
          bootstrapped: true,
          created: result.created,
          admin: await store.getSnapshot(accountId),
        },
        result.created ? 201 : 200,
        origin,
      );
    }

    const admin = await store.getSnapshot(accountId);

    if (request.method === "GET" && path === "/api/v1/me") {
      return json({ admin }, 200, origin);
    }

    if (request.method === "GET" && path === "/api/v1/audit") {
      requirePermission(admin, "security.audit.read");
      const url = new URL(request.url);
      const limit = boundedInteger(url.searchParams.get("limit"), 50, 1, 200);
      return json({ events: await store.listAudit(limit) }, 200, origin);
    }

    throw new ApiError(
      404,
      "route_not_found",
      "Admin API route was not found.",
    );
  } catch (error) {
    if (error instanceof ApiError) {
      return problem(
        error.status,
        error.code,
        error.message,
        correlationId,
        origin,
      );
    }
    if (isPostgresUnavailable(error)) {
      console.warn("LifeMate Admin database temporarily unavailable", {
        correlationId,
        method: request.method,
        path,
        ...safeError(error),
      });
      return problem(
        503,
        "database_busy",
        "Database is temporarily unavailable.",
        correlationId,
        origin,
      );
    }
    console.error("Unhandled LifeMate Admin API error", {
      correlationId,
      method: request.method,
      path,
      ...safeError(error),
    });
    return problem(
      500,
      "internal_error",
      "The request could not be completed.",
      correlationId,
      origin,
    );
  }
});
