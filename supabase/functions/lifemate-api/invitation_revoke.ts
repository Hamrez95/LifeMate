import { getLifeMateSql } from "./database_client.ts";
import { ApiError, requiredUuid } from "./validation.ts";

export function createInvitationRevocationStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function revokePendingInvitation(
    inviterUserId: string,
    invitationIdValue: unknown,
  ): Promise<void> {
    const invitationId = requiredUuid(invitationIdValue, "invitationId");
    const now = new Date();

    await sql.begin(async (tx: any) => {
      // Scope the lookup to the inviter so callers cannot use this endpoint to
      // enumerate another account's invitation identifiers or states.
      const rows = await tx`
        select id, status, expires_at_utc
        from lifemate.care_invitations
        where id = ${invitationId}
          and inviter_user_id = ${inviterUserId}
        for update
      `;
      const invitation = rows[0];
      if (!invitation) {
        throw new ApiError(
          404,
          "invitation_not_found",
          "Invitation was not found.",
        );
      }

      // Repeated revocation is a safe no-op. The outer API idempotency ledger
      // handles same-request replay, while this state-level guard also makes a
      // retry after an app restart harmless and avoids duplicate audit rows.
      if (invitation.status === "Revoked") return;

      if (
        invitation.status !== "Pending" ||
        new Date(invitation.expires_at_utc) <= now
      ) {
        throw new ApiError(
          409,
          "invitation_not_pending",
          "Invitation is no longer pending.",
        );
      }

      await tx`
        update lifemate.care_invitations
        set status = 'Revoked', revoked_at_utc = ${now}
        where id = ${invitationId}
      `;
      await tx`
        insert into lifemate.audit_logs
          (id, actor_user_id, action, resource_type, resource_id,
           metadata_json, created_at_utc)
        values
          (${crypto.randomUUID()}, ${inviterUserId},
           'care_invitation.revoked', 'care_invitation', ${invitationId},
           null, ${now})
      `;
    });
  }

  return { revokePendingInvitation };
}
