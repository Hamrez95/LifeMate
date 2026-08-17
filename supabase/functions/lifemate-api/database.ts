export * from "./database_legacy.ts";

import {
  createLifeMateDatabase as createLegacyLifeMateDatabase,
} from "./database_legacy.ts";
import { createIdentityResolver } from "./identity_resolver.ts";
import { createPhoneCareInvitationStore } from "./phone_care_invitation.ts";
import {
  createPhoneInvitationDeliveryFromEnvironment,
  type PhoneInvitationDelivery,
} from "./phone_invitation_delivery.ts";

export type LifeMateDatabaseOptions = {
  phoneInvitationDelivery?: PhoneInvitationDelivery;
};

/**
 * Compatibility facade around the existing application-data store.
 *
 * During the identity-link migration, all runtime callers keep the same
 * database API while authenticated-subject resolution is independently
 * switched from the legacy raw AppUser subject to the external-key token
 * boundary. The legacy implementation remains preserved in
 * database_legacy.ts so identity and invitation migrations stay reviewable and
 * reversible.
 */
export function createLifeMateDatabase(
  databaseUrl: string,
  contactHashingSecret: string,
  options: LifeMateDatabaseOptions = {},
) {
  const database = createLegacyLifeMateDatabase(
    databaseUrl,
    contactHashingSecret,
  );
  const identityResolver = createIdentityResolver(databaseUrl);
  const phoneInvitations = createPhoneCareInvitationStore(
    databaseUrl,
    contactHashingSecret,
  );

  return {
    ...database,
    requireIdentity: identityResolver.requireIdentity,
    identityLookupMode: identityResolver.lookupMode,
    createInvitation: async (
      identity: Parameters<typeof database.createInvitation>[0],
      body: Parameters<typeof database.createInvitation>[1],
    ) => {
      const contactType = typeof body.contactType === "string"
        ? body.contactType.trim().toLowerCase()
        : "";
      if (contactType !== "phone") {
        return await database.createInvitation(identity, body);
      }

      // Resolve provider configuration only for the phone path. Existing DB
      // callers and tests must not gain a new environment-permission dependency.
      const phoneInvitationDelivery = options.phoneInvitationDelivery ??
        createPhoneInvitationDeliveryFromEnvironment();
      phoneInvitationDelivery.requireEnabled();
      const created = await phoneInvitations.createPhoneInvitation(
        identity,
        body,
        ({ phoneE164, token }) =>
          phoneInvitationDelivery.deliver(phoneE164, token),
      );

      // The raw one-time token never crosses the public API boundary. It exists
      // only long enough to be delivered to Kavenegar inside the transaction.
      return {
        id: created.id,
        contactType: created.contactType,
        contactHint: created.contactHint,
        expiresAtUtc: created.expiresAtUtc,
      };
    },
    createPhoneInvitation: phoneInvitations.createPhoneInvitation,
    acceptInvitation: (
      identity: Parameters<typeof database.acceptInvitation>[0],
      body: Parameters<typeof database.acceptInvitation>[1],
    ) =>
      phoneInvitations.acceptInvitationOrDelegate(
        identity,
        body,
        (_phoneIdentity, legacyBody) =>
          database.acceptInvitation(identity, legacyBody),
      ),
  };
}
