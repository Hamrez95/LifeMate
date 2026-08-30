import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

export function createCommerceSubscriptionStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  return {
    async snapshot(appUserId: string) {
      const rows = await sql`
        select commerce.mobile_subscription_snapshot(${appUserId}::uuid) as payload
      `;
      const payload = rows[0]?.payload;
      if (!payload || typeof payload !== "object") {
        throw new ApiError(503,"commerce_unavailable","Subscription information is temporarily unavailable.");
      }
      const body = payload as Record<string, unknown>;
      const status = Number(body.httpStatus ?? 500);
      if (status >= 400) {
        throw new ApiError(status,String(body.code ?? "commerce_unavailable"),"Subscription information is temporarily unavailable.");
      }
      return body;
    },
  };
}
