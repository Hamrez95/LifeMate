import { getAdminSql } from "./database_client.ts";

function requiredObject(value: unknown, code: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(code);
  return value as Record<string, unknown>;
}

export function createPrivacyLegalAdminStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async snapshot(actorAccountId: string, jurisdiction: string) {
      const rows = await sql`
        select admin.privacy_legal_snapshot(
          ${actorAccountId}::uuid,
          ${jurisdiction}::varchar
        ) as result
      `;
      return requiredObject(rows[0]?.result, "privacy_legal_snapshot_invalid");
    },
    async publish(input: {
      actorAccountId: string;
      purpose: string;
      version: string;
      jurisdiction: string;
      title: string;
      documentHash: string;
      contentUri: string;
      effectiveAtUtc: string;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.publish_legal_document_idempotent(
          ${input.actorAccountId}::uuid,
          ${input.purpose}::varchar,
          ${input.version}::varchar,
          ${input.jurisdiction}::varchar,
          ${input.title}::varchar,
          ${input.documentHash}::varchar,
          ${input.contentUri}::text,
          ${input.effectiveAtUtc}::timestamptz,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return requiredObject(rows[0]?.result, "legal_document_publish_result_invalid");
    },
    async retire(input: {
      actorAccountId: string;
      documentId: string;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.retire_legal_document_idempotent(
          ${input.actorAccountId}::uuid,
          ${input.documentId}::uuid,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return requiredObject(rows[0]?.result, "legal_document_retire_result_invalid");
    },
    async updatePurpose(input: {
      actorAccountId: string;
      purpose: string;
      policyVersion: string;
      description: string;
      status: string;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.update_privacy_purpose_idempotent(
          ${input.actorAccountId}::uuid,
          ${input.purpose}::varchar,
          ${input.policyVersion}::varchar,
          ${input.description}::varchar,
          ${input.status}::varchar,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return requiredObject(rows[0]?.result, "privacy_purpose_update_result_invalid");
    },
  };
}
