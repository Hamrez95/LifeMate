import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { json } from "./http.ts";
import {
  evaluatePlatformControl,
  parseControlKey,
  type PlatformControlContext,
} from "./platform_controls.ts";
import { createPlatformControlMutationRouteHandler } from "./platform_controls_mutation_routes.ts";
import { createPlatformControlStore } from "./platform_controls_service.ts";
import { ApiError } from "./validation.ts";

function parseBoolean(
  value: string | null,
  field: string,
): boolean | undefined {
  if (value == null || value === "") return undefined;
  if (value === "true") return true;
  if (value === "false") return false;
  throw new ApiError(
    400,
    "platform_control_query_invalid",
    `${field} must be true or false.`,
  );
}

function parseSegments(url: URL): string[] {
  const values = url.searchParams.getAll("segment");
  const unique = new Set<string>();
  for (const raw of values) {
    const value = raw.trim().toLowerCase();
    if (!value) continue;
    if (!/^[a-z0-9][a-z0-9._-]{0,63}$/.test(value)) {
      throw new ApiError(
        400,
        "platform_control_segment_invalid",
        "Segment key is invalid.",
      );
    }
    unique.add(value);
    if (unique.size > 20) {
      throw new ApiError(
        400,
        "platform_control_segments_too_many",
        "At most 20 segment keys are allowed.",
      );
    }
  }
  return [...unique];
}

function parseEvaluationContext(
  url: URL,
  accountId: string,
): PlatformControlContext {
  const requestedSubject = url.searchParams.get("subjectKey")?.trim();
  if (requestedSubject && requestedSubject !== accountId) {
    throw new ApiError(
      403,
      "platform_control_subject_forbidden",
      "Admin control evaluation may only use the authenticated account subject.",
    );
  }

  const productCode = url.searchParams.get("product")?.trim().toLowerCase() ||
    null;
  if (productCode && !/^[a-z0-9][a-z0-9._-]{0,63}$/.test(productCode)) {
    throw new ApiError(
      400,
      "platform_control_product_invalid",
      "Product code is invalid.",
    );
  }

  return {
    subjectKey: accountId,
    productCode,
    segmentKeys: parseSegments(url),
    beta: parseBoolean(url.searchParams.get("beta"), "beta"),
  };
}

export function createPlatformControlRouteHandler(databaseUrl: string) {
  const store = createPlatformControlStore(databaseUrl);
  const mutationHandler = createPlatformControlMutationRouteHandler(
    databaseUrl,
    store.invalidate,
  );

  return async function platformControlRouteHandler(input: {
    request: Request;
    path: string;
    accountId: string;
    admin: AdminCapabilitySnapshot;
    correlationId: string;
    origin: string | null;
  }): Promise<Response | null> {
    const { request, path, accountId, admin, origin } = input;

    const mutationResponse = await mutationHandler(input);
    if (mutationResponse) return mutationResponse;

    if (request.method === "GET" && path === "/api/v1/platform/controls") {
      requirePermission(admin, "platform.config.read");
      const items = await store.list();
      return json(
        {
          items,
          total: items.length,
          authoritative: "server",
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    const detailMatch = path.match(/^\/api\/v1\/platform\/controls\/([^/]+)$/);
    if (request.method === "GET" && detailMatch) {
      requirePermission(admin, "platform.config.read");
      const key = parseControlKey(decodeURIComponent(detailMatch[1]));
      const control = await store.get(key);
      if (!control) {
        throw new ApiError(
          404,
          "platform_control_not_found",
          "Platform control was not found.",
        );
      }
      return json(
        {
          key,
          definition: control.definition,
          rules: control.rules,
          authoritative: "server",
          security: {
            grantsPermission: false,
            grantsEntitlement: false,
          },
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    const match = path.match(
      /^\/api\/v1\/platform\/controls\/([^/]+)\/evaluate$/,
    );
    if (request.method === "GET" && match) {
      requirePermission(admin, "platform.config.read");
      const key = parseControlKey(decodeURIComponent(match[1]));
      const control = await store.get(key);
      if (!control) {
        throw new ApiError(
          404,
          "platform_control_not_found",
          "Platform control was not found.",
        );
      }
      const context = parseEvaluationContext(new URL(request.url), accountId);
      const evaluation = await evaluatePlatformControl(
        control.definition,
        control.rules,
        context,
      );
      return json(
        {
          key,
          valueType: control.definition.valueType,
          definitionVersion: control.definition.version,
          evaluation,
          context: {
            productCode: context.productCode ?? null,
            segmentKeys: context.segmentKeys ?? [],
            beta: context.beta ?? false,
          },
          authoritative: "server",
          security: {
            grantsPermission: false,
            grantsEntitlement: false,
          },
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    return null;
  };
}
