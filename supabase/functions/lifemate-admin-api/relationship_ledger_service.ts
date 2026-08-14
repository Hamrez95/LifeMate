import { getAdminSql } from "./database_client.ts";
import type { RelationshipLedgerQuery } from "./relationship_ledger.ts";
import { getRelationshipLedger } from "./relationship_ledger_store.ts";

export function createRelationshipLedgerStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    getLedger: (query: RelationshipLedgerQuery) =>
      getRelationshipLedger(sql, query),
  };
}
