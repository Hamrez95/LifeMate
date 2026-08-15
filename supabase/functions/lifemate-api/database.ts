export * from "./database_legacy.ts";

import {
  createLifeMateDatabase as createLegacyLifeMateDatabase,
} from "./database_legacy.ts";
import { createIdentityResolver } from "./identity_resolver.ts";

/**
 * Compatibility facade around the existing application-data store.
 *
 * During the identity-link migration, all runtime callers keep the same
 * database API while authenticated-subject resolution is independently
 * switched from the legacy raw AppUser subject to the external-key token
 * boundary. The legacy implementation remains byte-for-byte preserved in
 * database_legacy.ts so this migration is reviewable and reversible.
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
  return {
    ...database,
    requireIdentity: identityResolver.requireIdentity,
    identityLookupMode: identityResolver.lookupMode,
  };
}
