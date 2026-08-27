import { type AdminSql, getAdminSql } from "./database_client.ts";
import type { ExecuteEntitlementAdjustmentPayload } from "./entitlement_adjustments.ts";
import { ApiError } from "./validation.ts";

function objectResult(value: unknown, code: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(503, code, "Entitlement adjustment workflow returned an invalid result.");
  }
  return value as Record<string, unknown>;
}

function iso(value: unknown): string | null {
  if (value == null) return null;
  return value instanceof Date ? value.toISOString() : String(value);
}

async function previewState(
  sql: AdminSql,
  payload: ExecuteEntitlementAdjustmentPayload,
): Promise<{ before: Record<string, unknown>; delta: Record<string, unknown>; after: Record<string, unknown> }> {
  const delta = {
    operation: payload.operation,
    entitlementId: payload.entitlementId,
    featureId: payload.featureId,
    offerId: payload.offerId,
    exactExpiresAtUtc: payload.exactExpiresAtUtc,
    addDays: payload.addDays,
    addMonths: payload.addMonths,
  };

  if (payload.operation === "Grant") {
    return {
      before: {},
      delta,
      after: {
        status: "Active",
        featureId: payload.featureId,
        offerId: payload.offerId,
        expiresAtUtc: payload.exactExpiresAtUtc,
      },
    };
  }

  const rows = await sql`
    select id,status,feature_id,expires_at_utc,version
    from commerce.entitlements
    where id=${payload.entitlementId}::uuid
      and grantee_account_id=${payload.subjectAccountId}::uuid
    limit 1
  `;
  const value = rows[0] as Record<string, unknown> | undefined;
  if (!value) {
    throw new ApiError(
      404,
      "entitlement_not_found",
      "Entitlement was not found for the target account.",
    );
  }
  const currentExpiry = iso(value.expires_at_utc);
  const before = {
    entitlementId: String(value.id),
    status: String(value.status),
    featureId: String(value.feature_id),
    expiresAtUtc: currentExpiry,
    version: Number(value.version),
  };
  let nextExpiry = payload.exactExpiresAtUtc;
  if (!nextExpiry && (payload.addDays || payload.addMonths)) {
    const base = currentExpiry ? new Date(currentExpiry) : new Date();
    if (payload.addDays) base.setUTCDate(base.getUTCDate() + payload.addDays);
    if (payload.addMonths) base.setUTCMonth(base.getUTCMonth() + payload.addMonths);
    nextExpiry = base.toISOString();
  }
  return {
    before,
    delta,
    after: {
      ...before,
      status: payload.operation === "Revoke" ? "Revoked" : before.status,
      expiresAtUtc: payload.operation === "Revoke" ? currentExpiry : nextExpiry,
      version: Number(value.version) + 1,
    },
  };
}

export function createEntitlementAdjustmentStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);
  return {
    async request(input: {
      actorAccountId: string;
      payload: ExecuteEntitlementAdjustmentPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const state = await previewState(sql, input.payload);
      const rows = await sql`
        select admin.create_approval_request(
          ${input.actorAccountId}::uuid,
          'manual_entitlement_adjustment'::character varying,
          'account'::character varying,
          ${input.payload.subjectAccountId}::character varying,
          ${sql.json(state.before)}::jsonb,
          ${sql.json(state.delta)}::jsonb,
          ${sql.json(state.after)}::jsonb,
          ${input.payload.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return objectResult(rows[0]?.result, "entitlement_adjust_request_unavailable");
    },

    async execute(input: {
      actorAccountId: string;
      payload: ExecuteEntitlementAdjustmentPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const operationKey = [
        "manual-entitlement-adjustment",
        p.operation,
        p.entitlementId ?? p.featureId ?? p.offerId ?? "new",
      ].join(":");
      const abuseRows = await sql`
        select security.evaluate_abuse_rules(
          ${input.actorAccountId}::uuid,
          ${p.subjectAccountId}::uuid,
          'manual_entitlement_adjustment'::character varying,
          ${operationKey}::character varying,
          ${[]}::character varying[],
          ${`${input.idempotencyKey}:abuse`}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      const abuse = objectResult(
        abuseRows[0]?.result,
        "entitlement_adjust_abuse_unavailable",
      );
      if (Number(abuse.httpStatus) >= 400) return abuse;
      const decisionId = String(abuse.decisionId ?? "");
      if (!decisionId) {
        throw new ApiError(
          503,
          "entitlement_adjust_abuse_unavailable",
          "Abuse-control decision ID was unavailable.",
        );
      }

      const rows = await sql`
        select commerce.execute_manual_entitlement_adjustment_v2(
          ${input.actorAccountId}::uuid,
          ${p.subjectAccountId}::uuid,
          ${p.entitlementId}::uuid,
          ${p.expectedEntitlementVersion}::bigint,
          ${p.featureId}::uuid,
          ${p.offerId}::uuid,
          ${p.operation}::character varying,
          ${p.exactExpiresAtUtc}::timestamptz,
          ${p.addDays}::integer,
          ${p.addMonths}::integer,
          ${p.reason}::character varying,
          ${p.confirmed}::boolean,
          ${p.approvalRequestId}::uuid,
          ${p.approvalExpectedVersion}::bigint,
          ${decisionId}::uuid,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return objectResult(rows[0]?.result, "entitlement_adjust_execute_unavailable");
    },

    async history(subjectAccountId: string, limit: number) {
      const rows = await sql`
        select id,entitlement_id,feature_id,offer_id,operation,status,approval_request_id,
               actor_account_id,reason,before_json,after_json,correlation_id,created_at_utc
        from commerce.manual_entitlement_adjustments
        where subject_account_id=${subjectAccountId}::uuid
        order by created_at_utc desc,id desc
        limit ${limit}
      `;
      return (rows as unknown as Record<string, unknown>[]).map((value) => ({
        adjustmentId: String(value.id),
        entitlementId: value.entitlement_id == null ? null : String(value.entitlement_id),
        featureId: value.feature_id == null ? null : String(value.feature_id),
        offerId: value.offer_id == null ? null : String(value.offer_id),
        operation: String(value.operation),
        status: String(value.status),
        approvalRequestId: value.approval_request_id == null ? null : String(value.approval_request_id),
        actorAccountId: String(value.actor_account_id),
        reason: String(value.reason),
        before: value.before_json,
        after: value.after_json,
        correlationId: String(value.correlation_id),
        createdAtUtc: iso(value.created_at_utc),
      }));
    },
  };
}
