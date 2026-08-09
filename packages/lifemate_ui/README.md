# lifemate_ui

Shared presentation layer for LifeMate applications.

The package owns cross-product UI that must stay visually and behaviorally aligned,
while each app injects its palette, localized labels, version text, and navigation
callbacks. Product-specific routes and business flows stay inside the app packages.

Current shared surfaces:

- Profile screen shell, identity header, subscription card, menu cards, account deletion and sign-out UI.
- Editable profile screen, including profile photo/avatar management and form behavior.

`lifemate_client` remains the shared API/domain package; reusable visual components
belong here so future LifeMate products can reuse the same design without coupling
navigation or product-specific features into the client layer.
