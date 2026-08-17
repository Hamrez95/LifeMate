import { getAdminSql } from "./database_client.ts";
import type {
  MarketingContentCalendarQuery,
  MarketingExecutionActionPayload,
  MarketingSchedulePayload,
} from "./marketing_content_calendar.ts";
import { ApiError } from "./validation.ts";

type CalendarRow = {
  execution_id: string;
  campaign_id: string;
  campaign_name: string;
  campaign_status: string;
  provider_code: string;
  content_revision: number | string;
  approval_state: string | null;
  publish_status: string;
  scheduled_for_utc: Date | string | null;
  schedule_timezone: string | null;
  requested_at_utc: Date | string;
  started_at_utc: Date | string | null;
  completed_at_utc: Date | string | null;
  cancelled_at_utc: Date | string | null;
  failure_code: string | null;
  provider_post_ref: string | null;
  retry_of_execution_id: string | null;
};

type ApprovalRow = {
  campaign_id: string;
  campaign_name: string;
  campaign_status: string;
  provider_code: string | null;
  content_revision: number | string;
  approval_state: "Pending" | "Approved" | "Revoked";
  updated_at_utc: Date | string;
  approved_at_utc: Date | string | null;
  publish_text_preview: string;
  operator_status: "Enabled" | "Disabled" | null;
  setup_status: "SetupRequired" | "CredentialAvailable" | "Disabled" | null;
  credential_available: boolean | null;
};

function iso(value: Date | string | null): string | null {
  if (value == null) return null;
  return value instanceof Date
    ? value.toISOString()
    : new Date(value).toISOString();
}

function mutation(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "marketing_calendar_workflow_unavailable",
      "Marketing calendar workflow result was unavailable.",
    );
  }
  const result = value as Record<string, unknown>;
  if (
    !Number.isInteger(result.httpStatus) ||
    typeof result.code !== "string" ||
    typeof result.replayed !== "boolean"
  ) {
    throw new ApiError(
      503,
      "marketing_calendar_workflow_unavailable",
      "Marketing calendar workflow result was invalid.",
    );
  }
  return result;
}

export function createMarketingContentCalendarStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async list(query: MarketingContentCalendarQuery) {
      const [calendarRows, approvalRows] = await Promise.all([
        sql<CalendarRow[]>`
          select execution_id,campaign_id,campaign_name,campaign_status,provider_code,content_revision,
                 approval_state,publish_status,scheduled_for_utc,schedule_timezone,requested_at_utc,
                 started_at_utc,completed_at_utc,cancelled_at_utc,failure_code,provider_post_ref,retry_of_execution_id
          from admin.marketing_content_calendar_v1
          where coalesce(scheduled_for_utc,requested_at_utc) >= (${query.from}::date::timestamp at time zone ${query.timezone})
            and coalesce(scheduled_for_utc,requested_at_utc) < ((${query.to}::date + 1)::timestamp at time zone ${query.timezone})
            and (${query.status}::varchar is null or publish_status=${query.status}::varchar)
          order by coalesce(scheduled_for_utc,requested_at_utc),execution_id
          limit 500
        `,
        sql<ApprovalRow[]>`
          select q.campaign_id,q.campaign_name,q.campaign_status,q.provider_code,q.content_revision,
                 q.approval_state,q.updated_at_utc,q.approved_at_utc,q.publish_text_preview,
                 c.operator_status,c.setup_status,c.credential_available
          from admin.marketing_content_approval_queue_v1 q
          left join admin.marketing_channel_connections_v1 c on c.provider_code=q.provider_code
          order by
            case q.approval_state when 'Pending' then 0 when 'Revoked' then 1 else 2 end,
            q.updated_at_utc desc,q.campaign_id
          limit 200
        `,
      ]);

      return {
        query,
        items: calendarRows.map((row) => ({
          executionId: row.execution_id,
          campaignId: row.campaign_id,
          campaignName: row.campaign_name,
          campaignStatus: row.campaign_status,
          providerCode: row.provider_code,
          contentRevision: Number(row.content_revision),
          approvalState: row.approval_state,
          publishStatus: row.publish_status,
          scheduledForUtc: iso(row.scheduled_for_utc),
          scheduleTimezone: row.schedule_timezone,
          requestedAtUtc: iso(row.requested_at_utc)!,
          startedAtUtc: iso(row.started_at_utc),
          completedAtUtc: iso(row.completed_at_utc),
          cancelledAtUtc: iso(row.cancelled_at_utc),
          failureCode: row.failure_code,
          providerPostRef: row.provider_post_ref,
          retryOfExecutionId: row.retry_of_execution_id,
          providerConnectivity: "NotVerified" as const,
        })),
        approvalQueue: approvalRows.map((row) => ({
          campaignId: row.campaign_id,
          campaignName: row.campaign_name,
          campaignStatus: row.campaign_status,
          providerCode: row.provider_code,
          contentRevision: Number(row.content_revision),
          approvalState: row.approval_state,
          updatedAtUtc: iso(row.updated_at_utc)!,
          approvedAtUtc: iso(row.approved_at_utc),
          publishTextPreview: row.publish_text_preview,
          channel: row.provider_code
            ? {
              operatorStatus: row.operator_status ?? "Disabled",
              setupStatus: row.setup_status ?? "SetupRequired",
              credentialAvailable: row.credential_available === true,
              providerConnectivity: "NotVerified" as const,
            }
            : null,
        })),
        freshness: {
          status: "fresh" as const,
          asOfUtc: new Date().toISOString(),
          source:
            "admin.marketing_content_calendar_v1 + admin.marketing_content_approval_queue_v1",
        },
      };
    },

    async schedule(input: {
      actorAccountId: string;
      campaignId: string;
      payload: MarketingSchedulePayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.schedule_marketing_campaign_publish(
          ${input.actorAccountId}::uuid,
          ${input.campaignId}::uuid,
          ${input.payload.scheduledLocal}::timestamp,
          ${input.payload.timezone}::varchar,
          ${input.payload.reason}::varchar,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return mutation(rows[0]?.result);
    },

    async cancel(input: {
      actorAccountId: string;
      executionId: string;
      payload: MarketingExecutionActionPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.cancel_marketing_campaign_publish(
          ${input.actorAccountId}::uuid,
          ${input.executionId}::uuid,
          ${input.payload.reason}::varchar,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return mutation(rows[0]?.result);
    },

    async retry(input: {
      actorAccountId: string;
      executionId: string;
      payload: MarketingExecutionActionPayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.retry_marketing_campaign_publish(
          ${input.actorAccountId}::uuid,
          ${input.executionId}::uuid,
          ${input.payload.reason}::varchar,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return mutation(rows[0]?.result);
    },
  };
}
