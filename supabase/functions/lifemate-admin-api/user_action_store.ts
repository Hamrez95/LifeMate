import { getAdminSql } from "./database_client.ts";
import {
  assertUserAccountActionResult,
  type UserAccountAction,
} from "./user_actions.ts";

export function createUserAccountActionStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  return {
    async execute(input: {
      actorAccountId: string;
      targetAccountId: string;
      action: UserAccountAction;
      reason: string;
      correlationId: string;
      idempotencyKey: string;
      requestHash: string;
    }) {
      const rows = await sql`
        select admin.execute_user_account_action(
          ${input.actorAccountId}::uuid,
          ${input.targetAccountId}::uuid,
          ${input.action}::character varying,
          ${input.reason}::character varying,
          ${input.correlationId}::uuid,
          ${input.idempotencyKey}::character varying,
          ${input.requestHash}::character varying
        ) as result
      `;
      return assertUserAccountActionResult(rows[0]?.result);
    },
  };
}
