import { createBootstrapIdentityStateReader } from "./identity_resolver.ts";
import { ApiError } from "./validation.ts";

/**
 * Fails closed when an existing authentication subject belongs to an account
 * that is no longer allowed to bootstrap. In particular, a deletion-pending
 * account must never be silently reactivated by the idempotent bootstrap path.
 */
export function createBootstrapAccountStateGuard(databaseUrl: string) {
  const identityState = createBootstrapIdentityStateReader(databaseUrl);

  async function assertAllowed(authSubject: string): Promise<void> {
    const row = await identityState.read(authSubject);
    if (!row) return;

    if (row.accountStatus === "DeletionPending") {
      throw new ApiError(
        409,
        "account_deletion_pending",
        "Account deletion is still being processed.",
      );
    }

    if (
      row.accountStatus === "Deleted" ||
      row.appUserStatus === "Deleted"
    ) {
      throw new ApiError(
        409,
        "account_deleted",
        "The previous LifeMate account has been deleted.",
      );
    }

    if (
      row.appUserStatus !== "Active" ||
      (row.accountStatus != null && row.accountStatus !== "Active")
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
