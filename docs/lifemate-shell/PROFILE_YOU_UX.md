# LifeMate Profile / You UX

Status: **approved UX contract for #1069**

Parent Epic: #1061  
Canonical profile contract: #1068  
Navigation contract: #1066  
Parent app foundation: #1067  
Implementation: #1080

This document defines the complete parent-shell `You` experience for Profile, avatar, language, privacy, accessibility, subscription, account and support. It is the UX source for #1080 and does not create backend authority, schema or product-specific profile copies.

## 1. Product role

`You` is the user's global LifeMate identity and preferences destination.

It must feel:

- calm, personal and premium;
- simpler than a settings dump;
- fast to scan;
- explicit about what is global versus product-specific;
- safe when profile data is incomplete, stale or unavailable;
- accessible without depending on the animated Living Camp scene.

`You` is not:

- a clinical record viewer;
- a relationship/consent manager replacement for Circle;
- a subscription authority;
- a Progression ledger;
- an Impact account;
- a duplicate WellMate/CareMate/CocoonMate settings page.

## 2. Information architecture

Canonical primary route:

`/you`

Secondary shell routes remain aligned with #1066:

- `/you/profile`
- `/you/settings`
- `/you/subscription`
- `/you/privacy`
- `/you/accessibility`
- `/support`

### `/you` overview order

The default page is composed from configurable sections, not one hard-coded monolith:

1. **Identity header**
2. **Profile & avatar**
3. **Preferences**
4. **Membership**
5. **Privacy & permissions**
6. **Help & support**
7. **Account**

Future sections may be added or reordered through a stable section registry without changing route identity.

## 3. Identity header

The top area gives a compact, human summary of the active Person.

### Contents

- avatar preview;
- display name or truthful incomplete-profile placeholder;
- optional lightweight LifeMate status text such as account/member state when supplied by an approved source;
- primary edit action → `/you/profile`.

### Rules

- never show email/phone as the main identity if a Person display name exists;
- never expose internal Person/Account IDs;
- no health score, diagnosis, medication or wellbeing score in the header;
- no Progression currency or Impact value until their own approved domains exist;
- avatar appearance is cosmetic and never derived from sensitive demographics.

## 4. Profile & avatar section

This section opens `/you/profile`.

### Fields

Initial supported semantic fields from #1068:

- display name;
- birth date;
- language/locale;
- timezone;
- city/coarse location **only when a reviewed canonical adapter exists**;
- avatar family;
- skin tone.

### Edit interaction

Use one clear edit surface rather than multiple hidden gestures.

Recommended structure:

- **Personal information**
  - display name
  - birth date
- **Language & local time**
  - language
  - timezone
  - city when supported
- **Avatar**
  - family
  - skin tone
  - current life-stage preview

Each subgroup may open a focused modal/page on small screens if inline editing would become crowded.

### Save semantics

- dirty edits are visually explicit;
- leaving with unsaved changes triggers confirmation;
- save submits only changed fields;
- successful save updates from returned canonical snapshot, not optimistic local authority alone;
- server validation errors attach to the relevant field and remain readable by screen readers;
- network failure preserves local edits and offers retry/discard.

## 5. Avatar customization UX

MVP customization is intentionally limited.

### Controls

- family selector;
- skin-tone selector;
- resolved life-stage preview.

### Life-stage behavior

The user does **not** manually select age stage.

It is derived from canonical DOB using #1068's approved age bands. When a boundary changes, the later Chapter Transition flow owns confirmation.

### Accessibility

- every choice has a semantic text label;
- selection is not represented by color alone;
- focus order follows logical reading order in RTL and LTR;
- avatar preview remains optional decoration for screen-reader users because equivalent labels expose the selected values.

### Error/fallback

If a selected avatar asset/version is unavailable:

- retain the canonical stable avatar ID;
- render a deterministic compatible visual fallback;
- do not silently rewrite the user's stored choice.

## 6. Language & direction

Language selection is global shell preference backed by the canonical locale contract.

### UX

Options begin with:

- فارسی
- English

The language label is shown in its own native script.

Changing language:

1. presents the selection immediately where safe;
2. persists through the reviewed profile API;
3. updates RTL/LTR direction consistently across shell-owned routes;
4. never changes route IDs or module IDs.

If persistence fails, the UI must clearly distinguish temporary preview from saved preference and offer retry.

## 7. Timezone and city

### Timezone

Display a user-friendly localized label with the canonical IANA ID available in detail/search contexts.

UX rules:

- allow search;
- offer device timezone as a suggestion, not silent permanent authority;
- changing timezone warns only where an existing feature truly has timezone-sensitive consequences; do not invent generic medical warnings.

### City

Do not show a fake editable city field before a reviewed backend adapter exists.

When canonical city support lands, the UX should:

- use city-level/coarse location by default;
- not require GPS for basic shell use;
- explain that it may improve local day/night presentation;
- keep precise coordinates out of the visible Profile contract unless separately justified.

Until then, omit the field or show a clearly non-editable future capability only if product specifically approves it. Default implementation is to omit it.

## 8. Preferences section

`Preferences` is for global presentation behavior.

Initial rows:

- Language
- Accessibility
- Ambient audio

Product-specific preferences stay inside their owning modules unless promoted through an approved shared contract.

## 9. Accessibility

Route: `/you/accessibility`

### Initial controls

- Reduced Motion
- link/explanation for system accessibility settings when relevant

Future controls may include text scaling or contrast preferences only after their ownership/fallback behavior is defined.

### Reduced Motion semantics

The page must explain simply:

- turning it on reduces nonessential animation in LifeMate;
- functional navigation still works;
- system accessibility settings may also reduce motion.

Effective behavior follows #1068: system request or explicit LifeMate request is sufficient to reduce nonessential motion.

### Accessibility requirements

- all controls expose label, value and role;
- minimum touch target follows platform guidance;
- screen-reader order matches visual/logical order;
- focus is restored after dialogs/sheets;
- errors are announced;
- no action requires animation, drag precision or color perception.

## 10. Ambient audio

Ambient audio is a simple global shell presentation toggle.

Rules:

- default off;
- explicit user opt-in required;
- setting is clearly separated from notification/alert sound;
- disabling ambient audio cannot disable medication reminders, safety alerts or product notification channels;
- lifecycle/background behavior may pause audio independently.

If canonical persistence is not yet available, #1080 must not present the control as durably saved. The preferred implementation is to wait for the reviewed adapter rather than create misleading local authority.

## 11. Membership / subscription

Route: `/you/subscription`

The row consumes canonical Commerce presentation from existing subscription work (#619).

### Overview row

May show a safe summary such as:

- current plan label;
- active/trial/expired presentation state;
- renewal/end date only when supplied by canonical Commerce state;
- CTA: `Manage membership`.

### Rules

- Profile never calculates entitlement;
- expired subscription does not erase avatar/profile data;
- subscription state does not imply authorization to another Person's data;
- paywall returns to its origin after dismiss/complete;
- no local boolean such as `isPremium` becomes authority.

## 12. Privacy & permissions

Route: `/you/privacy`

This page is a global privacy entry, not a replacement for granular relationship/consent flows.

Initial content categories:

- privacy overview;
- data-use/consent entry points where approved;
- notification/system-permission entry points;
- account/data deletion entry where existing backend flow supports it;
- legal/privacy documents.

### Important distinction

A relationship shown in Circle and a consent decision are separate. `/you/privacy` may navigate to consent management but must not summarize protected relationship access inaccurately.

## 13. Help & support

Route: `/support`

Support should be reachable without leaving the authenticated parent shell context.

Recommended content:

- Help center / FAQ entry;
- Contact support;
- report a problem;
- app version/build information;
- diagnostics export only if separately reviewed and privacy-safe.

Do not include raw tokens, medical data or internal database IDs in user-visible diagnostic copy.

## 14. Account section

Account operations are intentionally visually separated from Profile editing.

Potential rows:

- authentication/account identifier summary;
- sign out;
- account deletion/manage account when existing backend flow supports it.

### Sign out

- clear, explicit action;
- destructive styling is reserved for truly destructive actions;
- unsynced local state must follow shared product/offline policy rather than being silently discarded by Profile UX.

### Delete account

Account deletion is destructive and requires its existing reviewed backend flow. `You` only provides a safe entry point.

- confirmation copy must explain scope truthfully;
- do not promise immediate deletion if retention/legal processes say otherwise;
- do not implement deletion as local data clearing.

## 15. Primary screen states

Every `You` surface must support these states explicitly.

### Loading

- stable layout skeletons;
- no fabricated values;
- navigation chrome remains available where safe.

### Ready / complete

- all canonical fields display normally;
- edit actions visible;
- sections reflect available capabilities.

### Incomplete profile

- missing optional values show neutral prompts such as `Add birth date` rather than errors;
- completion is encouraged but does not block unrelated shell navigation;
- missing DOB means unresolved avatar stage, never guessed stage.

### Offline with safe cache

- display last safe cached presentation when permitted;
- show a subtle offline/stale indicator if edits cannot currently persist;
- prevent controls from claiming a server save that did not occur;
- do not treat cached access to another Person as current authorization.

### First load offline / no cache

- show a clear unavailable state;
- keep sign-out/support paths available when possible;
- retry action is explicit.

### Error

- preserve last safe content when possible;
- localized message;
- retry;
- do not wipe local edit draft automatically.

### Revoked/invalid Person context

- exit Profile content into the existing bootstrap/recovery flow;
- do not keep showing stale identity as if still active.

## 16. Edit-flow state matrix

| State | Fields | Primary action | Secondary action | Notes |
| --- | --- | --- | --- | --- |
| clean | enabled | none/save disabled | back | no unnecessary save CTA |
| dirty valid | enabled | Save | Cancel/back | back asks before discard |
| dirty invalid | enabled | Save disabled | Cancel/back | inline accessible validation |
| saving | locked or safely editable per implementation | progress | none | prevent duplicate writes |
| save success | canonical response rendered | Done/back | — | clear dirty state |
| validation error | enabled | Retry Save | Cancel | field errors preserved |
| network error | enabled | Retry | Keep editing | draft preserved |
| authorization error | protected fields disabled | recovery route | back | fail closed |

## 17. Navigation and back behavior

Follows #1066.

- `You` root is one of five peer destinations;
- `/you/profile`, `/you/accessibility`, `/you/privacy`, `/you/subscription` are secondary routes;
- Back from secondary route returns to `You` origin;
- Back from `You` root returns Home;
- unsaved edit flow intercepts Back before shell navigation;
- opening Subscription/Support must preserve valid origin for return.

## 18. RTL/LTR requirements

All layouts must use directional semantics.

### Persian RTL

- section text aligns naturally RTL;
- chevrons/arrows use directional widgets/icons rather than fixed left/right assumptions;
- form labels, validation and dialogs follow RTL reading order;
- mixed values such as timezone IDs remain readable without corrupting surrounding direction.

### English LTR

- same semantic order and route ownership;
- no duplicated screen implementation;
- translated copy may change length without clipping critical controls.

Tests for #1080 must render both Persian RTL and English LTR.

## 19. Visual hierarchy

This UX contract intentionally avoids locking a one-off visual design system before implementation.

Required hierarchy:

- calm page background consistent with parent shell;
- identity header visually distinct but not oversized;
- grouped cards/sections with generous spacing;
- one dominant action per edit surface;
- destructive account actions separated from routine preferences;
- icons support scanning but never replace text labels;
- animation remains optional and Reduced Motion-safe.

The Profile screen should feel like a personal LifeMate space, not an admin/settings table.

## 20. Section registry / extensibility

`You` sections must be representable by stable section/action IDs so future features do not require rewriting the screen graph.

Illustrative IDs:

```text
identity
profile
accessibility
language
ambient_audio
subscription
privacy
support
account
```

These are shell presentation IDs, not database table names.

A future section descriptor may contain:

- stable ID;
- localized title/subtitle resolver;
- icon token;
- route/action target;
- visibility predicate from presentation-safe capabilities;
- sort order;
- accessibility label/role metadata.

Visibility predicates may consume resolved capabilities but may not themselves calculate entitlement, consent or authorization.

## 21. Analytics boundary

Safe events may include:

- `you_opened`
- `profile_edit_opened`
- `profile_save_succeeded/failed`
- `accessibility_opened`
- `subscription_manage_opened`
- `support_opened`

Do not attach DOB, name, city, profile-photo path, health data or sensitive demographics to analytics events.

## 22. #1080 implementation acceptance matrix

### Functional

- [ ] `/you` overview renders from resolved profile/capability state;
- [ ] `/you/profile` supports canonical editable fields only;
- [ ] avatar family/skin tone use stable cosmetic IDs;
- [ ] language change handles Persian RTL and English LTR;
- [ ] accessibility route exposes Reduced Motion contract;
- [ ] subscription route reuses canonical Commerce UI/state;
- [ ] privacy/support/account entries route correctly;
- [ ] no direct Supabase table access from Flutter.

### States

- [ ] loading;
- [ ] complete;
- [ ] incomplete profile;
- [ ] offline cached;
- [ ] offline no cache;
- [ ] error;
- [ ] invalid/revoked Person context;
- [ ] edit dirty/saving/success/validation/network failure.

### Accessibility

- [ ] screen-reader labels/roles/selected states;
- [ ] keyboard/focus behavior where applicable;
- [ ] Reduced Motion honored;
- [ ] color is not sole state signal;
- [ ] touch targets remain usable;
- [ ] validation errors are announced.

### Extensibility

- [ ] sections/actions are registry/config driven rather than one fixed switch cascade;
- [ ] no Rive/asset path becomes canonical profile state;
- [ ] future sections can be added without changing unrelated Profile fields;
- [ ] standalone product behavior remains unchanged.

## 23. Verification evidence for #1069

This UX contract is reconciled against:

- `docs/lifemate-shell/MASTER_PLAN.md`;
- `docs/lifemate-shell/NAVIGATION_ARCHITECTURE.md` (#1066);
- `docs/lifemate-shell/PARENT_PROFILE_CONTRACT.md` (#1068);
- merged parent app #1067;
- #1069 objective and acceptance criteria;
- approved Living Camp constraints referenced by #1058.

#1069 is a UX/interaction contract. It requires no database mutation and no premature implementation of Progression, Impact, Circle consent or product-module clinical data.
