import {
  type AdminCapabilitySnapshot,
  requirePermission,
} from "./authorization.ts";
import {
  hashAbuseRuleMutation,
  hashAbuseRuleRetire,
  matchAbuseRuleRetirePath,
  matchAbuseRuleVersionsPath,
  parseAbuseRuleMutation,
  parseAbuseRuleRetire,
} from "./abuse_rules.ts";
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

const contextPattern = /^[a-z][a-z0-9._-]{2,79}$/;
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function mutationStatus(result: Record<string, unknown>): number {
  const status = Number(result.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "abuse_rule_workflow_unavailable",
      "Abuse rule workflow returned an invalid status.",
    );
  }
  if (status >= 400) {
    throw new ApiError(
      status,
      String(result.code),
      typeof result.message === "string"
        ? result.message
        : "Abuse rule operation failed.",
    );
  }
  return status;
}

function boundedLimit(url: URL): number {
  const raw = url.searchParams.get("limit");
  if (raw === null) return 100;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > 200) {
    throw new ApiError(
      400,
      "limit_invalid",
      "limit must be between 1 and 200.",
    );
  }
  return value;
}

function optionalContext(url: URL): string | null {
  const value = url.searchParams.get("context")?.trim().toLowerCase() ?? "";
  if (!value) return null;
  if (!contextPattern.test(value)) {
    throw new ApiError(
      400,
      "abuse_context_invalid",
      "context filter is invalid.",
    );
  }
  return value;
}

export function createAbuseRuleRouteHandler(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  return async function handleAbuseRuleRoute(
    context: Context,
  ): Promise<Response | null> {
    const { request, path, accountId, admin, correlationId, origin } = context;

    if (request.method === "GET" && path === "/api/v1/security/abuse/rules") {
      requirePermission(admin, "security.abuse.read");
      const url = new URL(request.url);
      const contextCode = optionalContext(url);
      const limit = boundedLimit(url);
      const rows = contextCode
        ? await sql`
          select r.id,r.code,r.context_code,r.display_name,r.rule_kind,r.subject_scope,
                 r.enforcement_action,r.window_seconds,r.max_count,r.cooldown_seconds,
                 r.evidence_code,r.approval_request_type,r.priority,r.status,r.version,
                 r.created_at_utc,r.updated_at_utc
          from security.abuse_rules r
          where r.context_code=${contextCode}
          order by r.priority,r.code
          limit ${limit}
        `
        : await sql`
          select r.id,r.code,r.context_code,r.display_name,r.rule_kind,r.subject_scope,
                 r.enforcement_action,r.window_seconds,r.max_count,r.cooldown_seconds,
                 r.evidence_code,r.approval_request_type,r.priority,r.status,r.version,
                 r.created_at_utc,r.updated_at_utc
          from security.abuse_rules r
          order by r.context_code,r.priority,r.code
          limit ${limit}
        `;
      return json(
        {
          items: rows,
          limit,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    const versionsRuleId = matchAbuseRuleVersionsPath(path);
    if (request.method === "GET" && versionsRuleId) {
      requirePermission(admin, "security.abuse.read");
      if (!uuidPattern.test(versionsRuleId)) {
        throw new ApiError(400, "abuse_rule_id_invalid", "Rule id is invalid.");
      }
      const limit = boundedLimit(new URL(request.url));
      const rows = await sql`
        select rule_version,snapshot_json,changed_by_account_id,change_reason,created_at_utc
        from security.abuse_rule_versions
        where rule_id=${versionsRuleId}::uuid
        order by rule_version desc
        limit ${limit}
      `;
      return json(
        {
          items: rows,
          limit,
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (
      request.method === "GET" && path === "/api/v1/security/abuse/decisions"
    ) {
      requirePermission(admin, "security.abuse.read");
      const url = new URL(request.url);
      const contextCode = optionalContext(url);
      const limit = boundedLimit(url);
      const rows = contextCode
        ? await sql`
          select id,context_code,final_action,matched_rule_ids,reason_codes,
                 approval_request_type,rule_set_hash,evaluated_at_utc
          from security.abuse_decisions
          where context_code=${contextCode}
          order by evaluated_at_utc desc,id desc
          limit ${limit}
        `
        : await sql`
          select id,context_code,final_action,matched_rule_ids,reason_codes,
                 approval_request_type,rule_set_hash,evaluated_at_utc
          from security.abuse_decisions
          order by evaluated_at_utc desc,id desc
          limit ${limit}
        `;
      return json(
        {
          items: rows,
          limit,
          privacy: {
            subjectIdentifiersExposed: false,
            rawContactValuesExposed: false,
          },
          freshness: { status: "fresh", asOfUtc: new Date().toISOString() },
        },
        200,
        origin,
      );
    }

    if (request.method === "POST" && path === "/api/v1/security/abuse/rules") {
      requirePermission(admin, "security.abuse.write");
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseAbuseRuleMutation(request);
      const requestHash = await hashAbuseRuleMutation(payload);
      const rows = await sql`
        select security.upsert_abuse_rule_idempotent(
          ${accountId}::uuid,${payload.code}::varchar,${payload.contextCode}::varchar,
          ${payload.displayName}::varchar,${payload.ruleKind}::varchar,${payload.subjectScope}::varchar,
          ${payload.enforcementAction}::varchar,${payload.windowSeconds}::integer,${payload.maxCount}::integer,
          ${payload.cooldownSeconds}::integer,${payload.evidenceCode}::varchar,${payload.approvalRequestType}::varchar,
          ${payload.priority}::integer,${payload.expectedVersion}::bigint,${payload.reason}::varchar,
          ${correlationId}::uuid,${idempotencyKey}::varchar,${requestHash}::varchar
        ) as result
      `;
      const result = (rows[0]?.result ?? {}) as Record<string, unknown>;
      return json(result, mutationStatus(result), origin);
    }

    const retireId = matchAbuseRuleRetirePath(path);
    if (request.method === "POST" && retireId) {
      requirePermission(admin, "security.abuse.write");
      if (!uuidPattern.test(retireId)) {
        throw new ApiError(400, "abuse_rule_id_invalid", "Rule id is invalid.");
      }
      const idempotencyKey = requireIdempotencyKey(request);
      const payload = await parseAbuseRuleRetire(request);
      const requestHash = await hashAbuseRuleRetire(retireId, payload);
      const rows = await sql`
        select security.retire_abuse_rule_idempotent(
          ${accountId}::uuid,${retireId}::uuid,${payload.expectedVersion}::bigint,
          ${payload.reason}::varchar,${correlationId}::uuid,${idempotencyKey}::varchar,${requestHash}::varchar
        ) as result
      `;
      const result = (rows[0]?.result ?? {}) as Record<string, unknown>;
      return json(result, mutationStatus(result), origin);
    }

    return null;
  };
}
