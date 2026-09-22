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

function resultOrThrow(
  result: Record<string, unknown>,
): Record<string, unknown> {
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

function iso(value: unknown): string | null {
  if (value == null) return null;
  const date = new Date(String(value));
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function mapExecution(row: Record<string, unknown>) {
  return {
    id: String(row.id),
    campaignId: String(row.campaign_id),
    audienceSnapshotId: String(row.audience_snapshot_id),
    campaignUpdatedAtUtc: iso(row.campaign_updated_at_utc),
    status: String(row.status),
    audienceCount: Number(row.audience_count),
    eligibleSmsCount: Number(row.eligible_sms_count),
    eligiblePushCount: Number(row.eligible_push_count),
    optedOutSmsCount: Number(row.opted_out_sms_count),
    optedOutPushCount: Number(row.opted_out_push_count),
    estimatedSmsCostMinor: row.estimated_sms_cost_minor == null
      ? null
      : String(row.estimated_sms_cost_minor),
    estimatedSmsCostCurrency: row.estimated_sms_cost_currency == null
      ? null
      : String(row.estimated_sms_cost_currency),
    smsProvider: row.sms_provider == null ? null : String(row.sms_provider),
    requiresSecondConfirmation: Boolean(row.requires_second_confirmation),
    confirmed: row.confirmed_at_utc != null,
    confirmedAtUtc: iso(row.confirmed_at_utc),
    scheduledAtUtc: iso(row.scheduled_at_utc),
    version: Number(row.version),
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

export function createCampaignOrchestratorStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  async function getExecution(executionId: string) {
    const rows = await sql`
      select id,campaign_id,audience_snapshot_id,campaign_updated_at_utc,status,
             audience_count,eligible_sms_count,eligible_push_count,
             opted_out_sms_count,opted_out_push_count,estimated_sms_cost_minor,
             estimated_sms_cost_currency,sms_provider,requires_second_confirmation,
             confirmed_at_utc,scheduled_at_utc,version,created_at_utc,updated_at_utc
      from messaging.campaign_executions
      where id=${executionId}::uuid
      limit 1
    `;
    return rows[0] ? mapExecution(rows[0]) : null;
  }

  async function listExecutions(campaignId: string) {
    const rows = await sql`
      select id,campaign_id,audience_snapshot_id,campaign_updated_at_utc,status,
             audience_count,eligible_sms_count,eligible_push_count,
             opted_out_sms_count,opted_out_push_count,estimated_sms_cost_minor,
             estimated_sms_cost_currency,sms_provider,requires_second_confirmation,
             confirmed_at_utc,scheduled_at_utc,version,created_at_utc,updated_at_utc
      from messaging.campaign_executions
      where campaign_id=${campaignId}::uuid
      order by created_at_utc desc,id desc
      limit 100
    `;
    return rows.map(mapExecution);
  }

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
    const result = resultOrThrow(rows[0]?.result ?? {});
    const executionId = typeof result.executionId === "string"
      ? result.executionId
      : null;
    if (!executionId) {
      throw new ApiError(
        503,
        "campaign_execution_workflow_unavailable",
        "Campaign execution preparation did not return an execution identifier.",
      );
    }
    const execution = await getExecution(executionId);
    if (!execution) {
      throw new ApiError(
        503,
        "campaign_execution_workflow_unavailable",
        "Prepared campaign execution could not be read back safely.",
      );
    }
    return {
      ...result,
      version: execution.version,
      createdAtUtc: execution.createdAtUtc,
    };
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

  return { getExecution, listExecutions, prepare, confirm, schedule, cancel };
}
