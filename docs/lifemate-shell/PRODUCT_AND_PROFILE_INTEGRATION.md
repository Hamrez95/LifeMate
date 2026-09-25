# Shell Product and Profile Integration

Status: implementation boundary for LifeMate product embedding

## One authentication entry

The LifeMate parent app owns the only authentication experience in an embedded session. Its `LifeMateExperienceGate` restores one Supabase Auth session and creates the reviewed `LifeMateApiClient`. OTP sign-in and sign-up are already implemented by `LifeMateShellAuth`; the shell release build must compile with `ENABLE_PHONE_OTP=true` for the configured SMS provider to be reachable. Stable releases remain controlled by the release workflow and its candidate gates.

An embedded product receives the existing `LifeMateApiClient` from `LifeMateModuleDefinition.pageBuilder`. It must not create a Supabase client, show `LifeMateExperienceGate`, or render its standalone sign-in/register pages. The current WellMate and CareMate roots are still standalone apps, and their registry entries are unavailable until their feature trees are extracted into hostable packages. This means those apps are not yet embedded by the shell; the module API is the integration seam, not evidence that the migration is complete.

When each app is converted, preserve its standalone APK by composing the same product module under its existing standalone auth gate. Under the parent shell, mount the product module directly with the host API client and host locale. Keep product navigation below the module entry route. Do not replace the module's Person context with an Account ID.

## One profile surface with product sections

The shell's `ProfileYouScreen` is the canonical cross-product profile destination. It owns the Person identity card, shared profile fields, locale, timezone, accessibility, privacy, account and support actions. Products contribute only their own settings/actions through `LifeMateModuleDefinition.profileSectionsBuilder`; the builder receives the shell `BuildContext`, the same authenticated API client and current locale. It must not show another global identity header or duplicate global profile fields.

WellMate and CareMate currently use the same `LifeMateSharedProfileScreen` from `lifemate_ui`, with different product actions (for example, WellMate health records and CareMate relationship management). During embedding, retain those product actions as sections contributed to the shell profile. Their standalone roots can continue to render the shared profile component with those sections until the shell mount is available. Global fields continue to come from the canonical profile API; product-specific settings remain owned by the relevant product.

Do not copy profile data into product-local stores to make the combined screen work. Account remains the authentication principal; the resolved active Person remains the owner of shared profile facts. Any new persisted field or API endpoint requires its own reviewed contract.

## Conversion sequence

1. Extract WellMate and CareMate feature trees into reusable module packages without changing their standalone behavior.
2. Add module builders that accept `LifeMateApiClient`, host locale, navigation handoff actions and profile-section builders.
3. Replace embedded product auth/onboarding roots with the host-provided session; keep standalone auth only in the standalone APK composition.
4. Route Living Camp hotspots to those module builders and return to the originating shell destination.
5. Move each product's profile-specific actions into its profile section; remove duplicate global headers and account controls in embedded mode.
6. Verify one OTP login opens both products, sign-out returns to shell auth, locale/profile edits are visible across products, and account/Person changes invalidate mounted module state.

No backend or Supabase schema change is needed for this host boundary.
