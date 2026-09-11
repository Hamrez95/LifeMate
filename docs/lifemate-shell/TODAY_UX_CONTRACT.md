# LifeMate Today — Peek Sheet & Full Day UX Contract

Status: **implementation contract for #1087**

Parent Epic: #1062  
Living Camp: #1058  
Navigation contract: #1066 / `NAVIGATION_ARCHITECTURE.md`  
Next contracts: #1088 shared Today data + normalized severity, #1089 Today implementation, #1090 Notification Center

This document defines the product and interaction contract for the LifeMate Today experience. It deliberately does **not** invent clinical ranking, module data schemas, entitlement truth, consent truth, or backend aggregation. #1088 owns the reviewed data/severity contract; #1089 consumes that contract to implement the UI described here.

## 1. Product role

Today is the fast cross-module execution surface of LifeMate.

It has two presentations of the same resolved day state:

1. **Today Peek Sheet** — a compact overlay over Living Camp showing the three highest-ranked actionable items.
2. **Full Day** — canonical `/today`, showing the complete resolved day in understandable order.

The central LifeMate home opens the Peek Sheet. The permanent Today bottom-navigation destination opens Full Day.

The experience must remain task-oriented rather than game-like. Living Camp supplies emotional context; Today supplies efficient execution.

## 2. Locked interaction model

### Peek Sheet

- Opens as an overlay over the existing Home/Living Camp scene.
- Occupies approximately the lower 40% of the usable viewport on the primary portrait target; content may grow within safe responsive limits for large text.
- Initial content is limited to **three** resolved priority items.
- Items are ordered across modules, not grouped by product.
- Every item visibly identifies whose task it is: the current Person or a consented companion.
- `View full day` expands/navigates to canonical `/today` and selects the Today primary destination.
- Swipe/drag down or explicit close dismisses the sheet and returns to the unchanged Camp state.
- Swipe/drag up may expand to Full Day only when it remains accessible and does not conflict with platform assistive gestures; the explicit `View full day` action is always present.
- Back closes the Peek Sheet before changing shell destination.

### Full Day

- Is a first-class shell destination at `/today`.
- Shows all resolved Today items available to the current authorized context.
- Keeps chronological/priority structure understandable without requiring users to know which LifeMate module owns an item.
- Items may expose a localized module/source label as secondary context, but module grouping is not the primary information architecture.
- Opening an item delegates to a reviewed navigation intent/module action; Today does not duplicate product-internal workflows.
- Back from Full Day root follows the parent navigation contract and returns to Home.

## 3. Ranking presentation boundary

Approved ordering principle:

1. safety / overdue;
2. due soon;
3. personal priority.

This is a **presentation requirement**, not permission for Flutter to derive clinical severity.

Today consumes a normalized, reviewed rank/severity/result from #1088. The shell must never inspect raw blood pressure, glucose, medication values, diagnoses, pregnancy data, or other raw health measurements to infer urgency.

When two items have equivalent normalized priority, #1088 must define deterministic tie-breaking. The UX must not silently re-rank items using product-specific guesses.

## 4. Identity and privacy

Every actionable item must expose a presentation-safe owner identity.

Minimum presentation states:

- **You / current Person**
- **Consented companion** — display name/avatar treatment only when the current authorization permits it
- **Unavailable/revoked context** — protected details disappear; the UI does not reveal why access changed

Rules:

- Account != Person.
- Relationship != Consent.
- Entitlement != Authorization.
- Cached relationship or companion presence never proves current access.
- Today must not show another Person's protected task merely because it was previously cached.
- No sensitive diagnosis/value is placed in navigation route names, analytics route labels, or external deep-link parameters.

A companion marker is supporting context, not a replacement for explicit accessible text.

## 5. Peek Sheet information hierarchy

Top to bottom:

1. **Drag/overlay affordance** where appropriate; never the only close/expand mechanism.
2. **Header**
   - localized `Today` title;
   - optional presentation-safe date label;
   - explicit close semantics.
3. **Priority list** — maximum three resolved items.
4. **Full Day action** — `View full day` / localized equivalent.
5. Optional lightweight state/support text when the list is degraded, offline or empty.

Each priority row should expose, when supplied by the contract:

- primary action/task label;
- due/time context;
- owner identity (`You` or authorized companion);
- normalized urgency/attention treatment;
- optional source/module label or icon;
- one clear primary action/navigation affordance.

Do not show raw internal IDs, backend status values or clinical scoring numbers.

## 6. Full Day information hierarchy

Full Day uses a continuous ordered list rather than separate module dashboards.

Recommended sections are time/task semantics, not product ownership:

- overdue / needs action now;
- upcoming today;
- later today;
- completed / resolved today, if the supplied read model includes a safe resolved history.

Exact normalized grouping keys belong to #1088. #1089 must not create a second ranking model inside widgets.

If the canonical contract cannot support one of these sections, omit that section rather than fabricate local state.

## 7. Item interaction states

Every Today item can resolve to one of these presentation-safe interaction outcomes:

| State | Presentation | Interaction |
| --- | --- | --- |
| actionable | normal actionable row | opens supplied safe intent/action |
| needs attention | bounded explicit emphasis + text/semantics | opens supplied action; animation/color never sole signal |
| urgent / safety-sensitive | standard explicit banner/sheet/row treatment | uses reviewed destination supplied by source contract |
| completed | visually de-emphasized with explicit completed semantics | optional detail only if contract permits |
| unavailable | truthful unavailable state | no stale protected details; retry/refresh where meaningful |
| authorization changed | protected content removed or generic safe unavailable state | revalidation required; never infer reason |

Today does not mutate a module's canonical task merely by changing a local visual state.

## 8. Required screen/state matrix

Both Peek Sheet and Full Day must define these states explicitly.

### Loading

Peek Sheet:
- sheet opens promptly;
- stable skeleton/placeholders preserve approximate row structure;
- no fake medication/task content;
- close and Full Day navigation remain deterministic where safe.

Full Day:
- header/navigation remain available;
- loading structure is announced accessibly without repeated noisy announcements.

### Loaded with items

- deterministic ordering from #1088;
- owner identity visible and accessible;
- top three only in Peek Sheet;
- complete current set in Full Day.

### Empty

Use a calm, non-alarmist empty state such as `Nothing needs your attention right now` with localized equivalent.

Do not imply perfect health, clinical safety, adherence, or that no health issue exists. Empty means only that the resolved Today contract currently has no displayable Today items.

### Offline with safe cache

- clearly indicate that displayed data may be from the last safe refresh;
- never treat cache as proof of current shared-person authorization;
- hide/revalidate remote/shared items according to #1088/#828 policy;
- local owner execution may use shared `lifemate_core` truth where the reviewed contract permits it.

### Offline without safe cache

- show a truthful offline state;
- provide retry when connectivity may restore;
- do not synthesize tasks.

### Recoverable error

- retain shell/navigation;
- show concise error + retry;
- do not expose backend error payloads or PHI.

### Partial/degraded data

If #1088 explicitly supports partial results:
- show available safe items;
- disclose that some information could not refresh;
- never silently present a partial set as complete.

If #1088 does not support partial-result provenance, fail to the defined error/offline state instead.

### Authorization/consent revocation during display

- protected companion rows are removed on refreshed/revalidated state;
- open protected detail must fail closed through its owner boundary;
- no explanatory text should reveal a private reason for revocation.

## 9. Alerts and severity presentation

Today and Notification Center share the same reviewed normalized severity vocabulary from #1088.

UX rules:

- **normal** — standard row treatment;
- **needs attention** — calm but explicit emphasis; may correlate with a bounded Camp zone pulse later;
- **urgent/safety-sensitive** — explicit conventional UI, never a purely animated/game treatment.

Color, motion and iconography are supplementary. Text/semantics communicate the state independently.

The source module/API contract is responsible for supplying reviewed normalized meaning. Today does not infer severity from raw measurements.

## 10. Navigation contract

### Home → Peek Sheet

`Living Camp central home` → open Today Peek Sheet overlay.

This does not push a second Home route and does not reset Camp scene state.

### Peek Sheet → Full Day

`View full day` → close/transition overlay → select canonical `/today` destination.

### Today item → destination

The item supplies a safe navigation/action intent defined by #1088 and module-host contracts.

Today may route to:

- a mounted product module;
- a shell-owned safe detail/action;
- Notification Center context where applicable;
- a truthful unavailable/setup/locked state.

Route availability never grants entitlement/authorization.

### Return

After completing/cancelling a module action, return to the originating Today context where practical. Re-resolve Today state rather than assuming the previous item is still valid.

## 11. RTL/LTR and localization

Persian RTL and English LTR are first-class.

Requirements:

- use directional padding/alignment/animation primitives;
- do not bake arrow direction into raster assets;
- owner/module chips and time labels must reorder naturally under Directionality;
- numbers/times remain legible with mixed-direction text;
- localized labels may grow; no fixed-width English assumptions;
- `View full day`, Close, Retry and item actions have localized semantic labels;
- source/module IDs remain locale-neutral internally.

## 12. Accessibility

Minimum requirements:

- sheet has a semantic route/container label and explicit close action;
- each item is one understandable traversal unit before nested actions;
- semantic label communicates task, owner and supplied time/attention state without relying on color;
- touch targets meet platform minimums;
- large text may increase sheet height rather than clip priority content;
- screen readers can reach `View full day` and every actionable item;
- drag gestures always have explicit button/action equivalents;
- Reduced Motion disables nonessential sheet/world animation but not opening, closing or actions;
- focus returns predictably to the central Home affordance when the Peek Sheet closes;
- focus lands on Today heading when Full Day opens through keyboard/screen reader navigation.

## 13. Responsive behavior

Primary phone reference remains Galaxy A55 plus at least one lower-mid Android portrait reference.

Peek Sheet's approximate 40% target is a composition guideline, not a hard fixed height:

- safe insets are respected;
- large-text content may expand/scroll within bounded sheet behavior;
- keyboard/system insets must not hide the primary action;
- the underlying Camp world is overlaid, not resized/re-authored;
- landscape/tablet behavior may use a width-constrained sheet/panel while keeping the same information hierarchy.

## 14. Low-power and Reduced Motion

Today remains fully usable when Camp animation is paused.

- no Today data refresh depends on a Rive/scene ticker;
- no action waits for avatar movement;
- transitions use platform-appropriate reduced/no-motion alternatives;
- loading indicators must not become high-frequency ambient animation.

## 15. Analytics/privacy boundary

Allowed analytics should describe presentation/navigation events, for example:

- Peek Sheet opened/closed;
- Full Day opened;
- safe source category/module identifier;
- item action invoked using a non-sensitive action category.

Do not log:

- task text containing PHI;
- diagnosis/medication/value strings;
- companion identity in analytics labels;
- raw clinical measurements;
- authorization/consent details as free text.

Exact analytics event names are outside #1087 unless an existing shared analytics contract already defines them.

## 16. Ownership boundaries

### #1087 owns

- Peek Sheet vs Full Day information architecture;
- interaction flow;
- user/companion presentation requirements;
- state matrix;
- RTL/LTR and accessibility behavior;
- truthful offline/error/empty UX requirements.

### #1088 owns

- canonical/shared Today item/read-model contract;
- normalized severity/ranking inputs;
- deterministic ordering/tie-break rules;
- safe owner identity payload;
- freshness/partial/offline provenance;
- navigation/action intent payload;
- authorization-safe aggregation boundary.

### #1089 owns

- Flutter Peek Sheet / Full Day implementation using #1087 + #1088;
- widget/state integration and regression tests;
- shell overlay/navigation integration.

### #1090 owns

- Notification Center UI/interaction using the same normalized alert contract where applicable.

Module products continue to own their internal workflows and canonical task mutations.

## 17. Implementation acceptance matrix for #1089

The later implementation PR must provide evidence for at least:

| Scenario | Peek Sheet | Full Day |
| --- | --- | --- |
| 3+ ranked items | exactly top 3, correct supplied order | all supplied items in correct supplied order |
| fewer than 3 items | only real supplied items | all supplied items |
| empty | safe non-clinical empty copy | safe non-clinical empty copy |
| loading | non-fabricated loading UI | non-fabricated loading UI |
| offline cached | explicit freshness/degraded state | explicit freshness/degraded state |
| offline uncached | truthful offline + retry | truthful offline + retry |
| error | recoverable error + retry | recoverable error + retry |
| current Person + companion | owner clear for every item | owner clear for every item |
| revoked companion access | protected row removed/fails closed | protected row removed/fails closed |
| needs-attention / urgent | explicit accessible signal | explicit accessible signal |
| RTL Persian | directional layout + localized semantics | directional layout + localized semantics |
| large text | actions/content remain reachable | content/actions remain reachable |
| Reduced Motion | all actions usable | all actions usable |

No test should assert fabricated clinical interpretation. Tests should inject resolved normalized Today fixtures defined by #1088.

## 18. Definition of Done for #1087

#1087 is complete when:

- Peek Sheet and Full Day ownership/flow are unambiguous;
- top-three behavior and Full Day expansion are defined;
- user/consented-companion presentation is defined without conflating relationship and consent;
- loading, loaded, empty, offline, partial, error and authorization-change behavior is defined;
- RTL/LTR, large-text, screen-reader and Reduced Motion behavior is explicit;
- normalized severity is clearly delegated to #1088 rather than inferred by Flutter;
- navigation/return behavior aligns with `NAVIGATION_ARCHITECTURE.md`;
- #1088 and #1089 can implement without reopening founder-level UX decisions;
- no raw sensitive Supabase access, duplicate domain truth or fake clinical state is introduced.
