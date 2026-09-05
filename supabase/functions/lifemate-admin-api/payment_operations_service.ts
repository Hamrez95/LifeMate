import { type AdminSql, getAdminSql } from "./database_client.ts";

function result(rows: readonly Record<string, unknown>[]) {
  const value = rows[0]?.result;
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("payment_operation_result_invalid");
  }
  return value as Record<string, unknown>;
}

export function createPaymentOperationsStore(databaseUrl: string) {
  const sql: AdminSql = getAdminSql(databaseUrl);

  return {
    async requestRefund(input: {
      actorAccountId: string;
      transactionId: string;
      amountMinor: string;
      reason: string;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.request_commerce_refund_v2(
          ${input.actorAccountId}::uuid,${input.transactionId}::uuid,
          ${input.amountMinor}::bigint,${input.reason}::character varying,
          ${input.correlationId}::uuid,${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return result(rows as unknown as Record<string, unknown>[]);
    },

    async submitRefund(input: {
      actorAccountId: string;
      refundRequestId: string;
      expectedRefundVersion: number;
      approvalExpectedVersion: number;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.submit_approved_commerce_refund(
          ${input.actorAccountId}::uuid,${input.refundRequestId}::uuid,
          ${input.expectedRefundVersion}::bigint,${input.approvalExpectedVersion}::bigint,
          ${input.correlationId}::uuid,${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return result(rows as unknown as Record<string, unknown>[]);
    },

    async listRefunds(limit: number) {
      return await sql`
        select rr.id as refund_request_id,rr.transaction_id,rr.status as request_status,
               rr.amount_minor,rr.currency,rr.reason,rr.version,rr.requested_at_utc,
               ro.id as refund_operation_id,ro.status as provider_status,ro.provider,
               ro.submitted_at_utc,ro.settled_at_utc,ro.provider_error_code
        from commerce.refund_requests rr
        left join commerce.refund_operations ro on ro.refund_request_id=rr.id
        order by rr.requested_at_utc desc,rr.id desc
        limit ${limit}
      `;
    },

    async openReconciliation(input: {
      actorAccountId: string;
      transactionId: string | null;
      caseType: string;
      reason: string;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.open_reconciliation_case_idempotent(
          ${input.actorAccountId}::uuid,${input.transactionId}::uuid,
          ${input.caseType}::character varying,${input.reason}::character varying,
          ${input.correlationId}::uuid,${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return result(rows as unknown as Record<string, unknown>[]);
    },

    async previewCorrection(input: {
      caseId: string;
      correctionType: string;
      correctedStatus: string | null;
      annotationCode: string | null;
    }) {
      const rows = await sql`
        select commerce.preview_transaction_correction(
          ${input.caseId}::uuid,${input.correctionType}::character varying,
          ${input.correctedStatus}::character varying,${input.annotationCode}::character varying
        ) as result
      `;
      return result(rows as unknown as Record<string, unknown>[]);
    },

    async executeCorrection(input: {
      actorAccountId: string;
      caseId: string;
      correctionType: string;
      correctedStatus: string | null;
      annotationCode: string | null;
      reason: string;
      approvalRequestId: string;
      approvalExpectedVersion: number;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.apply_approved_transaction_correction_v2(
          ${input.actorAccountId}::uuid,${input.caseId}::uuid,
          ${input.correctionType}::character varying,${input.correctedStatus}::character varying,
          ${input.annotationCode}::character varying,${input.reason}::character varying,
          ${input.approvalRequestId}::uuid,${input.approvalExpectedVersion}::bigint,
          ${input.correlationId}::uuid,${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return result(rows as unknown as Record<string, unknown>[]);
    },

    async listReconciliationCases(limit: number) {
      return await sql`
        select rc.id,rc.transaction_id,rc.case_type,rc.status,rc.source,
               rc.reason,rc.assigned_to_account_id,rc.opened_at_utc,rc.resolved_at_utc,
               es.provider_normalized_status,es.effective_normalized_status,
               es.classification_source,es.correction_id
        from commerce.reconciliation_cases rc
        left join commerce.transaction_effective_state_v1 es on es.transaction_id=rc.transaction_id
        order by rc.opened_at_utc desc,rc.id desc
        limit ${limit}
      `;
    },

    async setRenewalIntent(input: {
      actorAccountId: string;
      subscriptionId: string;
      expectedVersion: number;
      cancelAtPeriodEnd: boolean;
      reasonCode: string;
      reasonText: string | null;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select commerce.set_subscription_renewal_intent_v2(
          ${input.actorAccountId}::uuid,'Admin'::character varying,
          ${input.subscriptionId}::uuid,${input.expectedVersion}::bigint,
          ${input.cancelAtPeriodEnd}::boolean,${input.reasonCode}::character varying,
          ${input.reasonText}::character varying,${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,${input.requestHash}::character varying
        ) as result
      `;
      return result(rows as unknown as Record<string, unknown>[]);
    },

    async listChurn(limit: number) {
      return await sql`
        select s.id as subscription_id,s.owner_account_id,s.plan_id,s.status,
               s.current_period_end_utc,s.cancel_at_period_end,
               s.non_renewal_requested_at_utc,s.cancellation_reason_code,
               s.cancellation_reason_text,s.cancellation_version,
               e.event_type as latest_event_type,e.occurred_at_utc as latest_event_at_utc
        from commerce.subscriptions s
        left join lateral(
          select event_type,occurred_at_utc
          from commerce.subscription_cancellation_events ce
          where ce.subscription_id=s.id
          order by occurred_at_utc desc,id desc limit 1
        ) e on true
        where s.cancel_at_period_end=true or s.non_renewal_requested_at_utc is not null
        order by coalesce(s.non_renewal_requested_at_utc,s.updated_at_utc) desc,s.id desc
        limit ${limit}
      `;
    },
  };
}
