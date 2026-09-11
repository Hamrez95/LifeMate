# LifeMate Circle UX Contract

Status: **approved UX implementation contract for #1091**

Parent Epic: #1063  
Navigation contract: #1066  
Profile/person boundary: #1068  
Living Camp decisions: #1058 / approved Notion Living Camp decision log  
Downstream tasks: #1092 companion selection, #1093 consent-aware adapter, #1094 limited summary/presentation

This document defines the parent-shell `Circle` experience for relationships, invitations, pending states and privacy-safe companion presentation. It is a UX contract only: it does not create relationship, consent, authorization or healthcare authority.

## 1. Product role

`Circle` is the human relationship destination of LifeMate.

It should feel:
- warm and relational rather than administrative;
- understandable at a glance;
- safe when relationship or consent state is incomplete or unavailable;
- explicit about who a person is and what actions are currently allowed;
- usable without the Living Camp visual world;
- first-class in Persian RTL and English LTR.

`Circle` is not:
- a raw contact list;
- a clinical record browser;
- an authorization engine;
- a consent ledger UI replacement for every domain;
- a subscription/entitlement authority;
- a place where relationship alone implies access to protected information.

## 2. Non-negotiable boundaries

The UX must preserve these distinctions:

- **Account != Person**
- **Relationship != Consent**
- **Relationship != Authorization**
- **Enrollment != Entitlement**
- **Entitlement != Authorization**
- visual Camp companion selection is presentation state, not relationship truth;
- relationship presence never proves permission to read sensitive health information;
- revoked/expired consent must degrade presentation without exposing a sensitive reason.

The shell must consume reviewed relationship/consent adapters rather than joining sensitive Supabase tables directly.

## 3. Information architecture

Canonical primary route:

`/circle`

Recommended child surfaces:
- `/circle/person/:stablePresentationId` — relationship detail/presentation shell; identifier must not expose a raw database key in UI copy;
- `/circle/invite` — start an invitation flow only when the reviewed relationship service supports it;
- `/circle/pending` — pending incoming/outgoing relationship requests when supported;
- `/circle/camp` — companion presentation selection owned by #1092.

Route identity is stable even if the underlying relationship provider changes.

## 4. Circle overview

Default hierarchy:

1. **Circle header**
   - title;
   - short privacy-oriented explanation;
   - invite/add action only when supported.
2. **People section**
   - approved relationship cards grouped by human meaning, not database type.
3. **Pending section**
   - incoming/outgoing invitations when present.
4. **Camp companions entry**
   - presentation choice, explicitly separate from relationship/consent truth.
5. **Help/privacy explanation**
   - concise explanation that relationships and access permissions are separate.

Do not render a dense admin table.

## 5. Relationship roles

The UX must support at least these product-facing relationship concepts without hard-coding them as the only possible future roles:

- caregiver;
- care recipient;
- partner;
- child/family member;
- other reviewed family/close-person role when later introduced.

Use a stable role registry/configuration in implementation. Unknown future role values must fall back to a neutral localized label instead of breaking the page.

A person may have more than one semantic relationship over time. UI should represent the current reviewed presentation rather than inventing exclusivity rules.

## 6. Person card

Each person card may show only presentation-safe fields supplied by the reviewed adapter:

- display name;
- avatar/photo placeholder approved for shell use;
- localized relationship label;
- optional high-level connection/access status text;
- Camp companion selection indicator when #1092 is implemented.

Never show by default:
- raw health measurements;
- diagnosis/medication details;
- internal account/person IDs;
- consent document IDs;
- entitlement/payment internals;
- a green/red health score inferred by the shell.

### Card actions

Actions are capability-driven. Examples:
- open person detail;
- review relationship/invitation state;
- open an authorized module route;
- manage Camp companion presentation after #1092.

If an action is not authorized or not supported, omit/disable it truthfully rather than fabricating a result.

## 7. Relationship detail

The detail surface separates four concepts visually:

### A. Person
Who this human is in the current presentation context.

### B. Relationship
How the user and this Person are related.

### C. Permission/consent summary
A high-level, privacy-safe status supplied by #1093 or a reviewed backend contract. It must never be inferred from the relationship row.

### D. Presentation choices
Whether the Person may appear as a Camp companion after #1092, independent of relationship existence.

This separation is required so users do not interpret "Partner" or "Caregiver" as automatic access to records.

## 8. Invitation UX

Invitation capability is shown only when a canonical relationship invitation flow exists.

### Start state
- clear explanation of who can be invited;
- reviewed identity lookup/input method;
- no fake local contact import if permission/service is absent;
- no assumption that invitation acceptance grants clinical access.

### Outgoing pending
Show:
- person/recipient presentation when safe;
- relationship intent label;
- `Pending` state;
- cancel action only when supported.

### Incoming pending
Show:
- inviter presentation;
- requested relationship meaning;
- accept/decline actions;
- explanation that additional consent/authorization may still be required for protected data.

### Failure
If invitation creation fails:
- preserve entered safe form state where practical;
- show retry;
- do not display a successful-looking pending card.

## 9. Consent and authorization presentation

Circle may display a simple summary such as:
- `Connected`;
- `Access limited`;
- `Permission required`;
- `Access unavailable`.

Exact labels must come from a reviewed normalized adapter contract in #1093.

The shell must not:
- inspect raw consent events and derive its own legal meaning;
- treat entitlement as authorization;
- reveal why another person revoked access unless the backend explicitly provides a safe user-facing reason;
- keep showing cached protected details as proof of current permission.

On consent/access revocation, protected summary content disappears or becomes unavailable while the relationship card may remain if the relationship itself still exists.

## 10. Camp companion entry

`Circle` owns the human-facing selection entry; #1092 owns the actual Camp companion selection behavior.

UX rules:
- relationship existence does not auto-select a companion;
- user explicitly chooses eligible companions;
- MVP visible companion count may be two, but UI/domain structure must be configuration-driven;
- ineligible people remain understandable without exposing private reasons;
- removing a companion from Camp does not delete the relationship;
- adding/removing Camp presentation never grants/revokes data access.

## 11. State matrix

### Loading
- preserve page structure/skeleton where useful;
- do not show stale cards as confirmed current authorization.

### Loaded with people
- show relationship cards and only capability-valid actions.

### Empty
Message should communicate that Circle is where trusted relationships can appear, without implying the user must invite someone.

Primary action:
- `Invite someone` only if canonical invitation support is available;
- otherwise no fake CTA.

### Pending-only
Pending invitations are shown distinctly from established relationships.

### Offline / stale cache
- cached relationship names may be shown only if the reviewed adapter marks them presentation-safe;
- remote/shared authorization-sensitive actions are disabled or revalidated before use;
- clearly indicate that current permission could not be refreshed where relevant.

### Error
- concise error message;
- retry action;
- no fabricated empty state that could be mistaken for relationship deletion.

### Forbidden / revoked access
- keep only the relationship-level presentation that remains authorized;
- protected details become unavailable;
- do not leak the revocation reason.

## 12. Privacy

- Use the minimum information necessary for relationship recognition.
- Do not expose phone/email in overview cards unless explicitly required by a reviewed flow.
- Do not show another person's sensitive state in notifications, cards or Camp merely because they are related.
- Analytics must avoid names, raw identifiers and health details in event payloads.
- Screenshots/previews should not require real PHI; tests use synthetic privacy-safe fixtures.

## 13. Accessibility

All Circle functionality must work without animation or Camp visuals.

Requirements:
- semantic labels for person, relationship and status;
- status is never communicated by color alone;
- logical focus/read order in both RTL and LTR;
- minimum platform touch targets;
- pending/disabled actions expose their state to screen readers;
- errors and invitation results are announced;
- avatar imagery is decorative when equivalent text identifies the person;
- companion-selection controls expose selected/not-selected state explicitly.

## 14. RTL / LTR

- use directional paddings/alignment, not fixed left/right assumptions;
- relationship labels localize naturally instead of mirroring raw backend enum values;
- icons with directional meaning mirror only when semantically appropriate;
- route IDs, stable IDs and backend contracts do not change by locale;
- mixed Latin module names remain readable inside Persian layouts.

## 15. Responsive behavior

Phone-first layout:
- single-column cards;
- modal/bottom-sheet or full-page detail depending on content length;
- no horizontally scrolling relationship table.

Larger widths may use a bounded two-pane overview/detail layout later without changing route/state contracts.

## 16. Truthful source boundary

Future implementation should consume a normalized `CircleSnapshot`-style adapter rather than raw tables. The exact adapter is owned by #1093.

Presentation-safe concepts expected from that adapter may include:
- stable presentation ID;
- display name/avatar presentation;
- normalized relationship role;
- relationship lifecycle state;
- normalized consent/access presentation state;
- allowed actions/capabilities;
- Camp eligibility/presentation eligibility.

This document does not define a new backend schema.

## 17. Testing contract

Downstream implementation must cover at least:
- empty Circle;
- multiple supported relationship roles;
- pending incoming and outgoing invitation states;
- relationship present with no consent/access;
- revoked access without relationship deletion;
- capability-driven action visibility;
- Camp selection shown independently from relationship truth;
- loading, offline/stale and error states;
- Persian RTL and English LTR;
- screen-reader semantics/status labels;
- unknown future relationship role fallback;
- no raw sensitive fields exposed by the shell.

Use synthetic, privacy-safe fixtures only unless a dedicated integration environment is explicitly approved.

## 18. Downstream ownership

### #1092 — Camp companion selection
Owns explicit user selection, capacity/configuration, eligibility presentation and Camp-facing companion IDs.

### #1093 — consent-aware adapter
Owns normalization from canonical relationship + consent/authorization sources into privacy-safe Circle/Camp presentation. Relationship alone must never produce access.

### #1094 — limited summary/presentation
Owns the smallest approved person/care summary exposed from Circle after #1093 boundaries are real and tested.

No downstream task may bypass #1093 by directly querying sensitive tables from Flutter.

## 19. Definition of Done for #1091

#1091 is complete when:
- Circle IA and main route are explicit;
- caregiver, care recipient, partner and child/family presentations are covered without hard-coded exclusivity;
- relationship, consent, authorization and Camp selection are visibly separate concepts;
- invite, pending, empty, loading, offline/stale, error and revoked states are specified;
- privacy rules prevent PHI leakage;
- RTL/LTR and accessibility requirements are testable;
- downstream ownership for #1092–#1094 is clear;
- no new backend authority/schema or speculative task is introduced.
