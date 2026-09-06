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

const keyPattern = /^[a-z][a-z0-9._-]{2,79}$/;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const dispositions = new Set(["Delete", "Anonymize", "Archive", "Review"]);

function boundedString(
  value: unknown,
  field: string,
  min: number,
  max: number,
): string {
  if (typeof value !== "string") {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  const trimmed = value.trim();
  if (trimmed.length < min || trimmed.length > max) {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  return trimmed;
}

function optionalKey(value: unknown, field: string): string | null {
  if (value === null || value === undefined || value === "") return null;
  const result = boundedString(value, field, 3, 80).toLowerCase();
  if (!keyPattern.test(result)) {
    throw new ApiError(400, `${field}_invalid`, `${field} is invalid.`);
  }
  return result;
}

async function bodyObject(request: Request): Promise<Record<string, unknown>> {
  let value: unknown;
  try {
    value = await request.json();
  } catch {
    throw new ApiError(400, "json_invalid", "Request body must be valid JSON.");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "body_invalid",
      "Request body must be a JSON object.",
    );
  }
  return value as Record<string, unknown>;
}

function integer(
  value: unknown,
  field: string,
  min: number,
  max: number,
  nullable = false,
): number | null {
  if (nullable && (value === null || value === undefined)) return null;
  if (!Number.isInteger(value) || Number(value) < min || Number(value) > max) {
    throw new ApiError(
      400,
      `${field}_invalid`,
      `${field} is outside the allowed range.`,
    );
  }
  return Number(value);
}

function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, entry]) => [key, canonical(entry)]),
    );
  }
  return value;
}

async function requestHash(
  operation: string,
  payload: unknown,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(
      JSON.stringify(["retention-v3", operation, canonical(payload)]),
    ),
  );
  return Array.from(new Uint8Array(digest)).map((value) =>
    value.toString(16).padStart(2, "0")
  ).join("");
}

function mutationStatus(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "retention_workflow_unavailable",
      "Retention workflow returned an invalid status.",
    );
  }
  if (status >= 400) {
    throw new ApiError(
      status,
      String(result.code),
      typeof result.message === "string"
        ? result.message
        : "Retention operation failed.",
    );
  }
  return status;
}

export function createRetentionRouteHandler(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  return async function handleRetentionRoute(
    context: Context,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    if (
      request.method === "GET" && path === "/api/v1/security/retention/policies"
    ) {
      requirePermission(admin, "security.retention.read");
      const rows = await sql`
        select data_category,purpose_code,retention_days,grace_days,disposition,policy_version,status,
               legal_basis,effective_at_utc,created_at_utc,updated_at_utc
        from security.retention_policy_versions
        order by data_category,purpose_code,policy_version desc
        limit 500
      `;
      return json(
        {
          items: rows,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "GET" &&
      path === "/api/v1/security/retention/deletion-preview"
    ) {
      requirePermission(admin, "security.retention.read");
      const rows = await sql`
        select
          count(*) filter (where r.status in ('Requested','Processing'))::bigint as pending_count,
          count(*) filter (
            where r.status in ('Requested','Processing')
              and coalesce(r.eligible_at_utc,r.requested_at_utc)<=now()
              and not exists(
                select 1 from security.retention_holds h
                where h.account_id=r.account_id and h.status='Active'
                  and (h.expires_at_utc is null or h.expires_at_utc>now())
              )
          )::bigint as eligible_count,
          count(*) filter (
            where r.status in ('Requested','Processing')
              and exists(
                select 1 from security.retention_holds h
                where h.account_id=r.account_id and h.status='Active'
                  and (h.expires_at_utc is null or h.expires_at_utc>now())
              )
          )::bigint as held_count
        from identity.account_deletion_requests r
      `;
      const row = rows[0] ?? {};
      return json(
        {
          pendingCount: Number(row.pending_count ?? 0),
          eligibleCount: Number(row.eligible_count ?? 0),
          heldCount: Number(row.held_count ?? 0),
          destructiveActionPerformed: false,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "GET" && path === "/api/v1/security/retention/holds"
    ) {
      requirePermission(admin, "security.retention.read");
      const url = new URL(request.url);
      const accountIdFilter = url.searchParams.get("accountId");
      if (accountIdFilter && !uuidPattern.test(accountIdFilter)) {
        throw new ApiError(400, "account_id_invalid", "accountId is invalid.");
      }
      const rows = accountIdFilter
        ? await sql`
          select id,account_id,data_category,purpose_code,reason_code,status,expires_at_utc,created_by_account_id,
                 created_at_utc,released_by_account_id,released_at_utc
          from security.retention_holds where account_id=${accountIdFilter}::uuid
          order by created_at_utc desc limit 200
        `
        : await sql`
          select id,account_id,data_category,purpose_code,reason_code,status,expires_at_utc,created_by_account_id,
                 created_at_utc,released_by_account_id,released_at_utc
          from security.retention_holds order by created_at_utc desc limit 200
        `;
      return json(
        {
          items: rows,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "POST" &&
      path === "/api/v1/security/retention/policies"
    ) {
      requirePermission(admin, "security.retention.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const body = await bodyObject(request);
      const category = optionalKey(body.dataCategory, "data_category");
      const purpose =
        optionalKey(body.purposeCode ?? "default", "purpose_code") ?? "default";
      if (!category) {
        throw new ApiError(
          400,
          "data_category_invalid",
          "dataCategory is required.",
        );
      }
      const retentionDays = integer(
        body.retentionDays,
        "retention_days",
        0,
        36500,
        true,
      );
      const graceDays = integer(body.graceDays ?? 0, "grace_days", 0, 3650) ??
        0;
      const disposition = boundedString(body.disposition, "disposition", 4, 24);
      if (!dispositions.has(disposition)) {
        throw new ApiError(
          400,
          "disposition_invalid",
          "disposition is invalid.",
        );
      }
      const legalBasis =
        body.legalBasis === null || body.legalBasis === undefined
          ? null
          : boundedString(body.legalBasis, "legal_basis", 1, 500);
      const reason = boundedString(body.reason, "reason", 10, 1000);
      const payload = {
        category,
        purpose,
        retentionDays,
        graceDays,
        disposition,
        legalBasis,
        reason,
      };
      const rows = await sql`
        select security.activate_retention_policy_idempotent(
          ${accountId}::uuid,${category}::varchar,${purpose}::varchar,${retentionDays}::integer,
          ${graceDays}::integer,${disposition}::varchar,${legalBasis}::varchar,${reason}::varchar,
          ${correlationId}::uuid,${idempotencyKey}::varchar,${await requestHash(
        "policy.activate",
        payload,
      )}::varchar
        ) as result
      `;
      const result = (rows[0]?.result ?? {}) as Record<string, unknown>;
      return json(result, mutationStatus(result), origin);
    }

    if (
      request.method === "POST" && path === "/api/v1/security/retention/holds"
    ) {
      requirePermission(admin, "security.retention.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const body = await bodyObject(request);
      const targetAccountId = boundedString(
        body.accountId,
        "account_id",
        36,
        36,
      );
      if (!uuidPattern.test(targetAccountId)) {
        throw new ApiError(400, "account_id_invalid", "accountId is invalid.");
      }
      const category = optionalKey(body.dataCategory, "data_category");
      const purpose = optionalKey(body.purposeCode, "purpose_code");
      const reasonCode = optionalKey(body.reasonCode, "reason_code");
      if (!reasonCode) {
        throw new ApiError(
          400,
          "reason_code_invalid",
          "reasonCode is required.",
        );
      }
      const reason = boundedString(body.reason, "reason", 10, 1000);
      const expiresAt =
        body.expiresAtUtc === null || body.expiresAtUtc === undefined
          ? null
          : boundedString(body.expiresAtUtc, "expires_at_utc", 20, 40);
      if (expiresAt && Number.isNaN(Date.parse(expiresAt))) {
        throw new ApiError(
          400,
          "expires_at_utc_invalid",
          "expiresAtUtc is invalid.",
        );
      }
      const payload = {
        targetAccountId,
        category,
        purpose,
        reasonCode,
        reason,
        expiresAt,
      };
      const rows = await sql`
        select security.create_retention_hold_idempotent(
          ${accountId}::uuid,${targetAccountId}::uuid,${category}::varchar,${purpose}::varchar,
          ${reasonCode}::varchar,${reason}::varchar,${expiresAt}::timestamptz,${correlationId}::uuid,
          ${idempotencyKey}::varchar,${await requestHash(
        "hold.create",
        payload,
      )}::varchar
        ) as result
      `;
      const result = (rows[0]?.result ?? {}) as Record<string, unknown>;
      return json(result, mutationStatus(result), origin);
    }

    const release = path.match(
      /^\/api\/v1\/security\/retention\/holds\/([0-9a-f-]{36})\/release$/i,
    );
    if (request.method === "POST" && release) {
      requirePermission(admin, "security.retention.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const holdId = release[1];
      if (!uuidPattern.test(holdId)) {
        throw new ApiError(400, "hold_id_invalid", "Hold id is invalid.");
      }
      const body = await bodyObject(request);
      const reason = boundedString(body.reason, "reason", 10, 1000);
      const payload = { holdId, reason };
      const rows = await sql`
        select security.release_retention_hold_idempotent(
          ${accountId}::uuid,${holdId}::uuid,${reason}::varchar,${correlationId}::uuid,
          ${idempotencyKey}::varchar,${await requestHash(
        "hold.release",
        payload,
      )}::varchar
        ) as result
      `;
      const result = (rows[0]?.result ?? {}) as Record<string, unknown>;
      return json(result, mutationStatus(result), origin);
    }

    return null;
  };
}
