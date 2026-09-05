import { getAdminSql } from "./database_client.ts";
import type { StaffDirectoryQuery } from "./staff_directory.ts";
import {
  auditStaffDetailRead,
  getStaffDetail,
  listStaffDirectory,
} from "./staff_directory_store.ts";

export function createStaffDirectoryStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);
  return {
    list: (query: StaffDirectoryQuery) => listStaffDirectory(sql, query),
    getDetail: (accountId: string) => getStaffDetail(sql, accountId),
    auditDetailRead: (
      actorAccountId: string,
      targetAccountId: string,
      correlationId: string,
    ) =>
      auditStaffDetailRead(sql, actorAccountId, targetAccountId, correlationId),
  };
}
