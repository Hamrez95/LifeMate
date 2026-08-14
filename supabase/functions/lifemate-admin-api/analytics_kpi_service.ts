import { getAdminSql } from "./database_client.ts";
import type { AnalyticsKpiQuery } from "./analytics_kpis.ts";
import { getKpiValues } from "./analytics_kpi_store.ts";

export function createAnalyticsKpiStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    getValues: (query: AnalyticsKpiQuery) => getKpiValues(sql, query),
  };
}
