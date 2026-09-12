import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import { getAdminSql } from "./database_client.ts";
import { json } from "./http.ts";
import { ApiError, requireIdempotencyKey } from "./validation.ts";

type Context = {
  request: Request;
  path: string;
  accountId: string;
  admin: AdminCapabilitySnapshot;
  correlationId: string;
  origin: string | null;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const productPattern = /^[a-z][a-z0-9_-]{1,39}$/;
const statuses = new Set(["Submitted", "Acknowledged", "Triaged", "Resolved"]);
const kinds = new Set([
  "Feedback",
  "Nps",
  "BugReport",
  "FeatureRequest",
  "Advocacy",
]);
const actions = new Set([
  "Acknowledge",
  "Triage",
  "Resolve",
  "LinkSupport",
  "LinkProductIssue",
]);

function optionalEnum(
  url: URL,
  key: string,
  allowed: Set<string>,
): string | null {
  const raw = url.searchParams.get(key)?.trim() ?? "";
  if (!raw) return null;
  if (!allowed.has(raw)) {
    throw new ApiError(
      400,
      `feedback_${key}_invalid`,
      `${key} filter is invalid.`,
    );
  }
  return raw;
}

function optionalProduct(url: URL): string | null {
  const raw = url.searchParams.get("product")?.trim().toLowerCase() ?? "";
  if (!raw) return null;
  if (!productPattern.test(raw)) {
    throw new ApiError(
      400,
      "feedback_product_invalid",
      "product filter is invalid.",
    );
  }
  return raw;
}

function optionalVersion(url: URL): string | null {
  const raw = url.searchParams.get("appVersion")?.trim() ?? "";
  if (!raw) return null;
  if (raw.length > 80) {
    throw new ApiError(
      400,
      "feedback_app_version_invalid",
      "appVersion filter is invalid.",
    );
  }
  return raw;
}

function boundedInt(
  url: URL,
  key: string,
  fallback: number,
  min: number,
  max: number,
): number {
  const raw = url.searchParams.get(key);
  if (raw === null) return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new ApiError(
      400,
      `feedback_${key}_invalid`,
      `${key} must be between ${min} and ${max}.`,
    );
  }
  return value;
}

async function readJsonObject(
  request: Request,
): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw new ApiError(
      400,
      "feedback_payload_invalid",
      "Request body must be valid JSON.",
    );
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new ApiError(
      400,
      "feedback_payload_invalid",
      "Request body must be a JSON object.",
    );
  }
  return body as Record<string, unknown>;
}

function stringField(
  body: Record<string, unknown>,
  key: string,
  min: number,
  max: number,
): string {
  const value = typeof body[key] === "string" ? body[key].trim() : "";
  if (value.length < min || value.length > max) {
    throw new ApiError(400, `feedback_${key}_invalid`, `${key} is invalid.`);
  }
  return value;
}

function optionalUuid(
  body: Record<string, unknown>,
  key: string,
): string | null {
  const raw = body[key];
  if (raw === undefined || raw === null || raw === "") return null;
  if (typeof raw !== "string" || !uuidPattern.test(raw)) {
    throw new ApiError(
      400,
      `feedback_${key}_invalid`,
      `${key} must be a UUID.`,
    );
  }
  return raw;
}

function optionalReference(body: Record<string, unknown>): string | null {
  const raw = body.productIssueRef;
  if (raw === undefined || raw === null || raw === "") return null;
  if (typeof raw !== "string") {
    throw new ApiError(
      400,
      "feedback_product_issue_ref_invalid",
      "productIssueRef is invalid.",
    );
  }
  const value = raw.trim();
  if (!value || value.length > 160 || /^(https?:\/\/|www\.)/i.test(value)) {
    throw new ApiError(
      400,
      "feedback_product_issue_ref_invalid",
      "productIssueRef must be an opaque internal reference.",
    );
  }
  return value;
}

async function sha256(input: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(input));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((value) =>
    value.toString(16).padStart(2, "0")
  ).join("");
}

function resultStatus(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "feedback_workflow_unavailable",
      "Feedback workflow returned an invalid status.",
    );
  }
  if (status >= 400) {
    throw new ApiError(
      status,
      typeof result.code === "string"
        ? result.code
        : "feedback_workflow_failed",
      "Feedback workflow was not completed.",
    );
  }
  return status;
}

export function createFeedbackAdminRouteHandler(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return async function handleFeedbackAdminRoute(
    context: Context,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, origin } = context;

    if (request.method === "GET" && path === "/api/v1/feedback") {
      requirePermission(admin, "feedback.read");
      const url = new URL(request.url);
      const status = optionalEnum(url, "status", statuses);
      const kind = optionalEnum(url, "kind", kinds);
      const product = optionalProduct(url);
      const appVersion = optionalVersion(url);
      const limit = boundedInt(url, "limit", 50, 1, 100);
      const offset = boundedInt(url, "offset", 0, 0, 10000);
      const rows = await sql`
        select feedback.admin_list_items(
          ${accountId}::uuid,${status}::text,${kind}::text,${product}::text,${appVersion}::text,
          ${limit}::integer,${offset}::integer
        ) as result
      `;
      return json(
        {
          ...(rows[0]?.result as Record<string, unknown>),
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (request.method === "GET" && path === "/api/v1/feedback/trends") {
      requirePermission(admin, "feedback.trends.read");
      const url = new URL(request.url);
      const product = optionalProduct(url);
      const days = boundedInt(url, "days", 30, 1, 365);
      const rows = await sql`
        select feedback.admin_trends(${accountId}::uuid,${product}::text,${days}::integer) as result
      `;
      return json(
        {
          ...(rows[0]?.result as Record<string, unknown>),
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    const actionMatch = path.match(/^\/api\/v1\/feedback\/([^/]+)\/actions$/);
    if (request.method === "POST" && actionMatch) {
      requirePermission(admin, "feedback.write");
      const itemId = decodeURIComponent(actionMatch[1]);
      if (!uuidPattern.test(itemId)) {
        throw new ApiError(
          400,
          "feedback_item_id_invalid",
          "Feedback item id is invalid.",
        );
      }
      const body = await readJsonObject(request);
      const expectedStatus = stringField(body, "expectedStatus", 1, 32);
      if (!statuses.has(expectedStatus)) {
        throw new ApiError(
          400,
          "feedback_expected_status_invalid",
          "expectedStatus is invalid.",
        );
      }
      const action = stringField(body, "action", 1, 32);
      if (!actions.has(action)) {
        throw new ApiError(
          400,
          "feedback_action_invalid",
          "action is invalid.",
        );
      }
      const reason = stringField(body, "reason", 3, 500);
      const supportTicketId = optionalUuid(body, "supportTicketId");
      const productIssueRef = optionalReference(body);
      if (action === "LinkSupport" && supportTicketId === null) {
        throw new ApiError(
          400,
          "feedback_support_link_required",
          "supportTicketId is required for LinkSupport.",
        );
      }
      if (action === "LinkProductIssue" && productIssueRef === null) {
        throw new ApiError(
          400,
          "feedback_product_issue_ref_required",
          "productIssueRef is required for LinkProductIssue.",
        );
      }
      if (action !== "LinkSupport" && supportTicketId !== null) {
        throw new ApiError(
          400,
          "feedback_support_link_forbidden",
          "supportTicketId is only valid for LinkSupport.",
        );
      }
      if (action !== "LinkProductIssue" && productIssueRef !== null) {
        throw new ApiError(
          400,
          "feedback_product_issue_ref_forbidden",
          "productIssueRef is only valid for LinkProductIssue.",
        );
      }
      const idempotencyKey = requireIdempotencyKey(request);
      const requestHash = await sha256({
        itemId,
        expectedStatus,
        action,
        reason,
        supportTicketId,
        productIssueRef,
      });
      const rows = await sql`
        select feedback.admin_transition_item_idempotent(
          ${accountId}::uuid,${itemId}::uuid,${expectedStatus}::feedback.item_status,${action}::text,
          ${reason}::text,${supportTicketId}::uuid,${productIssueRef}::text,
          ${idempotencyKey}::varchar,${requestHash}::varchar
        ) as result
      `;
      const result = (rows[0]?.result ?? {}) as Record<string, unknown>;
      return json(result, resultStatus(result), origin);
    }

    return null;
  };
}
