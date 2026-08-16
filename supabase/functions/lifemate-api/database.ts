export * from "./database_legacy.ts";

import {
  createLifeMateDatabase as createLegacyLifeMateDatabase,
} from "./database_legacy.ts";
import { createIdentityResolver } from "./identity_resolver.ts";
import { createPhoneCareInvitationStore } from "./phone_care_invitation.ts";

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
    createPhoneInvitation: phoneInvitations.createPhoneInvitation,
    acceptInvitation: (identity: Parameters<typeof database.acceptInvitation>[0], body: Parameters<typeof database.acceptInvitation>[1]) =>
      phoneInvitations.acceptInvitationOrDelegate(
        identity,
        body,
        database.acceptInvitation,
      ),
  };
}
