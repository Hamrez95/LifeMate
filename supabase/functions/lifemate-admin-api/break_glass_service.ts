import { type AdminSql, getAdminSql } from "./database_client.ts";
import type {
  BreakGlassActionRequest,
  BreakGlassCreateRequest,
  BreakGlassDecision,
} from "./break_glass.ts";
import { ApiError } from "./validation.ts";

function result(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "break_glass_unavailable",
      "Break-glass workflow result was unavailable.",
    );
  }
  const parsed = value as Record<string, unknown>;
  if (!Number.isInteger(parsed.httpStatus) || typeof parsed.code !== "string") {
    throw new ApiError(
      503,
      "break_glass_unavailable",
      "Break-glass workflow result was invalid.",
    );
  }
  return parsed;
}

function iso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : String(value);
}

export function createBreakGlassStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  return {
    async list(accountId: string) {
      const rows = await sql`
        select
          id,
          requester_account_id,
          subject_person_id,
          capability,
          reason,
          case
            when status='Approved' and expires_at_utc is not null and expires_at_utc <= now()
              then 'Expired'
            else status
          end as effective_status,
          requested_ttl_minutes,
          requested_at_utc,
          reviewed_by_account_id,
          reviewed_at_utc,
          expires_at_utc,
          revoked_at_utc,
          review_reason,
          version
        from admin.elevated_access_requests
        where requester_account_id = ${accountId}::uuid
           or admin.account_has_permission(${accountId}::uuid, 'security.break_glass.approve')
        order by requested_at_utc desc, id desc
        limit 100
      `;
      return rows.map((row) => ({
        requestId: String(row.id),
        requesterAccountId: String(row.requester_account_id),
        subjectPersonId: String(row.subject_person_id),
        capability: String(row.capability),
        reason: String(row.reason),
        status: String(row.effective_status),
        ttlMinutes: Number(row.requested_ttl_minutes),
        requestedAtUtc: iso(row.requested_at_utc),
        reviewedByAccountId: row.reviewed_by_account_id == null
          ? null
          : String(row.reviewed_by_account_id),
        reviewedAtUtc: row.reviewed_at_utc == null
          ? null
          : iso(row.reviewed_at_utc),
        expiresAtUtc: row.expires_at_utc == null
          ? null
          : iso(row.expires_at_utc),
        revokedAtUtc: row.revoked_at_utc == null
          ? null
          : iso(row.revoked_at_utc),
        reviewReason: row.review_reason == null
          ? null
          : String(row.review_reason),
        version: Number(row.version),
      }));
    },

    async create(input: {
      actorAccountId: string;
      request: BreakGlassCreateRequest;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.create_break_glass_request(
          ${input.actorAccountId}::uuid,
          ${input.request.subjectPersonId}::uuid,
          ${input.request.capability}::character varying,
          ${input.request.ttlMinutes}::integer,
          ${input.request.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return result(rows[0]?.result);
    },

    async mutate(input: {
      actorAccountId: string;
      requestId: string;
      action: BreakGlassDecision;
      request: BreakGlassActionRequest;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.mutate_break_glass_request(
          ${input.actorAccountId}::uuid,
          ${input.requestId}::uuid,
          ${input.action}::character varying,
          ${input.request.expectedVersion}::integer,
          ${input.request.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return result(rows[0]?.result);
    },
  };
}
