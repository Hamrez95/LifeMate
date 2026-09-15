import { createIdentityResolver } from "./identity_resolver.ts";

/**
 * Fails closed when an existing authentication identity belongs to an account
 * that is no longer allowed to bootstrap. Identity lookup remains centralized
 * in the canonical resolver so this guard does not create a second raw-link
 * dependency while legacy lookup mode is being retired.
 */
export function createBootstrapAccountStateGuard(databaseUrl: string) {
  const identityResolver = createIdentityResolver(databaseUrl);

  async function assertAllowed(authSubject: string): Promise<void> {
    await identityResolver.assertBootstrapAllowed({
      id: authSubject,
      email: null,
      phone: null,
      userMetadata: {},
    });
  }

  return { assertAllowed };
}
