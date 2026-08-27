import { getAdminSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

function resultStatus(result: Record<string, unknown>): number {
  const value = Number(result.httpStatus);
  if (!Number.isInteger(value) || value < 100 || value > 599) {
    throw new ApiError(
      503,
      "campaign_execution_workflow_unavailable",
      "Campaign execution workflow returned an invalid status.",
    );
  }
  return value;
}

function resultOrThrow(result: Record<string, unknown>): Record<string, unknown> {
  const status = resultStatus(result);
  if (status >= 400) {
    throw new ApiError(
      status,
      typeof result.code === "string"
        ? result.code
        : "campaign_execution_workflow_unavailable",
      typeof result.message === "string"
        ? result.message
        : "Campaign execution workflow was not completed.",
    );
  }
  return result;
}

export function createCampaignOrchestratorStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  async function prepare(input: {
    actorAccountId: string;
    campaignId: string;
    audienceSnapshotId: string;
    campaignUpdatedAtUtc: string;
    channels: string[];
    smsProvider: string | null;
    smsCurrency: string | null;
    correlationId: string;
  }) {
    const rows = await sql`
      select messaging.prepare_campaign_execution_v2(
        ${input.actorAccountId}::uuid,
        ${input.campaignId}::uuid,
        ${input.audienceSnapshotId}::uuid,
        ${input.campaignUpdatedAtUtc}::timestamptz,
        ${input.channels}::varchar[],
        ${input.smsProvider}::varchar,
        ${input.smsCurrency}::varchar,
        ${input.correlationId}::uuid
      ) as result
    `;
    return resultOrThrow(rows[0]?.result ?? {});
  }

  async function confirm(input: {
    actorAccountId: string;
    executionId: string;
    expectedVersion: number;
    correlationId: string;
  }) {
    const rows = await sql`
      select messaging.confirm_campaign_execution(
        ${input.actorAccountId}::uuid,
        ${input.executionId}::uuid,
        ${input.expectedVersion}::bigint,
        ${input.correlationId}::uuid
      ) as result
    `;
    return resultOrThrow(rows[0]?.result ?? {});
  }

  async function schedule(input: {
    actorAccountId: string;
    executionId: string;
    expectedVersion: number;
    scheduledAtUtc: string;
    correlationId: string;
  }) {
    const rows = await sql`
      select messaging.schedule_campaign_execution(
        ${input.actorAccountId}::uuid,
        ${input.executionId}::uuid,
        ${input.expectedVersion}::bigint,
        ${input.scheduledAtUtc}::timestamptz,
        ${input.correlationId}::uuid
      ) as result
    `;
    return resultOrThrow(rows[0]?.result ?? {});
  }

  async function cancel(input: {
    actorAccountId: string;
    executionId: string;
    expectedVersion: number;
    reason: string;
    correlationId: string;
  }) {
    const rows = await sql`
      select messaging.cancel_campaign_execution(
        ${input.actorAccountId}::uuid,
        ${input.executionId}::uuid,
        ${input.expectedVersion}::bigint,
        ${input.reason}::varchar,
        ${input.correlationId}::uuid
      ) as result
    `;
    return resultOrThrow(rows[0]?.result ?? {});
  }

  return { prepare, confirm, schedule, cancel };
}
