import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

type BootstrapStateRow = {
  app_user_status: string;
  account_status: string | null;
};

/**
 * Fails closed when an existing authentication subject belongs to an account
 * that is no longer allowed to bootstrap. In particular, a deletion-pending
 * account must never be silently reactivated by the idempotent bootstrap path.
 */
export function createBootstrapAccountStateGuard(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function assertAllowed(authSubject: string): Promise<void> {
    const rows = await sql<BootstrapStateRow[]>`
      select
        u.status as app_user_status,
        a.status as account_status
      from lifemate.app_users u
      left join lateral (
        select candidate.status
        from identity.accounts candidate
        where candidate.legacy_app_user_id=u.id
           or (candidate.legacy_app_user_id is null and candidate.id=u.id)
        order by case when candidate.legacy_app_user_id=u.id then 0 else 1 end,
                 candidate.updated_at_utc desc,
                 candidate.id
        limit 1
      ) a on true
      where u.auth_subject=${authSubject}
      limit 2
    `;

    if (rows.length > 1) {
      throw new ApiError(
        409,
        "bootstrap_identity_ambiguous",
        "The LifeMate identity mapping is inconsistent.",
      );
    }

    const row = rows[0];
    if (!row) return;

    if (row.account_status === "DeletionPending") {
      throw new ApiError(
        409,
        "account_deletion_pending",
        "Account deletion is still being processed.",
      );
    }

    if (
      row.account_status === "Deleted" ||
      row.app_user_status === "Deleted"
    ) {
      throw new ApiError(
        409,
        "account_deleted",
        "The previous LifeMate account has been deleted.",
      );
    }

    if (
      row.app_user_status !== "Active" ||
      (row.account_status != null && row.account_status !== "Active")
    ) {
      throw new ApiError(
        409,
        "account_disabled",
        "The LifeMate account is not active.",
      );
    }
  }

  return { assertAllowed };
}
