import type { CommerceDashboardQuery } from "./commerce.ts";
import { getAdminSql } from "./database_client.ts";
import { getCommerceDashboard } from "./commerce_store.ts";

export function createCommerceDashboardStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    get: (query: CommerceDashboardQuery) => getCommerceDashboard(sql, query),
  };
}
