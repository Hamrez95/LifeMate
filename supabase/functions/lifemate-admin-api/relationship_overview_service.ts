import { getAdminSql } from "./database_client.ts";
import { getRelationshipOverview } from "./relationship_overview_store.ts";
import type { RelationshipOverviewQuery } from "./relationships.ts";

export function createRelationshipOverviewStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    getOverview: (query: RelationshipOverviewQuery) => getRelationshipOverview(sql, query),
  };
}
