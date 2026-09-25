type BootstrapIdentityResolver = {
  assertBootstrapAllowed(authSubject: string): Promise<void>;
};

/**
 * Bootstrap state is checked by the canonical identity resolver. In token-only
 * mode that check hashes the provider subject and reads Account status through
 * the token mapping, rather than looking up raw AppUser authentication data.
 */
export function createBootstrapAccountStateGuard(
  identityResolver: BootstrapIdentityResolver,
) {
  return {
    assertAllowed: (authSubject: string) =>
      identityResolver.assertBootstrapAllowed(authSubject),
  };
}
