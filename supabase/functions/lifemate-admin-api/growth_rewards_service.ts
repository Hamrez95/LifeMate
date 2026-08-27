import { getAdminSql } from "./database_client.ts";
import type { RewardIssuePayload } from "./growth_rewards.ts";
import { ApiError } from "./validation.ts";

function result(value: unknown, code: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(503, code, "Growth reward workflow returned an invalid result.");
  }
  return value as Record<string, unknown>;
}

function status(value: Record<string, unknown>): number {
  const parsed = Number(value.httpStatus);
  if (!Number.isInteger(parsed) || parsed < 100 || parsed > 599) {
    throw new ApiError(503, "growth_reward_workflow_unavailable", "Growth reward workflow returned an invalid status.");
  }
  return parsed;
}

export function createGrowthRewardAdminStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  async function previewWith(client: typeof sql, payload: RewardIssuePayload) {
    const rows = await client`
      select growth.preview_reward_issue(
        ${payload.beneficiaryAccountId}::uuid,${payload.sourceKind}::varchar,${payload.sourceId}::uuid,
        ${payload.rewardRuleId}::uuid,${payload.expectedRuleVersion}::bigint,${payload.provenanceHash}::varchar
      ) as result
    `;
    return result(rows[0]?.result, "growth_reward_preview_unavailable");
  }

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
               status,fulfillment_state,approval_request_id,issued_by_account_id,created_at_utc,issued_at_utc,reversed_at_utc
        from growth.reward_events order by created_at_utc desc,id desc limit ${limit}
      `;
    },

    async upsertRule(input: {
      actorAccountId: string;
      payload: {
        id: string | null; code: string; triggerKind: string; rewardKind: string;
        rewardConfig: Record<string, unknown>; maxIssuesPerAccount: number | null;
        status: string; expectedVersion: number | null; reason: string;
      };
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const p = input.payload;
      const rows = await sql`
        select growth.upsert_reward_rule(
          ${input.actorAccountId}::uuid,${p.id}::uuid,${p.code}::varchar,${p.triggerKind}::varchar,
          ${p.rewardKind}::varchar,${sql.json(p.rewardConfig)}::jsonb,${p.maxIssuesPerAccount}::integer,
          ${p.status}::varchar,${p.expectedVersion}::bigint,${p.reason}::varchar,${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,${input.requestHash}::varchar
        ) as result
      `;
      return result(rows[0]?.result, "growth_reward_rule_unavailable");
    },

    async reviewAdvocacy(input: {
      actorAccountId: string; submissionId: string; expectedVersion: number;
      decision: string; reason: string; correlationId: string; idempotencyKey: string; requestHash: string;
    }) {
      const rows = await sql`
        select growth.review_advocacy_submission(
          ${input.actorAccountId}::uuid,${input.submissionId}::uuid,${input.expectedVersion}::bigint,
          ${input.decision}::varchar,${input.reason}::varchar,${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,${input.requestHash}::varchar
        ) as result
      `;
      return result(rows[0]?.result, "growth_advocacy_review_unavailable");
    },

    async requestIssue(input: {
      actorAccountId: string; payload: RewardIssuePayload; correlationId: string;
      idempotencyKey: string; requestHash: string;
    }) {
      const preview = await previewWith(sql, input.payload);
      if (status(preview) >= 400) return preview;
      const rows = await sql`
        select admin.create_approval_request(
          ${input.actorAccountId}::uuid,'growth_reward_issue'::varchar,'account'::varchar,
          ${input.payload.beneficiaryAccountId}::varchar,
          ${sql.json(preview.before as Record<string, unknown>)}::jsonb,
          ${sql.json(preview.delta as Record<string, unknown>)}::jsonb,
          ${sql.json(preview.after as Record<string, unknown>)}::jsonb,
          ${input.payload.reason}::varchar,${input.correlationId}::uuid,
          ${input.idempotencyKey}::varchar,${input.requestHash}::varchar
        ) as result
      `;
      return result(rows[0]?.result, "growth_reward_approval_unavailable");
    },

    async executeIssue(input: {
      actorAccountId: string;
      payload: RewardIssuePayload & { approvalRequestId: string; approvalExpectedVersion: number };
      correlationId: string; idempotencyKey: string; requestHash: string;
    }) {
      try {
        const p = input.payload;
        const rows = await sql`
          select growth.execute_reward_issue(
            ${input.actorAccountId}::uuid,${p.beneficiaryAccountId}::uuid,${p.sourceKind}::varchar,${p.sourceId}::uuid,
            ${p.rewardRuleId}::uuid,${p.expectedRuleVersion}::bigint,${p.provenanceHash}::varchar,
            ${p.approvalRequestId}::uuid,${p.approvalExpectedVersion}::bigint,${p.reason}::varchar,
            ${input.correlationId}::uuid,${input.idempotencyKey}::varchar,${input.requestHash}::varchar
          ) as result
        `;
        return result(rows[0]?.result, "growth_reward_issue_unavailable");
      } catch (error) {
        const value = error as { code?: string };
        if (value.code === "42501") throw new ApiError(403, "growth_reward_execution_denied", "Actor cannot execute this reward.");
        if (["40001", "55000", "P0002", "22023"].includes(String(value.code))) {
          throw new ApiError(409, "growth_reward_state_conflict", "Reward, approval, or entitlement state changed; refresh before retrying.");
        }
        throw error;
      }
    },
  };
}
