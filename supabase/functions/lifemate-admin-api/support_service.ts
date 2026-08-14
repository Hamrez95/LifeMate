import { getAdminSql } from "./database_client.ts";
import type { SupportQueueQuery } from "./support.ts";
import { listSupportQueue } from "./support_store.ts";

export function createSupportQueueStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    list: (query: SupportQueueQuery) => listSupportQueue(sql, query),
  };
}
