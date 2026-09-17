import { createBootstrapIdentityStateLookup } from "./identity_resolver.ts";
import { ApiError } from "./validation.ts";

/**
 * Fails closed when an existing authentication subject belongs to an account
 * that is no longer allowed to bootstrap. In particular, a deletion-pending
 * account must never be silently reactivated by the idempotent bootstrap path.
 */
export function createBootstrapAccountStateGuard(databaseUrl: string) {
  const identityState = createBootstrapIdentityStateLookup(databaseUrl);

  async function assertAllowed(authSubject: string): Promise<void> {
    const rows = await identityState.findByAuthSubject(authSubject);

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
