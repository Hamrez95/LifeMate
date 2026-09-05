import { getAdminSql, toAdminJson } from "./database_client.ts";
import type {
  CreateApprovalRequest,
  DecideApprovalRequest,
} from "./approval_requests.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

function mutationResult(value: unknown): Row {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "approval_workflow_unavailable",
      "Approval workflow result was unavailable.",
    );
  }
  const row = value as Row;
  if (
    !Number.isInteger(row.httpStatus) || typeof row.code !== "string" ||
    typeof row.replayed !== "boolean"
  ) {
    throw new ApiError(
      503,
      "approval_workflow_unavailable",
      "Approval workflow result was invalid.",
    );
  }
  return row;
}

function requestRow(row: Row) {
  return {
    id: String(row.id),
    requestType: String(row.request_type),
    policyDisplayName: String(row.policy_display_name ?? row.request_type),
    targetType: String(row.target_type),
    targetId: String(row.target_id),
    status: String(row.status),
    version: Number(row.version),
    requesterAccountId: String(row.requester_account_id),
    reason: String(row.reason),
    expiresAtUtc: new Date(String(row.expires_at_utc)).toISOString(),
    reviewedByAccountId: row.reviewed_by_account_id
      ? String(row.reviewed_by_account_id)
      : null,
    reviewedAtUtc: row.reviewed_at_utc
      ? new Date(String(row.reviewed_at_utc)).toISOString()
      : null,
    reviewReason: row.review_reason ? String(row.review_reason) : null,
    executedByAccountId: row.executed_by_account_id
      ? String(row.executed_by_account_id)
      : null,
    executedAtUtc: row.executed_at_utc
      ? new Date(String(row.executed_at_utc)).toISOString()
      : null,
    executionOperation: row.execution_operation
      ? String(row.execution_operation)
      : null,
    createdAtUtc: new Date(String(row.created_at_utc)).toISOString(),
    updatedAtUtc: new Date(String(row.updated_at_utc)).toISOString(),
  };
}

export function createApprovalRequestStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async list(
      status: string | null,
      requestType: string | null,
      limit: number,
    ) {
      const rows = await sql`
        select r.*,p.display_name as policy_display_name
        from admin.approval_requests r
        join admin.approval_policies p on p.request_type=r.request_type
        where (${status}::text is null or r.status=${status})
          and (${requestType}::text is null or r.request_type=${requestType})
        order by r.created_at_utc desc,r.id desc
        limit ${limit}
      `;
      return rows.map(requestRow);
    },

    async get(id: string) {
      const rows = await sql`
        select r.*,p.display_name as policy_display_name
        from admin.approval_requests r
        join admin.approval_policies p on p.request_type=r.request_type
        where r.id=${id}::uuid
        limit 1
      `;
      if (rows.length === 0) return null;
      const events = await sql`
        select event_type,actor_account_id,from_status,to_status,reason,correlation_id,metadata_json,occurred_at_utc
        from admin.approval_events
        where approval_request_id=${id}::uuid
        order by occurred_at_utc,id
      `;
      const base = requestRow(rows[0]);
      return {
        ...base,
        before: rows[0].before_json,
        delta: rows[0].requested_delta_json,
        after: rows[0].after_json,
        events: events.map((event) => ({
          eventType: String(event.event_type),
          actorAccountId: String(event.actor_account_id),
          fromStatus: event.from_status ? String(event.from_status) : null,
          toStatus: String(event.to_status),
          reason: event.reason ? String(event.reason) : null,
          correlationId: String(event.correlation_id),
          metadata: event.metadata_json,
          occurredAtUtc: new Date(String(event.occurred_at_utc)).toISOString(),
        })),
      };
    },

    async create(input: {
      actorAccountId: string;
      payload: CreateApprovalRequest;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.create_approval_request(
          ${input.actorAccountId}::uuid,
          ${p.requestType}::character varying,
          ${p.targetType}::character varying,
          ${p.targetId}::character varying,
          ${sql.json(toAdminJson(p.before))},
          ${sql.json(toAdminJson(p.delta))},
          ${sql.json(toAdminJson(p.after))},
          ${p.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return mutationResult(rows[0]?.result);
    },

    async decide(input: {
      actorAccountId: string;
      id: string;
      payload: DecideApprovalRequest;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.decide_approval_request(
          ${input.actorAccountId}::uuid,
          ${input.id}::uuid,
          ${input.payload.expectedVersion}::bigint,
          ${input.payload.decision}::character varying,
          ${input.payload.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return mutationResult(rows[0]?.result);
    },
  };
}
