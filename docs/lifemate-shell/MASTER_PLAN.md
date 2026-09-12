# LifeMate Living Shell — MASTER PLAN

> Canonical continuity map for the LifeMate parent shell, Living Camp, Profile/You, Today, Circle, Journey, future Progression & Rewards, future Impact, and cross-cutting Global Markets/Localization foundations.
>
> **Execution truth:** GitHub LIVE + merged code/CI. **Runtime truth:** Supabase LIVE where relevant. **Approved product/UX decisions:** Notion. This file is the durable execution map and must be reconciled whenever those sources change.

## 0. Reconciliation snapshot

Last reconciled: **2026-09-12**

Current verified `main` at this reconciliation point:

`a0d862f1fa1460f1b52f94c3dadbb092853fd84b`

Current implementation facts:
- top-level `lifemate/` parent Flutter application exists and is independently buildable;
- Shell/Profile lane through #1081 is merged on `main`;
- Living Camp contracts #1070, #1071 and #1072 are merged;
- Living Camp 2.5D renderer #1075 is merged and mounted as Shell Home;
- Living Camp runtime/accessibility/navigation tasks #1077 and #1078 are merged;
- #1073 and #1074 remain OPEN Work-preferred visual/Rive production tasks;
- #1076 remains genuinely blocked by the reusable Rive avatar output from #1074;
- #1079 remains the representative-art/Rive performance/battery/accessibility Go/No-Go gate and must not close before #1073/#1074/#1076 are genuinely integrated;
- Today/Alerts lane #1087–#1090 is merged;
- Circle lane #1091–#1093 is merged; #1094 remains OPEN with implementation PR #1157 still open and must be finished/revalidated before it is treated as complete;
- Global Markets & Localization canonical decision/backlog exists: Core Epic #1161, Admin Epic `Hamrez95/lifemate-admin#332`, P0/P1/P2 contract→runtime chain #1162–#1177, and separate Commerce security task #1176.

Existing platform precedents remain authoritative:
- #783 reusable Cocoon product module + thin host is completed and remains the preferred convergence pattern;
- #828 remains the offline-first owner-health execution authority;
- #619 canonical Subscription Center/contextual paywall work is completed;
- #494 Gift/Referral/Advocacy Reward Engine is completed and future Progression must reconcile with it.

## 1. Source-of-truth order

When sources disagree, reconcile in this order:

1. **GitHub LIVE** — current `main`, Issues, PRs, CI, tests, code.
2. **Supabase LIVE** — deployed database/runtime truth when a task depends on it.
3. **Notion** — approved product/UX decisions and North Star references.
4. **This file** — durable execution order, dependencies and continuity.

Never restart architecture from zero when approved decisions already exist. Verify before changing them.

## 2. Execution policy

### 2.1 Chat is the default executor

For every task, first determine whether Chat can complete it with appropriate quality. If yes, Chat owns the full loop:

`LIVE VERIFY → current-main reconciliation → inspect dependencies/contracts → implement → test → fix → retest → exact diff review → PR → CI → fix CI if needed → merge → verify current main → update/close issue → next`

Do not stop for routine status reports or confirmation.

### 2.2 When Work has a material advantage

Use Work only for tasks where its tools/workspace materially improve output, especially:
- heavy visual exploration;
- original illustration/art asset production;
- Rive authoring/animation;
- large visual package generation;
- broad repo-wide autonomous implementation;
- long research + implementation workflows.

A Work-suitable task must **not** be fake-completed and must **not** stop the whole project.

For every Work handoff:
1. keep the GitHub Issue **OPEN** until real output is LIVE verified;
2. add/update a comment beginning exactly with `WORK HANDOFF — READY`;
3. store in that comment:
   - why Work is better;
   - recommended model and reasoning level;
   - completed dependencies and current LIVE main/context;
   - exact scope and explicit out-of-scope;
   - architecture/design references and files/contracts to read first;
   - implementation + asset/Rive requirements as applicable;
   - testing requirements;
   - PR/CI/merge expectations;
   - Definition of Done;
   - return/handoff requirements;
   - one **complete copy-ready Work prompt** that is self-contained;
4. add/update the task in **Pending Work Handoffs** below;
5. recompute the dependency graph and immediately continue the earliest genuinely-unblocked Chat-friendly task.

Only real downstream dependencies may be blocked. A Work blocker is never automatically a project blocker.

### 2.3 Recovering the Work queue

When asked to review Work tasks:
1. read this file and GitHub LIVE;
2. find Issues with `WORK HANDOFF — READY`;
3. verify they were not already completed, made obsolete, or superseded;
4. re-check dependencies against current main;
5. sort only truly ready Work tasks by execution priority/dependency value;
6. refresh stale prompts if main/contracts moved;
7. return the first Work task, recommended model/reasoning, and its final copy-ready prompt.

The user should not need to remember issue numbers.

### 2.4 After Work finishes

Never accept Work completion claims blindly. LIVE verify:
- branch;
- commits;
- exact diff;
- PR;
- CI/checks;
- merged main;
- issue state;
- assets/files actually present;
- tests/evidence.

If incomplete, Chat completes Chat-friendly gaps or updates the Work handoff with the exact remaining gap. Then sync the Pending Work Handoffs section.

### 2.5 Scheduler rule

The previous LifeMate Living Shell hourly continuation automation was **disabled by explicit user request** after it became unreliable. Do not recreate, re-enable or duplicate a recurring scheduler unless the user explicitly asks for one again.

Continuation is currently manual/session-driven:
- every implementation session refreshes LIVE state;
- reads this file first;
- continues the earliest genuinely unblocked task;
- reuses existing PRs/branches instead of duplicating work;
- registers/updates Work handoffs when Work has a material advantage;
- works to the execution limit of that session.

## 3. Non-negotiable architecture boundaries

These are invariants:

- **Account != Person**
- **Relationship != Consent**
- **Enrollment != Entitlement**
- **Entitlement != Authorization**
- **Progression != Entitlement**
- **Progression != Scene State**
- **Locale != Market**
- **Market != Billing Country / Storefront / Service Location / Data Region**
- **Market capability != Authorization**
- Living Camp must not infer clinical meaning from raw health measurements.
- Flutter must not become authoritative for trusted rewards, financial/Impact state, sensitive authorization, canonical health truth, market-capability truth, legal-acceptance truth or mobile-store pricing truth.
- Product modules must not create another global Auth/Person/Profile/Locale store.
- Existing standalone products remain functional during incremental convergence.

## 4. Locked Living Camp product direction

### World
- fixed elevated/isometric cinematic viewport;
- layered **2.5D** world: raster environment layers + small independent Rive actors/effects;
- Flutter owns shell UI, routing, semantics, state orchestration and accessibility;
- no free camera, drag/zoom, joystick or city-builder behavior;
- Flame is out of MVP unless profiling proves Flutter + Rive insufficient;
- product principle: **Magical Shell. Efficient Tasks.**
- central LifeMate home opens Today;
- module tap gives short 300–500 ms response then navigates immediately; navigation never waits for avatar walking;
- day/night follows local sunrise/sunset from saved city/coarse location with 06:00/20:00 fallback;
- Reduced Motion disables nonessential movement while preserving all actions;
- Persian RTL and English LTR are first-class.

### Avatar / companions
- main avatar is autonomous/deterministic, not user-steered;
- two character families × six life-stage variants (~2, 10, 20, 30, 50, 70) in later MVP completion;
- initial customization: skin tone only;
- extensible action contract begins with `idle`, `walk`, `sit`, `drink`, `wellness`, `care`, `exercise`, `wave`, `sleep`;
- age-band visual change is a user-confirmed Chapter Transition;
- MVP shows at most two user-selected companions while domain capacity remains configuration-driven.

### Module zones
- `lifemate_home`: central home / Today entry;
- `wellmate`: wellness garden / health beacon;
- `caremate`: companion/care area;
- `reproductive_context`: shared CocoonMate/Women Health contextual location;
- `fitmate`: movement/activity area; quiet under-construction when unavailable.

## 5. Backend / database boundaries

Supabase production `lifemate` is the runtime truth when relevant.

Existing canonical domains observed during bootstrap:
- `identity.accounts`;
- `core.persons`, `core.person_profiles`, `core.account_person_links`;
- `ecosystem.applications`, `ecosystem.app_enrollments`;
- Commerce tables including `commerce.entitlements`, `commerce.entitlement_events`, `commerce.subscriptions`;
- consent tables including `consent.consent_records`, `consent.consent_events`;
- relationships including `network.person_relationships`;
- existing rewards precedent `growth.reward_events`, `growth.reward_rules`.

No speculative Progression or Impact schema should be created before their approved phases.

Mobile/API rules:
- Flutter uses reviewed Auth + LifeMate API/shared clients for healthcare state;
- no direct sensitive healthcare-table access from Shell;
- no service-role key in Flutter;
- `packages/lifemate_client` is the shared authenticated API boundary;
- `packages/lifemate_core` owns shared offline/local execution primitives;
- `supabase/functions/lifemate-api/` remains current healthcare API runtime until a separately reviewed cutover.

The production Camp eventually consumes a privacy-safe resolved snapshot/read model, not on-device raw-table joins.

Security note at this reconciliation:
- production RLS is currently disabled on `commerce.orders`, `commerce.transactions`, `commerce.transaction_events` and `commerce.refund_requests`;
- #1176 owns the required security audit/remediation;
- do **not** enable RLS blindly without proving runtime-role/policy behavior and regression-testing Commerce flows.

## 6. Asset, scene and Rive strategy

### North Star
The Notion `lifemate-living-camp-north-star-v1.png` is a **design reference**, never a monolithic runtime asset.

### Scene layering
Preserve independent replaceable layers:
- background/sky;
- distant environment/depth;
- ground/paths/water;
- stable zone slots;
- replaceable zone visuals;
- actors;
- foreground occlusion;
- lights/night overlays;
- lightweight ambient effects;
- semantic/hotspot layer independent of pixels.

Renderer/world uses stable logical coordinates and safe composition + bleed/crop; never stretch world art to each phone.

### Stable zone identity / progression readiness
Every zone has stable `zoneId` independent from art asset, stage, coordinates, hotspot and navigation route.

Initial visuals are intentionally modest **Stage 1**. Future Stage 2/3/N packs must append through versioned manifest/catalog entries without scene-topology rewrites.

Fallback rule:
- compatible requested stage exists → render it;
- otherwise → deterministic compatible fallback, normally Stage 1/last compatible stage.

Availability/entitlement remains orthogonal to progression stage.

### Rive
- prefer focused Rive actors/effects over a giant world artboard;
- `RIVE_AVATAR_CONTRACT.md` is the versioned actor/state-machine contract;
- identity, route state and transient action state stay separable;
- new actions/actors/companions/families must be addable without breaking old call sites;
- skin tint regions remain separate from hair/clothing;
- source + `.riv` + version metadata stay together.

## 7. Execution map — actual dependency order

Multiple lanes may proceed in parallel when genuinely independent. Never turn visual Work into an artificial blocker for unrelated runtime/contracts/backend work.

### P0-A — Shell / Profile
Parent: #1061

Completed/merged on current ancestry:
- #1066 — parent navigation map / IA
- #1067 — independently buildable `lifemate/` parent app
- #1068 — canonical Profile contract
- #1069 — Profile / You UX
- #1080 — Profile implementation
- #1081 — module registry + resilient route host

### P0-B — Living Camp
Parent: #1058

Completed/merged:
- #1070 — layered scene + responsive composition contract
- #1071 — versioned Rive avatar/animation contract
- #1072 — deterministic Scene Coordinator contract
- #1075 — extensible 2.5D renderer in parent app
- #1077 — permission-free day/night, lifecycle and Reduced Motion
- #1078 — accessible WellMate hotspot + immediate canonical route transition

Pending Work:
- #1073 — layered master Camp asset package — Work-preferred
- #1074 — first reusable Rive avatar — Work-preferred

Dependency behavior while Work is pending:
- #1076 — **blocked by #1074** because the Home → WellMate → Home PoC requires the real reusable Rive actor; #1073 supplies representative environment art.
- #1079 — final performance/battery/accessibility Go/No-Go requires representative integrated #1073/#1074 art/Rive plus completed #1076 behavior.

Recommended P0 continuation:
1. keep #1073/#1074 in the Work queue and LIVE verify any returned output;
2. when #1074 returns, integrate it and execute #1076;
3. when #1073/#1074/#1076 are representative in runtime, execute #1079;
4. only then unlock Living Camp MVP expansion #1082–#1086.

### P1 — Living Camp MVP
Begins only after acceptable #1079 evidence:
- #1082 — active/locked/expired module-zone presentation
- #1083 — complete avatar families + eligible-zone route system
- #1084 — consent-safe companion presentation
- #1085 — CocoonMate/Women Health contextual resolver
- #1086 — first-run Camp introduction

Do not pull Progression economy or Impact implementation into this phase.

### P1 — Today / Alerts / Notifications
Parent: #1062

Completed/merged:
1. #1087 — Today UX
2. #1088 — shared data + normalized severity contract
3. #1089 — Today Peek Sheet
4. #1090 — Notification Center

The shell consumes module-provided normalized severity and never infers clinical urgency from raw records.

### P1 — Circle / Companions
Parent: #1063

Completed/merged:
1. #1091 — Circle UX
2. #1092 — Camp companion selection
3. #1093 — consent-aware adapter

Current:
4. #1094 — limited privacy-safe summary/presentation — **OPEN**, implementation PR #1157 is OPEN and must be revalidated/merged before completion.

Relationship, consent, authorization and visual selection stay separate.

### P2 — Journey / Chapters
Parent: #1064

Order:
1. #1095 — Journey concept
2. #1096 — Journey visual design
3. #1097 — confirmed Chapter Transition

Journey is a meaningful life-stage narrative, not another dashboard.

## 8. Pending Work Handoffs

This is the canonical recoverable Work queue. Every item remains OPEN until Work output is merged and LIVE verified.

### #1073 — READY FOR WORK
- **Title:** Produce layered master Camp asset package
- **Priority:** P0
- **Dependency order:** after #1070/#1071/#1072; renderer #1075 is already merged
- **Status:** `WORK HANDOFF — READY`; Issue OPEN
- **Why Work:** original visual/environment asset production, layered day/night package, zone art, runtime exports
- **Work prompt:** stored in GitHub Issue #1073 comment headed `WORK HANDOFF — READY`
- **Can continue in parallel:** unrelated Shell/Global/contract work not requiring final Camp art
- **True downstream blockers:** representative visual portion of #1079 and any acceptance that explicitly requires final layered Camp art

### #1074 — READY FOR WORK
- **Title:** Produce first reusable Rive avatar for PoC
- **Priority:** P0
- **Dependency order:** after #1071/#1072; renderer #1075 already exists
- **Status:** `WORK HANDOFF — READY`; Issue OPEN
- **Why Work:** real Rive authoring/animation, reusable actor asset, state-machine/tint/export production
- **Work prompt:** stored in GitHub Issue #1074 comment headed `WORK HANDOFF — READY`
- **Can continue in parallel:** unrelated Shell/Global/contract work not requiring the actor
- **True downstream blockers:** #1076 real avatar route PoC, actor-dependent portions of #1079, later avatar-family expansion

When Work output appears, verify it before removing an item from this section.

## 9. Progression & Rewards future path

Parent: #1111. Do not block current P0/P1 Camp work.

Locked direction:
- trusted balances/progression are server-authoritative;
- scene renders resolved progression only;
- stage/variant catalog is versioned/open-ended;
- reviewed derived wellbeing signals only; never raw Camp clinical inference;
- paid state never buys better clinical care/safety priority;
- reconcile with existing `growth.reward_events` / `growth.reward_rules` and #494.

Order:
1. #1113 — canonical progression/economy + auditable reward ledger contract
2. #1114 — versioned zone-stage catalog/upgrade contract
3. #1115 — reviewed WellMate/wearable presentation adapter
4. #1116 — first Stage-1 → Stage-2 upgrade slice after renderer/MVP stability
5. #1117 — approved Commerce/activity/referral sources + reversal/anti-abuse

Progression must remain optional to renderer; absent/disabled progression produces deterministic neutral/default presentation.

## 10. Impact future path

Parent: #1112. P3, downstream of Progression foundation.

Never collapse:
1. eligible impact value;
2. user allocation;
3. LifeMate funding commitment;
4. actual settlement/disbursement;
5. partner delivery/proof.

Order:
1. #1118 — funding/conversion policy + campaign lifecycle + auditable Impact ledger
2. #1119 — cause catalog + idempotent allocation + community aggregate
3. #1120 — funding reconciliation/disbursement/proof + Admin contract
4. #1121 — Camp Impact presentation from canonical state

Impact Grove/cause vessels, if built later, are read-only presentation of canonical Impact state and never fabricate offline outcomes.

## 11. Offline / lifecycle boundary

#828 remains authoritative for owner-health offline behavior.

- Camp ambience/scene presentation may reconstruct locally and must pause background animation;
- safe cached shell presentation may degrade gracefully;
- health schedules/reminders/outbox reuse `lifemate_core`;
- remote/shared/Circle/Commerce authorization remains server-authoritative;
- cached shared data never proves revoked access still exists.

## 12. No speculative expansion

- do not create speculative tasks when backlog already covers work;
- do not create parallel architecture/domain truth;
- do not fake backend state because visual assets are pending;
- do not mark placeholders as final visual completion;
- do not turn a Work handoff into a whole-project blocker;
- lower issue number alone does not determine priority;
- actual priority comes from GitHub LIVE + dependency graph + approved Notion decisions.

## 13. Immediate next action

At this reconciliation point:

1. **Finish the existing Circle #1094 / PR #1157 before creating a duplicate implementation branch.** Re-run CI against current main, fix owned failures, exact-diff review, merge if green, verify #1094 closed, and update its completion evidence.
2. In parallel, Work-preferred Living Camp #1073/#1074 may continue because they do not conflict with #1094 or Global contract work.
3. For Global Markets, the earliest architectural implementation chain is #1162 → #1169, followed by #1163/#1164 → #1170/#1171. Do not let Admin #334 treat #1162 contract-only completion as a production read model.
4. Reconcile LIVE again after each merge; do not infer priority from issue number.

## 14. Durable references

GitHub:
- #827 Super App umbrella
- #1058 Living Camp
- #1061 Shell/Profile
- #1062 Today/Alerts
- #1063 Circle
- #1064 Journey
- #1111 Progression
- #1112 Impact
- #1161 Global Markets & Localization
- #1176 Commerce RLS security audit
- #783 reusable product-module + thin-host precedent
- #828 offline-first platform invariant
- #619 canonical subscription UX
- #494 existing reward-engine precedent
- `Hamrez95/lifemate-admin#332` Global Markets Admin

Notion:
- `LifeMate Living Camp — Product & Interaction Decision Log`
- `LifeMate Progression & Rewards — Product & Architecture Decision Log`
- `LifeMate Impact — Real-World Causes & Community Contribution Decision Log`
- `LifeMate Global Markets & Localization — Product & Architecture Decision Log`

Whenever this file is read in a future session, verify current `main`, relevant issue/PR state, open Work handoffs and Supabase runtime facts before executing the next task.

## 15. Global Markets & Localization cross-cutting foundation

Canonical decision:
- [LifeMate Global Markets & Localization — Product & Architecture Decision Log](https://app.notion.com/p/3d99ef2b1617814ebf33f168fabc7a55?pvs=204)

Core parent:
- #1161 — `[Global][EPIC][P0] Global Markets & Localization Foundation`

### P0 — refactor-prevention chain
- #1162 — canonical Market/Locale/Account Experience Preferences contract
- #1169 — **runtime/API/read-model implementation** of Account Experience Preferences + MarketConfiguration/Capabilities
- #1163 — first-launch Language + Market selection contract
- #1170 — **first-launch implementation** with anonymous→account merge and safe market-change states
- #1164 — ecosystem locale/RTL/formatting contract
- #1171 — **shared locale runtime + module propagation implementation**

Contract completion must never be mistaken for runtime/API completion.

### P1 — before international commercial release
- #1165 — canonical offer ↔ storefront mapping/localized-price contract
- #1173 — storefront mappings + authoritative localized-price adapters
- #1166 — market-aware legal/consent contract
- #1174 — legal resolver + immutable acceptance evidence runtime
- #1172 — localization content pipeline/review/QA governance, including pseudo-localization/text-expansion and stricter clinical/legal provenance
- #1175 — provider-neutral web tax/VAT/invoice/receipt compliance contract; required before enabling web checkout
- Admin `lifemate-admin#334 → #333 → #335`, each gated by the corresponding Core runtime rather than contract-only work.

### P2 — local services / marketplace foundation
- #1167 — privacy-first service-area/partner/local-marketplace extension contract
- #1177 — minimal service-area + partner directory runtime foundation
- Admin `lifemate-admin#336` after #1177

No real pharmacy/lab/clinic/retailer integration, physical marketplace checkout, or multi-region database migration is authorized by these foundation tasks.

### Security prerequisite
- #1176 separately owns the audit/remediation of production Commerce RLS for orders/transactions/refunds.
- Security remediation must prove existing runtime roles and access paths before enabling/changing RLS; Globalization work must not hide or bypass this issue.

### Global invariants
- Account != Person
- Locale != Market
- Market != Billing Country
- Market != Storefront
- Market != Service Location
- Market != Data Region
- digital IAP != physical marketplace
- market capability != authorization
- admin reference price != authoritative mobile storefront price
- legal localization != ordinary UI translation

Flutter renders resolved locale/market/capability/price/legal state and never hard-codes country business branches.

### Launch guardrails
Before activating a real country market, verify at minimum:
- supported locale resources + fallback behavior + RTL/LTR/text-expansion QA;
- canonical MarketConfiguration/Capabilities runtime;
- storefront product mappings and authoritative localized pricing;
- approved/versioned legal documents and re-acceptance policy;
- support/operational readiness;
- web tax/VAT/invoice path if web checkout is enabled;
- observability plus rollback/disable controls;
- data-region requirements independently reviewed;
- country-specific partner integrations only after due diligence.
