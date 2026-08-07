import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

export function createAccountLifecycleStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function requestDeletion(accountId: string): Promise<Record<string, unknown>> {
    let rows;
    try {
      rows = await sql`
        select identity.request_account_deletion(${accountId}::uuid) as request_id
      `;
    } catch (error) {
      if (String((error as Record<string, unknown>)?.message ?? "").includes("account_not_found")) {
        throw new ApiError(404, "account_not_found", "Account was not found.");
      }
      throw error;
    }
    const requestId = rows[0]?.request_id;
    if (typeof requestId !== "string") {
      throw new ApiError(500, "deletion_request_failed", "Deletion request could not be created.");
    }
    return {
      id: requestId,
      status: "requested",
      accountId,
    };
  }

  async function latestDeletionRequest(accountId: string): Promise<Record<string, unknown> | null> {
    const rows = await sql`
      select * from identity.latest_account_deletion_request(${accountId}::uuid)
    `;
    const row = rows[0] as Row | undefined;
    if (!row) return null;
    return {
      id: row.id,
      status: String(row.status ?? "").toLowerCase(),
      requestedAtUtc: isoOrNull(row.requested_at_utc),
      processingStartedAtUtc: isoOrNull(row.processing_started_at_utc),
      completedAtUtc: isoOrNull(row.completed_at_utc),
      retentionPolicyVersion: row.retention_policy_version,
    };
  }

  return { requestDeletion, latestDeletionRequest };
}

function isoOrNull(value: unknown): string | null {
  if (value == null) return null;
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}
