import { getAdminSql } from "./database_client.ts";
import { getUserAdminActivitySummary } from "./user_detail_activity.ts";
import { getUserDetailBase, listUserEnrollments } from "./user_detail_base.ts";
import { getUserCommerceSummary } from "./user_detail_commerce.ts";
import { getUserRelationshipSummary } from "./user_detail_relationships.ts";

export function createUserDetailStore(databaseUrl: string) {
  const sql = getAdminSql(databaseUrl);

  return {
    getBase: (accountId: string) => getUserDetailBase(sql, accountId),
    listEnrollments: (accountId: string) => listUserEnrollments(sql, accountId),
    getCommerce: (accountId: string, personId: string | null) =>
      getUserCommerceSummary(sql, accountId, personId),
    getRelationships: (personId: string | null) =>
      getUserRelationshipSummary(sql, personId),
    getAdminActivity: (accountId: string) =>
      getUserAdminActivitySummary(sql, accountId),
  };
}
