# LifeMate Parent Navigation & Information Architecture

Status: **approved implementation contract for #1066**

Parent Epic: #1061  
Living Camp: #1058  
Super App umbrella: #827  
Reusable product-module precedent: #783

This document defines the parent-shell navigation contract that #1067 and later Shell/Living Camp work must implement. It is intentionally independent from one concrete router package so the route model can survive implementation changes.

## 1. Goals

The LifeMate parent shell must provide one predictable navigation model for:

- Home / Living Camp;
- Today;
- Journey;
- Circle;
- You / global Profile;
- product-module entry and return;
- notification/deep-link entry;
- global settings/support/subscription surfaces.

The shell must remain extensible without turning every product into a top-level tab and without forcing product modules to own global Auth, Account, Person or root navigation.

## 2. Locked principles

1. **Home is the emotional root.** The authenticated shell starts at Home unless a valid deferred deep link resolves elsewhere.
2. **Five primary destinations:** Home, Today, Journey, Circle, You.
3. **Products are mounted destinations, not primary bottom-navigation tabs.** WellMate, CareMate, CocoonMate/Women Health, FitMate and future products are entered from the world, Today items, notifications, deep links or other approved contextual entry points.
4. **Bottom navigation switches peer destinations; it does not push duplicate root pages onto one stack.**
5. **Each product module owns navigation below its product entry boundary.** The parent shell owns entry/exit, global routes and cross-product handoffs.
6. **Route identity is locale-neutral and presentation-neutral.** Persian/English labels, icons and visual stage assets never become route identifiers.
7. **No PHI or sensitive state in route URLs, route names, analytics route labels or deep-link parameters.** Pass opaque identifiers only when needed and resolve authoritative details after authorization.
8. **Navigation never grants authority.** A route being addressable does not imply enrollment, entitlement, relationship, consent or authorization.
9. **Shell routes must survive future scene changes.** Living Camp zone coordinates/assets/stages are not route identity.
10. **Accessibility never depends on the visual world.** Every primary destination and module entry must have semantic navigation independent from scene artwork.

## 3. Primary information architecture

Canonical destination IDs are stable implementation identifiers.

| Destination | Canonical ID | Canonical path | Owner | Purpose |
| --- | --- | --- | --- | --- |
| Home | `home` | `/home` | #1058 / Shell | Living Camp, world-level module entry, central LifeMate home |
| Today | `today` | `/today` | #1062 | Cross-module priorities, full-day view, notification-linked task entry |
| Journey | `journey` | `/journey` | #1064 | Chapters, meaningful life-stage/history presentation |
| Circle | `circle` | `/circle` | #1063 | Relationships, companion selection and consent-safe social/care entry |
| You | `you` | `/you` | #1061 | Global Person/Profile, account-facing settings and shell preferences |

The canonical path strings above are internal app route contracts. External URI scheme/host selection is a release/infrastructure concern and must map into these stable internal paths rather than redefining them.

### Bottom navigation order

Logical order is:

`Home → Today → Journey → Circle → You`

Implementation must use directional layout primitives so the visual order is naturally correct in Persian RTL and English LTR. Code must not hard-code left/right assumptions.

Labels are localized presentation. Destination IDs remain exactly locale-neutral.

## 4. Home / Living Camp ownership

`/home` is the root shell destination after authenticated bootstrap.

Home owns:

- Living Camp scene presentation;
- module-zone hotspots;
- central LifeMate home interaction;
- global shell notification entry affordance where shown;
- safe loading/offline/degraded scene states;
- accessible non-visual equivalents for all world actions.

Home does **not** own:

- canonical entitlement mutation;
- clinical urgency inference;
- relationship/consent truth;
- product-internal navigation;
- progression balances/reward minting;
- Impact accounting.

### Central LifeMate home → Today

Tapping the central LifeMate home opens the Today Peek Sheet over Home. This is an overlay state, not a second Home route.

- initial Peek Sheet shows the approved small cross-module priority set;
- dismiss returns to the unchanged Home scene state;
- expanding / `View full day` transitions to canonical `/today`;
- the Today tab becomes selected when full Today is opened.

The overlay must also be reachable through semantics without requiring a visual tap target.

## 5. Product module route boundary

Canonical product entry route family:

`/apps/:moduleId`

Optional product-internal suffixes may be represented through the module host contract, e.g.:

`/apps/:moduleId/<module-owned-route>`

but the shell must not hard-code every product's internal page graph.

### `moduleId`

`moduleId` is a stable registry identity from the future Shell module registry (#1081). It is **not**:

- a localized product name;
- a Camp `zoneId` visual asset key;
- entitlement state;
- application enrollment row ID exposed as navigation truth;
- a database table name.

The module registry may map a stable module ID to application/enrollment/entitlement adapters and an entry builder.

### Entry resolution order

A product route request is resolved by the shell in this conceptual order:

1. route target exists in module registry;
2. runtime/application availability is known;
3. authenticated Account/Person context is available where required;
4. enrollment/setup requirements are resolved;
5. entitlement/availability presentation is resolved;
6. authorization/consent is evaluated separately for any sensitive person/context;
7. module host mounts the product or presents a truthful unavailable/setup/locked state.

Navigation itself must never short-circuit these checks.

### Existing Cocoon precedent

The existing `CocoonHostContract` demonstrates the required direction: Cocoon receives host state/actions and exposes a reusable module widget; it does not own global Auth or canonical Person state. The unified shell should mount Cocoon through an equivalent host adapter rather than move Cocoon feature code back into a root app.

## 6. Global secondary routes

These are shell-owned or shell-coordinated routes, but they are not permanent bottom-navigation destinations.

| Purpose | Canonical path family | Ownership |
| --- | --- | --- |
| Notifications | `/notifications` | #1062 |
| Global profile details | `/you/profile` | #1061/#1068/#1080 |
| Shell settings | `/you/settings` | #1061 |
| Subscription Center | `/you/subscription` | canonical Commerce UI / #619 reuse |
| Support | `/support` | shared shell/support boundary |
| Privacy/legal | `/you/privacy` | shared shell/account boundary |
| Accessibility preferences | `/you/accessibility` | Shell; product-specific settings may delegate here |

A contextual paywall or product CTA may open Subscription Center, but must return to its origin after completion/cancel rather than permanently changing primary-tab ownership.

## 7. Back behavior

Back behavior must be deterministic on Android and equivalent through explicit UI affordances on iOS/web where applicable.

### Priority order

1. If a modal/sheet/overlay is open, close the topmost overlay.
2. If inside a product/module-owned detail stack, pop within that module.
3. If at a product root entered from the shell, exit the product and restore the originating shell destination.
4. If inside a secondary shell route (`notifications`, profile detail, subscription, support), pop to its recorded shell origin.
5. If at the root of Today/Journey/Circle/You, Back returns to Home.
6. If at Home root with no overlay, allow normal platform app-exit/background behavior.

### Bottom-navigation selection

Selecting a different primary destination:

- switches the active shell destination rather than pushing another root route;
- preserves lightweight destination state where practical;
- must not clone root destinations in history.

Re-selecting the already selected destination should return that destination to its own root state if it has a nested shell-owned stack. It must not silently discard unsaved user input in a child flow; guarded forms keep their own confirmation behavior.

## 8. Deep-link contract

External deep links are normalized into an internal `ShellNavigationIntent` (name illustrative; exact Dart type lands in implementation).

Minimum fields:

- target route ID/path;
- optional stable module ID;
- optional opaque resource/context ID;
- source category (`notification`, `external`, `internal`, `resume`);
- optional version for future compatibility.

### Rules

- no health value, diagnosis, medication name, pregnancy status or other PHI in external URI parameters;
- unknown/obsolete routes fail to a safe shell state, not an arbitrary web page;
- deep links requiring Auth are held as a deferred intent through login and revalidated after session restoration;
- deep links requiring a Person/context are re-authorized after Account/Person resolution;
- revoked consent/access must fail closed even if an old notification/deep link still exists;
- unsupported module/version state opens a truthful unavailable/update-required state;
- after a deep-linked detail is dismissed/popped, Home is the safe fallback unless a valid internal origin exists.

## 9. Notifications and alerts

Notification Center is a shell secondary route owned by #1062.

- bell tap → `/notifications`;
- normal notification tap → normalize to a safe navigation intent;
- `needs attention` zone pulse is presentation only and never the sole route/alert channel;
- urgent/safety-sensitive state uses explicit standard UI and a reviewed destination supplied by the source module/contract;
- Shell never derives clinical severity from raw observations to decide navigation.

Notification payloads must contain minimal opaque identifiers and route intent metadata only.

## 10. Circle and companion navigation boundary

Circle is the management/relationship destination. Living Camp companion presence is a presentation of separately resolved relationship + consent-safe state.

- tapping a companion in Camp may open a Circle-owned summary or approved care/product action;
- companion presence does not prove data authorization;
- relationship selection, consent status, scoped authorization and presentation selection remain separate;
- consent revocation must invalidate future navigation to protected shared content even if a cached route remains in history.

## 11. You / global Profile boundary

You is the canonical global Profile surface.

Global Person/Profile facts belong here rather than being duplicated in product modules when they truly apply globally.

Product-specific settings remain product-owned. A product may expose a host action such as `openGlobalProfile()` or `openSubscription()` to hand control back to the parent shell.

Account-level controls and Person-level profile controls must remain conceptually distinct in UI and state even when presented within one You experience.

## 12. Journey boundary

Journey is a first-class primary destination but remains P2.

The Shell creates the stable `/journey` destination now; #1095–#1097 own its future concept/visual/transition behavior.

Do not fill Journey with speculative dashboard widgets merely to avoid an empty destination during early parent-app work. Until implemented, the parent app may expose a truthful staged/coming-soon shell state under the stable route.

## 13. Bootstrap and authentication states

Before primary navigation is available, the parent host owns bootstrap state.

Conceptual root states:

- `bootstrapping`;
- `unauthenticated`;
- `authenticatedShell`;
- `fatalConfigurationError` / safe unavailable state.

After successful authentication/global bootstrap:

- valid deferred intent → resolve/revalidate and navigate;
- otherwise → `/home`.

Product modules must not replace the root app to implement login/session restore.

## 14. Account / Person switch behavior

On effective Account or active Person context switch:

- invalidate product module stacks that belong to the previous context;
- clear presentation caches according to shared platform policy;
- discard/revalidate deferred navigation intents;
- return to a safe shell root while the new context resolves;
- never keep another Person's protected detail page visible merely because it remains in Navigator history.

Shared offline health state follows #828 and is isolated by environment + Account + Person.

## 15. State restoration

The shell may restore non-sensitive navigation position after ordinary process recreation, but restored navigation is always subordinate to current authorization.

Safe restoration examples:

- selected primary tab;
- Home scene presentation state that contains no sensitive canonical truth;
- product entry route identity when still available and authorized.

Do not persist sensitive route arguments in plaintext preferences for convenience.

## 16. RTL/LTR and accessibility contract

- primary logical destination IDs never change by locale;
- visible labels are localized;
- directional padding/animations use directional primitives;
- semantic traversal follows the visual order for the current directionality;
- each bottom-navigation destination has a localized semantic label;
- Home world hotspots have semantic buttons/actions independent from image coordinates;
- Reduced Motion affects animation only, never route availability;
- large-text layouts must keep navigation labels/actions usable;
- color and animation are never the only indication of selected/alerted state.

## 17. Error and unavailable states

Every route family must have a truthful failure path.

### Shell destination unavailable

A primary destination whose feature implementation has not landed yet may render a localized staged/coming-soon state, but its route remains stable. It must not redirect to an unrelated product.

### Module unavailable

If a registered product is disabled/unavailable/incompatible:

- keep the shell alive;
- show a module-scoped unavailable/update-required state;
- allow Back/Home;
- do not crash the root navigator;
- do not fabricate entitlement or enrollment.

### Offline

The shell may show safe cached presentation, but remote/shared/Commerce operations that require authoritative state say so explicitly. Owner health offline execution remains governed by #828.

## 18. Analytics / diagnostics

Route analytics must use privacy-safe route IDs such as:

- `shell_home`;
- `shell_today`;
- `shell_journey`;
- `shell_circle`;
- `shell_you`;
- `shell_notifications`;
- `module_entry:<moduleId>` only when module ID itself is non-sensitive.

Never emit resource names, medication names, pregnancy state, care notes or Person names as route labels.

## 19. Implementation shape for #1067

#1067 should implement the smallest parent app consistent with this contract:

- new independently buildable `lifemate/` Flutter host;
- auth/runtime bootstrap using existing shared platform patterns;
- localized RTL/LTR Material app root;
- five stable primary destinations;
- Home selected by default;
- placeholder/staged content for destinations not yet implemented;
- deterministic back behavior;
- shell-owned route coordinator that can later mount typed product registry entries;
- tests for route IDs, destination switching, back-to-Home behavior, deep-link normalization boundary and RTL/LTR semantics.

#1067 should **not** yet implement:

- Living Camp renderer (#1075);
- final Profile UX (#1069/#1080);
- Today aggregation (#1087+);
- Circle domain integration (#1091+);
- Journey final visual design (#1095+);
- full module registry (#1081) beyond the minimum extension point needed to avoid hard-coding;
- Progression or Impact.

## 20. Acceptance evidence for #1066

This contract satisfies #1066 when the PR demonstrates:

- all five primary destinations have stable ownership and route identity;
- bottom-navigation switching and Back behavior are unambiguous;
- product module entry/exit boundary is explicit;
- deep-link/auth/account-person revalidation behavior is explicit;
- Today Peek Sheet versus full Today ownership is explicit;
- global secondary routes have owners/return behavior;
- RTL/LTR, accessibility, offline/error and state-restoration requirements are documented;
- no navigation path relies on direct sensitive Supabase-table access;
- existing standalone apps and Cocoon module/host architecture remain unchanged.

## 21. Dependency handoff

After this contract merges:

1. #1067 may create the parent `lifemate/` application.
2. #1070–#1072 may proceed in the parallel Living Camp contract lane.
3. #1075 still waits for #1067 + #1070 and approved asset/runtime contracts.
4. #1068–#1081 continue in Shell/Profile order from MASTER_PLAN.

Any future change to primary destination ownership, stable route IDs, product-module boundary or Back semantics must update this document and `MASTER_PLAN.md` in the same reviewed change.
