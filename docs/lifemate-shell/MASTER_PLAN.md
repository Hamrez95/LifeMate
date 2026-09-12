# LifeMate Living Shell — MASTER PLAN

> Canonical continuity map for the LifeMate parent shell, Living Camp, Profile/You, Today, Circle, Journey, future Progression & Rewards, and future Impact.
>
> **Execution truth:** GitHub LIVE + merged code/CI. **Runtime truth:** Supabase LIVE where relevant. **Approved product/UX decisions:** Notion. This file is the durable execution map and must be reconciled whenever those sources change.

## 0. Reconciliation snapshot

Last reconciled: **2026-09-11**

Current verified `main` at this reconciliation point:

`45a82f2c6c49c18036d3c7871ed10ccbbff5eafa`

Current implementation facts:
- top-level `lifemate/` parent Flutter application exists and is independently buildable;
- Shell/Profile lane through #1081 is merged on `main`;
- Living Camp contracts #1070, #1071 and #1072 are merged;
- Living Camp 2.5D renderer #1075 is merged and mounted as Shell Home;
- #1073 and #1074 remain open because final visual/Rive production is not yet complete;
- #1076 genuinely depends on the reusable Rive avatar output from #1074;
- #1077 and #1078 do **not** need final #1073/#1074 output to begin their independent runtime/accessibility/navigation work after #1075;
- #1079 remains the mandatory Go/No-Go gate and must evaluate representative final-enough art/Rive integration before Living Camp MVP expansion.

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

The existing LifeMate Living Shell hourly continuation automation is retained. Do not create a duplicate scheduler and do not reset/disable its hourly cadence.

Each recurring run must:
- refresh LIVE state;
- read this file first;
- continue the earliest unblocked Chat-friendly task;
- register/update Work handoffs without stopping the project;
- reuse open PRs/branches instead of duplicating implementation;
- work to the execution limit of that run.

## 3. Non-negotiable architecture boundaries

These are invariants:

- **Account != Person**
- **Relationship != Consent**
- **Enrollment != Entitlement**
- **Entitlement != Authorization**
- **Progression != Entitlement**
- **Progression != Scene State**
- Living Camp must not infer clinical meaning from raw health measurements.
- Flutter must not become authoritative for trusted rewards, financial/Impact state, sensitive authorization, or canonical health truth.
- Product modules must not create another global Auth/Person/Profile store.
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

Pending Work:
- #1073 — layered master Camp asset package — Work-preferred
- #1074 — first reusable Rive avatar — Work-preferred

Dependency behavior while Work is pending:
- #1076 — **blocked by #1074** because the Home → WellMate → Home PoC requires the real reusable Rive actor; #1073 improves representative visuals but is not a reason to stop independent runtime work.
- #1077 — **Chat-friendly and unblocked after #1075**; may proceed while #1073/#1074 are pending.
- #1078 — **Chat-friendly and independently implementable after #1075/#1081**; may proceed while #1073/#1074 are pending, while final visual validation remains later.
- #1079 — final performance/battery/accessibility Go/No-Go requires representative integrated art/Rive and completed PoC behavior; do not close it before #1073/#1074/#1076 are genuinely integrated.

Recommended P0 continuation from current state:
1. keep #1073/#1074 in Work queue;
2. Chat implements #1077;
3. Chat implements #1078 if still unblocked/current;
4. when #1074 returns, LIVE verify/integrate it and execute #1076;
5. when #1073/#1074/#1076 runtime is representative, execute #1079.

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

Order:
1. #1087 — Today UX
2. #1088 — shared data + normalized severity contract
3. #1089 — Today Peek Sheet
4. #1090 — Notification Center

The shell consumes module-provided normalized severity and never infers clinical urgency from raw records.

### P1 — Circle / Companions
Parent: #1063

Order:
1. #1091 — Circle UX
2. #1092 — Camp companion selection
3. #1093 — consent-aware adapter
4. #1094 — limited summary/presentation

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
- **Can continue in parallel:** #1077, #1078, Today/Circle contract work and other tasks without final Camp art dependency
- **True downstream blockers:** representative visual portion of #1079 and any acceptance that explicitly requires final layered Camp art

### #1074 — READY FOR WORK
- **Title:** Produce first reusable Rive avatar for PoC
- **Priority:** P0
- **Dependency order:** after #1071/#1072; renderer #1075 already exists
- **Status:** `WORK HANDOFF — READY`; Issue OPEN
- **Why Work:** real Rive authoring/animation, reusable actor asset, state-machine/tint/export production
- **Work prompt:** stored in GitHub Issue #1074 comment headed `WORK HANDOFF — READY`
- **Can continue in parallel:** #1077, #1078, Today/Circle contract work and other tasks not requiring the actor
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

**Execute #1077 — `[LivingCamp] Implement permission-free day/night, lifecycle and Reduced Motion`.**

Why:
- #1073/#1074 are correctly parked in the Work queue rather than fake-completed;
- #1076 is a real dependency consumer of #1074;
- #1077 depends on existing renderer/runtime contracts, not on final art or Rive asset production;
- #1077 is P0 and Chat-friendly;
- completing it reduces risk for the later #1079 performance/accessibility gate.

After #1077, reconcile LIVE again and execute #1078 if still genuinely unblocked.

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
- #783 reusable product-module + thin-host precedent
- #828 offline-first platform invariant
- #619 canonical subscription UX
- #494 existing reward-engine precedent

Notion:
- `LifeMate Living Camp — Product & Interaction Decision Log`
- `LifeMate Progression & Rewards — Product & Architecture Decision Log`
- `LifeMate Impact — Real-World Causes & Community Contribution Decision Log`

Whenever this file is read in a future session, verify current `main`, relevant issue/PR state, open Work handoffs and Supabase runtime facts before executing the next task.

## 15. Global Markets & Localization cross-cutting foundation

A dedicated global-expansion decision log and execution backlog now exist. This is an architecture/dependency reference, not a reason to stop the current Living Camp path.

- **Notion canonical decision:** [LifeMate Global Markets & Localization — Product & Architecture Decision Log](https://app.notion.com/p/3d99ef2b1617814ebf33f168fabc7a55?pvs=204)
- **Core Epic:** #1161; early refactor-prevention tasks: #1162 Market + Experience Preferences contract, #1163 first-launch selection contract, #1164 ecosystem locale/RTL/formatting contract.
- **Before international commerce:** #1165 canonical offer ↔ storefront mapping/localized-price contract and #1166 market-aware legal/consent contract.
- **Admin coordination:** lifemate-admin #332, downstream of Core contract; it reuses #226 and existing RBAC/AAL2/audit boundaries.
- **Deferred marketplace:** #1167 only specifies privacy-first service-area/partner/refill extension points; no partner, pharmacy, data-residency or marketplace implementation is currently authorized.

Global invariants: Account != Person; Locale != Market; Market != Billing Country/Storefront/Service Location/Data Region; digital IAP != physical marketplace; market capability != authorization. Flutter must render only resolved locale/market/capability/price/legal state and never hard-code country branches.
