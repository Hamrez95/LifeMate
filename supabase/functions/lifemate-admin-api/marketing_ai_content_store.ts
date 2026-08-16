import { getAdminSql } from "./database_client.ts";
import type {
  MarketingAiContentPayload,
  MarketingAiContentVariant,
} from "./marketing_ai_content.ts";
import { ApiError } from "./validation.ts";

type GenerationRow = {
  id: string;
  campaign_id: string;
  requested_by_admin_account_id: string;
  goal: MarketingAiContentPayload["goal"];
  tone: MarketingAiContentPayload["tone"];
  language: MarketingAiContentPayload["language"];
  key_message: string | null;
  call_to_action: string | null;
  variants_json: unknown;
  generation_mode: "deterministic_fallback" | "model";
  model_status: "not_configured" | "available" | "unavailable";
  created_at_utc: Date | string;
};

function iso(value: Date | string): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(value).toISOString();
}

function variants(value: unknown): MarketingAiContentVariant[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is MarketingAiContentVariant => {
    if (!item || typeof item !== "object" || Array.isArray(item)) return false;
    const row = item as Record<string, unknown>;
    return (
      typeof row.id === "string" &&
      typeof row.headline === "string" &&
      typeof row.body === "string" &&
      (row.callToAction === null || typeof row.callToAction === "string") &&
      Array.isArray(row.hashtags) &&
      row.hashtags.every((tag) => typeof tag === "string") &&
      typeof row.rationale === "string"
    );
  });
}

function mutation(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      503,
      "marketing_ai_content_unavailable",
      "Content Studio persistence returned an invalid result.",
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
      "marketing_ai_content_unavailable",
      "Content Studio persistence returned an invalid result.",
    );
  }
  return result;
}

export function createMarketingAiContentStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async list(campaignId: string, limit = 12) {
      const bounded = Math.max(1, Math.min(20, limit));
      const rows = await sql<GenerationRow[]>`
        select id,campaign_id,requested_by_admin_account_id,goal,tone,language,
               key_message,call_to_action,variants_json,generation_mode,model_status,created_at_utc
        from admin.marketing_ai_content_generations_v1
        where campaign_id=${campaignId}::uuid
        order by created_at_utc desc,id desc
        limit ${bounded}
      `;
      return rows.map((row) => ({
        id: row.id,
        campaignId: row.campaign_id,
        requestedByAdminAccountId: row.requested_by_admin_account_id,
        goal: row.goal,
        tone: row.tone,
        language: row.language,
        keyMessage: row.key_message,
        callToAction: row.call_to_action,
        variants: variants(row.variants_json),
        generationMode: row.generation_mode,
        modelStatus: row.model_status,
        createdAtUtc: iso(row.created_at_utc),
      }));
    },

    async get(campaignId: string, generationId: string) {
      const rows = await sql<GenerationRow[]>`
        select id,campaign_id,requested_by_admin_account_id,goal,tone,language,
               key_message,call_to_action,variants_json,generation_mode,model_status,created_at_utc
        from admin.marketing_ai_content_generations_v1
        where campaign_id=${campaignId}::uuid and id=${generationId}::uuid
        limit 1
      `;
      const row = rows[0];
      if (!row) return null;
      return {
        id: row.id,
        campaignId: row.campaign_id,
        requestedByAdminAccountId: row.requested_by_admin_account_id,
        goal: row.goal,
        tone: row.tone,
        language: row.language,
        keyMessage: row.key_message,
        callToAction: row.call_to_action,
        variants: variants(row.variants_json),
        generationMode: row.generation_mode,
        modelStatus: row.model_status,
        createdAtUtc: iso(row.created_at_utc),
      };
    },

    async record(input: {
      actorAccountId: string;
      campaignId: string;
      payload: MarketingAiContentPayload;
      generatedVariants: MarketingAiContentVariant[];
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.record_marketing_ai_content_generation(
          ${input.actorAccountId}::uuid,
          ${input.campaignId}::uuid,
          ${input.payload.goal}::varchar,
          ${input.payload.tone}::varchar,
          ${input.payload.language}::varchar,
          ${input.payload.keyMessage}::varchar,
          ${input.payload.callToAction}::varchar,
          ${JSON.stringify(input.generatedVariants)}::jsonb,
          'deterministic_fallback'::varchar,
          'not_configured'::varchar,
          ${input.idempotencyKey}::varchar,
          ${input.requestHash}::varchar
        ) as result
      `;
      return mutation(rows[0]?.result);
    },
  };
}
