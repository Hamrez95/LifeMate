import { getAdminSql, toAdminJson } from "./database_client.ts";
import type { ManualEntitlementPayload } from "./manual_entitlement_adjustments.ts";
import { ApiError } from "./validation.ts";

function object(value: unknown, code: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(503, code, "Workflow returned an invalid result.");
  }
  return value as Record<string, unknown>;
}

function httpStatus(value: Record<string, unknown>): number {
  const status = Number(value.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "entitlement_adjustment_unavailable",
      "Workflow returned an invalid status.",
    );
  }
  return status;
}

function iso(value: unknown): string | null {
  if (value == null) return null;
  return value instanceof Date ? value.toISOString() : String(value);
}

export function createManualEntitlementAdjustmentStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  async function previewWith(
    client: typeof sql,
    payload: ManualEntitlementPayload,
  ) {
    const rows = await client`
      select commerce.preview_manual_entitlement_adjustment(
        ${payload.subjectAccountId}::uuid,${payload.targetType}::varchar,${payload.targetId}::uuid,
        ${payload.entitlementId}::uuid,${payload.expectedEntitlementVersion}::bigint,
        ${payload.operation}::varchar,${payload.scheduleMode}::varchar,${payload.scheduleAmount}::integer,
        ${payload.exactExpiresAtUtc}::timestamptz,${payload.referenceAtUtc}::timestamptz
      ) as result
    `;
    return object(rows[0]?.result, "entitlement_preview_unavailable");
  }

  return {
    preview(payload: ManualEntitlementPayload) {
      return previewWith(sql, payload);
    },

    async request(input: {
      actorAccountId: string;
      payload: ManualEntitlementPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const preview = await previewWith(sql, input.payload);
      if (httpStatus(preview) >= 400) return preview;
      const rows = await sql`
        select admin.create_approval_request(
          ${input.actorAccountId}::uuid,
          'manual_entitlement_adjustment'::varchar,
          'account'::varchar,
          ${input.payload.subjectAccountId}::varchar,
          ${sql.json(toAdminJson(preview.before))}::jsonb,
          ${sql.json(toAdminJson(preview.delta))}::jsonb,
          ${sql.json(toAdminJson(preview.after))}::jsonb,
          ${input.payload.reason}::varchar,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return {
        ...object(rows[0]?.result, "entitlement_adjust_request_unavailable"),
        normalized: input.payload,
      };
    },

    async execute(input: {
      actorAccountId: string;
      isFounder: boolean;
      payload: ManualEntitlementPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      try {
        return await sql.begin(async (tx) => {
          await tx`select pg_advisory_xact_lock(hashtextextended(${`${input.actorAccountId}:commerce.entitlement.adjust.execute:${input.idempotencyKey}`},0))`;

          const existing = await tx`
            select id,operation,affected_entitlement_ids,before_json,after_json,abuse_decision_id,created_at_utc,request_hash
            from commerce.manual_entitlement_adjustments
            where actor_account_id=${input.actorAccountId}::uuid
              and idempotency_key=${input.idempotencyKey}
            limit 1
          `;
          if (existing[0]) {
            if (String(existing[0].request_hash) !== input.requestHash) {
              throw new ApiError(
                409,
                "idempotency_conflict",
                "Idempotency-Key was used for a different adjustment.",
              );
            }
            return {
              httpStatus: 200,
              code: "ok",
              adjustmentId: String(existing[0].id),
              operation: String(existing[0].operation),
              affectedEntitlementIds: existing[0].affected_entitlement_ids,
              before: existing[0].before_json,
              after: existing[0].after_json,
              abuseDecisionId: existing[0].abuse_decision_id == null
                ? null
                : String(existing[0].abuse_decision_id),
              createdAtUtc: iso(existing[0].created_at_utc),
              replayed: true,
            };
          }

          if (
            !input.isFounder &&
            (!input.payload.approvalRequestId ||
              !input.payload.approvalExpectedVersion)
          ) {
            return {
              httpStatus: 409,
              code: "entitlement_adjust_approval_required",
              message: "An approved manual entitlement request is required.",
              approvalRequestType: "manual_entitlement_adjustment",
            };
          }

          const preview = await previewWith(tx as typeof sql, input.payload);
          if (httpStatus(preview) >= 400) return preview;

          // Abuse-decision idempotency follows the complete normalized request hash,
          // not the business execution key. A Founder can therefore retry after a
          // RequireApproval decision with the newly approved request without
          // colliding with the earlier decision, while exact retries still replay.
          const abuseIdempotencyKey = `entitlement-adjust:${
            input.requestHash.slice(0, 48)
          }`;
          const abuseRows = await tx`
            select security.evaluate_abuse_rules(
              ${input.actorAccountId}::uuid,${input.payload.subjectAccountId}::uuid,
              'manual_entitlement_adjustment'::varchar,
              ${
            input.payload.entitlementId ??
              `${input.payload.targetType}:${input.payload.targetId}`
          }::varchar,
              ${
            input.payload.approvalRequestId ? ["approval_present"] : []
          }::varchar[],
              ${abuseIdempotencyKey}::varchar,
              ${input.requestHash}::varchar
            ) as result
          `;
          const abuse = object(
            abuseRows[0]?.result,
            "entitlement_abuse_unavailable",
          );
          if (httpStatus(abuse) >= 400) return abuse;
          if (abuse.action === "Deny") {
            return {
              httpStatus: 403,
              code: "entitlement_adjust_abuse_denied",
              message: "Adjustment was denied by an explainable abuse rule.",
              abuseDecisionId: abuse.decisionId,
              reasonCodes: abuse.reasonCodes,
            };
          }

          const requiresApproval = !input.isFounder ||
            abuse.action === "RequireApproval";
          if (requiresApproval) {
            if (
              !input.payload.approvalRequestId ||
              !input.payload.approvalExpectedVersion
            ) {
              return {
                httpStatus: 409,
                code: "entitlement_adjust_approval_required",
                message: "An approved manual entitlement request is required.",
                approvalRequestType: abuse.approvalRequestType ??
                  "manual_entitlement_adjustment",
              };
            }
            if (
              abuse.action === "RequireApproval" &&
              abuse.approvalRequestType &&
              abuse.approvalRequestType !== "manual_entitlement_adjustment"
            ) {
              return {
                httpStatus: 409,
                code: "entitlement_adjust_approval_policy_mismatch",
                message: "Abuse rule requires an incompatible approval policy.",
              };
            }
            await tx`
              select commerce.manual_adjustment_approval_valid(
                ${input.actorAccountId}::uuid,${input.payload.subjectAccountId}::uuid,
                ${input.payload.approvalRequestId}::uuid,${input.payload.approvalExpectedVersion}::bigint,
                ${tx.json(toAdminJson(preview.before))}::jsonb,
                ${tx.json(toAdminJson(preview.delta))}::jsonb,
                ${tx.json(toAdminJson(preview.after))}::jsonb,
                ${input.correlationId}::uuid
              )
            `;
          } else if (input.payload.approvalRequestId) {
            throw new ApiError(
              400,
              "unexpected_approval",
              "Direct Founder execution must not consume an unrelated approval.",
            );
          }

          const decisionId = typeof abuse.decisionId === "string"
            ? abuse.decisionId
            : null;
          if (!decisionId) {
            throw new ApiError(
              503,
              "entitlement_abuse_unavailable",
              "Abuse evaluation did not return a decision id.",
            );
          }

          const adjustmentId = crypto.randomUUID();
          let affected: string[];
          let after: unknown;
          if (input.payload.operation === "Grant") {
            const expiry = String(
              (preview.after as Record<string, unknown>).expiresAtUtc,
            );
            const rows = await tx`
              select commerce.apply_manual_entitlement_grant_guarded(
                ${input.actorAccountId}::uuid,${input.payload.subjectAccountId}::uuid,
                ${input.payload.targetType}::varchar,${input.payload.targetId}::uuid,
                ${expiry}::timestamptz,${adjustmentId}::uuid
              ) as ids
            `;
            affected = Array.isArray(rows[0]?.ids)
              ? rows[0].ids.map(String)
              : [];
            after = {
              ...(preview.after as Record<string, unknown>),
              affectedEntitlementIds: affected,
            };
          } else {
            const expiry = String(
              (preview.after as Record<string, unknown>).expiresAtUtc,
            );
            const rows = await tx`
              select commerce.apply_manual_entitlement_change_guarded(
                ${input.actorAccountId}::uuid,${input.payload.subjectAccountId}::uuid,
                ${input.payload.targetType}::varchar,${input.payload.targetId}::uuid,
                ${input.payload.entitlementId}::uuid,${input.payload.expectedEntitlementVersion}::bigint,
                ${input.payload.operation}::varchar,${expiry}::timestamptz,${adjustmentId}::uuid
              ) as result
            `;
            affected = [input.payload.entitlementId!];
            after = rows[0]?.result;
          }

          await tx`
            insert into commerce.manual_entitlement_adjustments(
              id,subject_account_id,target_type,target_id,entitlement_id,operation,schedule_mode,
              schedule_amount,exact_expires_at_utc,reference_at_utc,affected_entitlement_ids,
              before_json,after_json,approval_request_id,abuse_decision_id,actor_account_id,
              reason,correlation_id,idempotency_key,request_hash
            ) values(
              ${adjustmentId}::uuid,${input.payload.subjectAccountId}::uuid,${input.payload.targetType}::varchar,
              ${input.payload.targetId}::uuid,${input.payload.entitlementId}::uuid,${input.payload.operation}::varchar,
              ${input.payload.scheduleMode}::varchar,${input.payload.scheduleAmount}::integer,
              ${input.payload.exactExpiresAtUtc}::timestamptz,${input.payload.referenceAtUtc}::timestamptz,
              ${affected}::uuid[],${
            tx.json(toAdminJson(preview.before))
          }::jsonb,
              ${
            tx.json(toAdminJson(after))
          }::jsonb,${input.payload.approvalRequestId}::uuid,
              ${decisionId}::uuid,${input.actorAccountId}::uuid,${input.payload.reason}::varchar,
              ${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar
            )
          `;
          await tx`
            select security.record_abuse_event(
              ${input.payload.subjectAccountId}::uuid,'manual_entitlement_adjustment'::varchar,
              ${
            input.payload.entitlementId ?? adjustmentId
          }::varchar,'adjustment_executed'::varchar
            )
          `;
          await tx`
            insert into admin.audit_events(
              actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,
              request_id,elevated_access,metadata_json
            ) values(
              ${input.actorAccountId}::uuid,'commerce.entitlement.adjust.execute','manual_entitlement_adjustment',
              ${adjustmentId},'Succeeded',${input.payload.reason},${input.correlationId}::uuid,
              ${input.idempotencyKey},false,
              ${
            tx.json({
              subjectAccountId: input.payload.subjectAccountId,
              targetType: input.payload.targetType,
              targetId: input.payload.targetId,
              operation: input.payload.operation,
              affectedEntitlementCount: affected.length,
            })
          }::jsonb
            )
          `;
          return {
            httpStatus: 200,
            code: "ok",
            adjustmentId,
            operation: input.payload.operation,
            affectedEntitlementIds: affected,
            before: preview.before,
            after,
            abuseDecisionId: decisionId,
            replayed: false,
          };
        });
      } catch (error) {
        if (error instanceof ApiError) throw error;
        const value = error as { code?: string; message?: string };
        if (value.code === "42501") {
          throw new ApiError(
            403,
            "entitlement_adjust_permission_denied",
            "Actor cannot execute entitlement adjustments.",
          );
        }
        if (value.code === "40001") {
          throw new ApiError(
            409,
            "entitlement_version_conflict",
            "Entitlement changed; refresh before adjusting.",
          );
        }
        if (
          value.code === "22023" || value.code === "55000" ||
          value.code === "P0002"
        ) {
          throw new ApiError(
            409,
            "entitlement_adjustment_conflict",
            "Approval or entitlement state changed; refresh before adjusting.",
          );
        }
        throw error;
      }
    },

    async history(subjectAccountId: string, limit: number) {
      const rows = await sql`
        select id,target_type,target_id,entitlement_id,operation,schedule_mode,schedule_amount,
               exact_expires_at_utc,reference_at_utc,affected_entitlement_ids,before_json,after_json,
               approval_request_id,abuse_decision_id,actor_account_id,reason,correlation_id,created_at_utc
        from commerce.manual_entitlement_adjustments
        where subject_account_id=${subjectAccountId}::uuid
        order by created_at_utc desc,id desc
        limit ${limit}
      `;
      return rows;
    },
  };
}
