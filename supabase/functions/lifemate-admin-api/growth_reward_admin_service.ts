import { getAdminSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

function object(value: unknown, code: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      code,
      "Growth reward workflow returned an invalid result.",
    );
  }
  return value as Record<string, unknown>;
}

function httpStatus(value: Record<string, unknown>): number {
  const status = Number(value.httpStatus);
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ApiError(
      503,
      "growth_reward_workflow_unavailable",
      "Growth reward workflow returned an invalid status.",
    );
  }
  return status;
}

export function createGrowthRewardAdminStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async listRules(limit: number) {
      return await sql`
        select id,code,trigger_kind,reward_kind,reward_config,max_issues_per_account,status,version,created_at_utc,updated_at_utc
        from growth.reward_rules order by updated_at_utc desc,id desc limit ${limit}
      `;
    },
    async listEvents(limit: number) {
      return await sql`
        select id,beneficiary_account_id,source_kind,source_id,reward_rule_id,reward_rule_version,reward_kind,
               status,version,approval_request_id,created_at_utc,issued_at_utc,reversed_at_utc
        from growth.reward_events order by created_at_utc desc,id desc limit ${limit}
      `;
    },
    async listSources(kind: "Referral" | "Advocacy", limit: number) {
      if (kind === "Referral") {
        return await sql`
          select id,status,version,attributed_at_utc,qualified_at_utc
          from growth.referral_attributions
          where status in ('Attributed','PendingReview')
          order by attributed_at_utc asc,id asc limit ${limit}
        `;
      }
      return await sql`
        select id,platform_code,evidence_type,evidence_source,status,version,created_at_utc
        from growth.advocacy_submissions where status='PendingReview'
        order by created_at_utc asc,id asc limit ${limit}
      `;
    },
    async upsertRule(input: {
      actorAccountId: string;
      payload: {
        code: string;
        triggerKind: string;
        rewardKind: string;
        rewardConfig: Record<string, unknown>;
        maxIssuesPerAccount: number | null;
        status: string;
        expectedVersion: number;
        reason: string;
      };
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.upsert_growth_reward_rule(
          ${input.actorAccountId}::uuid,${p.code}::varchar,${p.triggerKind}::varchar,${p.rewardKind}::varchar,
          ${
        sql.json(p.rewardConfig)
      }::jsonb,${p.maxIssuesPerAccount}::integer,${p.status}::varchar,
          ${p.expectedVersion}::bigint,${p.reason}::varchar,${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,${input.requestHash}::varchar
        ) as result
      `;
      return object(rows[0]?.result, "growth_reward_rule_unavailable");
    },
    async createEvent(input: {
      actorAccountId: string;
      payload: {
        beneficiaryAccountId: string;
        sourceKind: string;
        sourceId: string;
        ruleCode: string;
        reason: string;
      };
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select admin.create_growth_reward_event(
          ${input.actorAccountId}::uuid,${p.beneficiaryAccountId}::uuid,${p.sourceKind}::varchar,
          ${p.sourceId}::uuid,${p.ruleCode}::varchar,${p.reason}::varchar,${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,${input.requestHash}::varchar
        ) as result
      `;
      return object(rows[0]?.result, "growth_reward_event_unavailable");
    },
    async reviewSource(input: {
      actorAccountId: string;
      sourceKind: "Referral" | "Advocacy";
      sourceId: string;
      expectedVersion: number;
      decision: string;
      reason: string;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.review_growth_reward_source(
          ${input.actorAccountId}::uuid,${input.sourceKind}::varchar,${input.sourceId}::uuid,
          ${input.expectedVersion}::bigint,${input.decision}::varchar,${input.reason}::varchar,
          ${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar
        ) as result
      `;
      return object(rows[0]?.result, "growth_reward_source_review_unavailable");
    },
    async requestFulfillment(input: {
      actorAccountId: string;
      rewardEventId: string;
      expectedVersion: number;
      reason: string;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const previewRows = await sql`
        select admin.preview_growth_reward_fulfillment(${input.rewardEventId}::uuid,${input.expectedVersion}::bigint) as result
      `;
      const preview = object(
        previewRows[0]?.result,
        "growth_reward_fulfillment_preview_unavailable",
      );
      if (httpStatus(preview) >= 400) return preview;
      const rows = await sql`
        select admin.create_approval_request(
          ${input.actorAccountId}::uuid,'growth_reward_fulfillment'::varchar,'growth_reward_event'::varchar,
          ${input.rewardEventId}::varchar,${
        sql.json(preview.before as Record<string, unknown>)
      }::jsonb,
          ${sql.json(preview.delta as Record<string, unknown>)}::jsonb,${
        sql.json(preview.after as Record<string, unknown>)
      }::jsonb,
          ${input.reason}::varchar,${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar
        ) as result
      `;
      return object(
        rows[0]?.result,
        "growth_reward_fulfillment_approval_unavailable",
      );
    },
    async executeFulfillment(input: {
      actorAccountId: string;
      rewardEventId: string;
      expectedVersion: number;
      approvalRequestId: string;
      approvalExpectedVersion: number;
      reason: string;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      try {
        const rows = await sql`
          select admin.execute_growth_reward_fulfillment(
            ${input.actorAccountId}::uuid,${input.rewardEventId}::uuid,${input.expectedVersion}::bigint,
            ${input.approvalRequestId}::uuid,${input.approvalExpectedVersion}::bigint,${input.reason}::varchar,
            ${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar
          ) as result
        `;
        return object(rows[0]?.result, "growth_reward_fulfillment_unavailable");
      } catch (error) {
        const code = String((error as { code?: string }).code ?? "");
        if (code === "42501") {
          throw new ApiError(
            403,
            "growth_reward_fulfillment_denied",
            "Actor lacks canonical fulfillment authority.",
          );
        }
        if (["40001", "55000", "P0002", "22023"].includes(code)) {
          throw new ApiError(
            409,
            "growth_reward_fulfillment_conflict",
            "Reward or approval state changed; refresh before retrying.",
          );
        }
        throw error;
      }
    },
  };
}
