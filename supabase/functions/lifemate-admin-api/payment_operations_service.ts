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
          ${input.actorAccountId}::uuid,
          ${input.transactionId}::uuid,
          ${input.amountMinor}::bigint,
          ${input.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
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
          ${input.actorAccountId}::uuid,
          ${input.refundRequestId}::uuid,
          ${input.expectedRefundVersion}::bigint,
          ${input.approvalExpectedVersion}::bigint,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return result(rows as unknown as Record<string, unknown>[]);
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
          ${input.actorAccountId}::uuid,
          ${input.transactionId}::uuid,
          ${input.caseType}::character varying,
          ${input.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
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
          ${input.caseId}::uuid,
          ${input.correctionType}::character varying,
          ${input.correctedStatus}::character varying,
          ${input.annotationCode}::character varying
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
        select admin.apply_approved_transaction_correction_idempotent(
          ${input.actorAccountId}::uuid,
          ${input.caseId}::uuid,
          ${input.correctionType}::character varying,
          ${input.correctedStatus}::character varying,
          ${input.annotationCode}::character varying,
          ${input.reason}::character varying,
          ${input.approvalRequestId}::uuid,
          ${input.approvalExpectedVersion}::bigint,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return result(rows as unknown as Record<string, unknown>[]);
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
          ${input.actorAccountId}::uuid,
          'Admin'::character varying,
          ${input.subscriptionId}::uuid,
          ${input.expectedVersion}::bigint,
          ${input.cancelAtPeriodEnd}::boolean,
          ${input.reasonCode}::character varying,
          ${input.reasonText}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return result(rows as unknown as Record<string, unknown>[]);
    },
  };
}
