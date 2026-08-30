import { getAdminSql } from "./database_client.ts";
import type { GiftTestFinalizePayload } from "./gift_test_operations.ts";
import { ApiError } from "./validation.ts";

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(503, "gift_test_finalize_unavailable", "Gift workflow returned an invalid result.");
  }
  return value as Record<string, unknown>;
}

export function createGiftTestOperationsStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    async finalize(input: {
      actorAccountId: string;
      payload: GiftTestFinalizePayload;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      return await sql.begin(async (tx) => {
        await tx`select pg_advisory_xact_lock(hashtextextended(${`${input.actorAccountId}:gift-test-finalize:${input.idempotencyKey}`},0))`;
        const existing = await tx`
          select id,metadata_json
          from admin.audit_events
          where actor_account_id=${input.actorAccountId}::uuid
            and action='commerce.gift.test_finalize'
            and request_id=${input.idempotencyKey}
          order by occurred_at desc
          limit 1
        `;
        if (existing[0]) {
          const metadata = existing[0].metadata_json as Record<string, unknown> | null;
          if (metadata?.requestHash !== input.requestHash) {
            throw new ApiError(409, "idempotency_conflict", "Idempotency-Key was already used for a different gift finalization.");
          }
          return {
            httpStatus: 200,
            code: "ok",
            giftIntentId: input.payload.giftIntentId,
            replayed: true,
          };
        }

        const rows = await tx`
          select growth.test_finalize_subscription_gift(
            ${input.payload.giftIntentId}::uuid,
            ${input.payload.transactionId}::uuid,
            ${input.payload.claimTokenHash}::varchar,
            ${input.payload.claimTtlHours}::integer
          ) as result
        `;
        const result = object(rows[0]?.result);
        const status = Number(result.httpStatus);
        if (!Number.isInteger(status)) {
          throw new ApiError(503, "gift_test_finalize_unavailable", "Gift workflow returned an invalid status.");
        }
        if (status >= 400) return result;

        await tx`
          insert into admin.audit_events(
            actor_account_id,action,resource_type,resource_id,result,correlation_id,request_id,elevated_access,metadata_json
          ) values(
            ${input.actorAccountId}::uuid,'commerce.gift.test_finalize','gift_intent',${input.payload.giftIntentId},
            'Succeeded',${input.correlationId}::uuid,${input.idempotencyKey},true,
            ${tx.json({requestHash:input.requestHash,transactionId:input.payload.transactionId,testOnly:true})}::jsonb
          )
        `;
        return {...result,replayed:false};
      });
    },
  };
}
