# LifeMate Living Shell — MASTER PLAN

> Canonical continuity map for the LifeMate parent shell, Living Camp, Profile/You, Today, Circle, Journey, future Progression & Rewards, and future Impact.
>
> **Execution truth:** GitHub LIVE + merged code/CI. **Runtime truth:** Supabase LIVE where relevant. **Approved product/UX decisions:** Notion. This file is the durable execution map and must be reconciled when those sources change.

## 0. Reconciliation snapshot

Last reconciled: **2026-09-11**

GitHub `main` at bootstrap: `bcd161c9b873304bcbc505677394c7986ecd97a0`.

Current repository facts:
- `wellmate/`, `caremate/`, `cocoonmate/`, `packages/`, `supabase/` and backend boundaries already exist.
- A top-level `lifemate/` parent Flutter application does **not** yet exist on current `main`; creating it remains #1067.
- Cocoon's reusable `product module + thin host` precedent is completed in #783 and is the preferred migration pattern for future Super App mounting.
- The cross-product offline-first platform invariant #828 remains open and authoritative for owner health execution. Living Camp PoC must not duplicate or bypass it.
- Canonical Subscription Center / contextual paywall work #619 is completed. Shell presentation must consume canonical Commerce state rather than create another entitlement truth.
- Gift/referral/advocacy reward precedent #494 is completed and must be reconciled by future Progression work instead of creating a conflicting reward ledger.

### Primary Epics — LIVE status at bootstrap

All are open:
- #827 — LifeMate Super App umbrella
- #1058 — Living Camp
- #1061 — Shell / Profile / You — **P0**
- #1062 — Today / Alerts / Notifications — **P1**
- #1063 — Circle / Companions — **P1**
- #1064 — Journey / Chapters — **P2**
- #1111 — Progression & Rewards — **P2 / post-Living-Camp-MVP**
- #1112 — Impact — **P3 / post-Progression foundation**

All shell/Living-Camp/Today/Circle/Journey/Progression/Impact child issues created on/after 2026-09-09 are still open at this reconciliation point. No implementation PR for `LivingCamp` exists yet.

## 1. Source-of-truth order

When sources disagree, reconcile in this order:

1. **GitHub LIVE** — current `main`, Issues, PRs, CI, tests, code.
2. **Supabase LIVE** — deployed database/runtime truth when a task depends on it.
3. **Notion** — approved product/UX decisions and North Star references.
4. **This file** — durable execution order, dependencies and continuity; update it after approved decisions or execution-map changes.

Never restart architecture from zero when a decision is already approved. Verify before changing it.

## 2. Locked product direction

### Living Camp
- Fixed elevated/isometric cinematic viewport.
- Layered **2.5D** world: raster environment layers + small independent Rive actors/effects.
- Flutter owns shell UI, routing, semantics, state orchestration and accessibility.
- No free camera, drag/zoom, joystick or city-builder behavior.
- **Flame is out of MVP** unless measured profiling proves Flutter + Rive is insufficient.
- Product principle: **Magical Shell. Efficient Tasks.** Health/care workflows remain fast conventional UI after entry.
- Central LifeMate home opens Today.
- Module tap gives a short 300–500 ms response, then navigates immediately; navigation never waits for avatar walking.
- Day/night follows local sunrise/sunset from coarse saved location or selected city, with 06:00/20:00 local fallback.
- Reduced Motion disables nonessential motion while preserving all actions.
- Persian RTL and English LTR are first-class from the first implementation.

### Avatar / companions
- Main avatar is autonomous and deterministic, not user-steered.
- Two character families × six life-stage variants (~2, 10, 20, 30, 50, 70).
- MVP customization: skin tone only.
- Common animation contract begins with `idle`, `walk`, `sit`, `drink`, `wellness`, `care`, `exercise`, `wave`, `sleep` and must be extensible without breaking existing actors.
- Age-band visual change is a user-confirmed Chapter Transition, not a silent identity change.
- MVP displays at most two user-selected companions, but capacity must be configuration-driven rather than hard-coded into the domain model.

### Module zones
- WellMate: wellness garden / health beacon.
- CareMate: companion/care area.
- CocoonMate / Women Health: one contextual location with mutually exclusive presentation.
- FitMate: activity/movement area; quiet under-construction when unavailable.
- LifeMate: central home / Today entry.

## 3. Non-negotiable architecture boundaries

These are invariants, not implementation suggestions:

- **Account != Person**
- **Relationship != Consent**
- **Enrollment != Entitlement**
- **Entitlement != Authorization**
- **Progression != Entitlement**
- **Progression != Scene State**
- Living Camp must not infer clinical meaning from raw health measurements.
- Flutter must not become the authority for trusted rewards, financial/Impact state, sensitive authorization, or canonical health truth.
- Product modules must not create another global Auth/Person/Profile store.
- Existing standalone products remain functional during incremental convergence; no big-bang rewrite.

## 4. LIVE backend / database boundaries

Supabase production project `lifemate` is ACTIVE/HEALTHY at bootstrap.

Relevant existing canonical domains observed LIVE:
- identity Account: `identity.accounts`
- Person/profile: `core.persons`, `core.person_profiles`, `core.account_person_links`
- application registry/enrollment: `ecosystem.applications`, `ecosystem.app_enrollments`
- Commerce: `commerce.entitlements`, `commerce.entitlement_events`, `commerce.subscriptions`, related offer/payment/adjustment tables
- consent: `consent.consent_records`, `consent.consent_events`, related data-use consent tables
- relationships: `network.person_relationships` plus existing legacy/domain relationship tables where still supported
- existing reward precedent: `growth.reward_events`, `growth.reward_rules`

No new canonical Progression or Impact table family was observed in this bootstrap scan. That matches #1111/#1112 being future work; do not pre-create speculative schema.

### Mobile/API boundary
- Flutter authenticates through the approved Auth flow and reads/writes healthcare state through reviewed LifeMate API/shared clients.
- No direct sensitive healthcare-table queries from the shell.
- No service-role key in Flutter.
- `packages/lifemate_client` is the shared authenticated API boundary.
- `packages/lifemate_core` owns shared offline/local execution primitives; do not create one scheduler/outbox/database per product.
- `supabase/functions/lifemate-api/` remains the current healthcare API runtime unless a separately reviewed runtime cutover is completed.

### Camp read-model direction
The production Camp eventually consumes a privacy-safe resolved snapshot/read model. It may include presentation-safe fields such as:
- active Account/Person context
- avatar family/life-stage/skin-tone presentation
- module availability + enrollment
- entitlement presentation state
- consent-safe companion presentation
- normalized alert severity
- resolved Today summary
- future `zoneStage` / variant
- future reviewed wellbeing presentation signal

The Camp must not assemble that state by joining sensitive raw tables on-device.

## 5. Asset, scene and Rive strategy

### North Star
The approved `lifemate-living-camp-north-star-v1.png` lives in the Notion Living Camp decision log. It is a **design reference**, not a shippable monolithic runtime image.

### Scene layering
#1070 owns the exact specification, but the architecture must preserve independent replaceable layers such as:
- background / sky
- environment / distant depth
- ground / paths / water
- stable zone slots
- replaceable zone visuals
- actors
- foreground occlusion
- lights / night overlays
- small ambient effects
- semantic/hotspot layer independent of pixels

Responsive behavior uses a stable world coordinate system, safe composition area and bleed/crop rules. Do not stretch the world to each phone aspect ratio.

### Stable zone identity and future upgrades
Every module area has a stable `zoneId` independent from its current art asset, coordinates, hotspot and navigation route.

Initial product/module structures are intentionally **modest Stage 1** visuals. Future Stage 2/3/N assets must be addable through versioned catalog/manifest entries without rewriting scene topology.

Required fallback behavior:
- requested compatible stage asset exists → render it;
- missing/incompatible stage asset → deterministic compatible fallback, normally Stage 1 or last compatible stage;
- module availability/entitlement presentation remains orthogonal to progression stage.

### Rive
- Prefer several focused Rive actors/effects over one giant world artboard.
- Define versioned artboard/state-machine inputs/events in #1071.
- Character identity, route state and transient action state remain separable.
- New actions, actors, companions and character families must be addable without changing old call sites.
- Skin tint regions remain separately addressable from clothing/hair.
- Rive source + exported `.riv` + contract/version metadata belong together.
- Actual file/folder naming and numeric budgets are locked by #1070/#1071, not guessed here.

### Asset production rule
Art-generation and Rive-production tasks may use Work when it materially improves visual/animation output. Runtime architecture, contracts and integration remain reviewable in Chat/GitHub.

## 6. Execution map — actual dependency order

The project has multiple lanes. Do not force everything into one serial line when tasks are genuinely independent, but never skip a declared prerequisite.

### Phase P0-A — Shell contract and parent-app foundation
Parent: #1061

1. **#1066 — Define parent navigation map and information architecture**
   - First default task.
   - Owner: Chat.
   - Defines Home / Today / Journey / Circle / You ownership, bottom navigation, back/deep-link behavior.
2. **#1067 — Create independently buildable `lifemate/` parent application**
   - Depends on #1066.
   - Owner: Chat unless repo-wide refactoring becomes unexpectedly broad.
3. **#1068 — Canonical Profile contract**
4. **#1069 — Profile / You UX**
5. **#1080 — Profile implementation**
6. **#1081 — Module registry and resilient route host**

#1068–#1081 can advance in their declared Shell order while Living Camp technical work proceeds in parallel after #1067 establishes the host.

### Phase P0-B — Living Camp art/runtime contracts
Parent: #1058

1. **#1070 — Layered scene + responsive composition spec** — Chat.
2. **#1071 — Versioned Rive avatar/animation contract** — Chat.
3. **#1072 — Deterministic Scene Coordinator design** — Chat.
4. After contracts:
   - **#1073 — Produce layered master Camp asset package** — **Work preferred** (visual/art-heavy).
   - **#1074 — Produce first reusable Rive avatar for PoC** — **Work preferred** (Rive/animation asset production).
5. **#1075 — Implement 2.5D renderer in parent app** — Chat; requires parent app #1067 and scene contract #1070, and should integrate the approved asset contract rather than inventing a second one.
6. **#1076 — Home → WellMate → Home technical PoC** — after #1072/#1074/#1075.
7. **#1077 — Day/night, lifecycle, Reduced Motion**.
8. **#1078 — WellMate hotspot and immediate route transition**.
9. **#1079 — Performance/battery/accessibility gate** — mandatory Go/No-Go before Living Camp MVP expansion.

### Global P0 scheduling rule
The first task is #1066. After its contract is stable, #1067 and the Living Camp contract lane (#1070–#1072) may progress without waiting for full Profile implementation. Do not block technical PoC on full Circle/Today/Journey or live PHI.

### Phase P1 — Living Camp MVP
Parent: #1058; begins only after #1079 provides acceptable evidence.

- #1082 — active / locked / expired module-zone presentation
- #1083 — complete avatar families + eligible-zone route system
- #1084 — consent-safe companion presentation
- #1085 — CocoonMate / Women Health contextual resolver
- #1086 — first-run Camp introduction

Integration rules:
- synthetic/privacy-safe placeholders are acceptable only where the Epic explicitly allows them;
- canonical live companion/entitlement/context integration must use reviewed adapters and real consent/authorization boundaries;
- no Progression economy or Impact implementation is pulled forward into this phase.

### Phase P1 — Today / Alerts / Notifications
Parent: #1062

Merge order:
1. #1087 — Today UX
2. #1088 — shared data + normalized severity contract
3. #1089 — Today Peek Sheet
4. #1090 — Notification Center

The shell consumes module-provided normalized severity; it does not infer clinical urgency from raw records.

### Phase P1 — Circle / Companions
Parent: #1063

Merge order:
1. #1091 — Circle UX
2. #1092 — Camp companion selection
3. #1093 — consent-aware adapter
4. #1094 — limited summary/presentation

Relationship, consent, authorization and visual selection remain separate states.

### Phase P2 — Journey / Chapters
Parent: #1064

Merge order:
1. #1095 — Journey concept
2. #1096 — Journey visual design
3. #1097 — confirmed Chapter Transition

Journey must remain a meaningful life-stage narrative, not another generic dashboard.

## 7. Progression & Rewards future path

Parent: #1111. **Do not block current P0/P1 Living Camp work.** Current work only preserves extension points.

Locked direction:
- trusted balances and progression are server-authoritative;
- scene only renders resolved progression;
- stage/variant catalog is versioned and open-ended;
- health/wearable influence enters through reviewed derived presentation signals, never raw Camp inference;
- paid state never buys better clinical care or safety priority;
- reconcile with existing `growth.reward_events` / `growth.reward_rules` and #494 before introducing a new ledger model.

Recommended order:
1. #1113 — canonical progression/economy + auditable reward ledger contract
2. #1114 — versioned zone-stage catalog and upgrade contract
3. #1115 — reviewed WellMate/wearable wellbeing presentation adapter; may progress in parallel with #1114 after boundaries stabilize
4. #1116 — first real Stage-1 → Stage-2 upgrade slice, only after Living Camp MVP renderer is stable
5. #1117 — approved Commerce/activity/referral reward sources + spend/reversal/anti-abuse

Progression must remain optional from the renderer's perspective: when unavailable/disabled, Living Camp renders a deterministic neutral/default state.

## 8. Impact future path

Parent: #1112. **P3, downstream of Progression foundation.**

Impact is a separate trusted accounting/product domain, not a cosmetic counter and not a Camp calculation.

Never collapse these states:
1. user has eligible impact value;
2. user allocated value to a cause;
3. LifeMate committed company funding;
4. funds were actually settled/disbursed;
5. partner reported/proved delivery.

Recommended order:
1. #1118 — funding/conversion policy + campaign lifecycle + auditable Impact ledger
2. #1119 — cause catalog + idempotent user allocation + community aggregate progress
3. #1120 — company funding reconciliation, disbursement/proof + Admin contract
4. #1121 — Living Camp Impact presentation from canonical campaign state

A future Impact Grove/cause-vessel UI is read-only presentation of canonical Impact state. It must never fabricate donation value or delivered outcomes while offline.

## 9. Offline / lifecycle boundary

#828 remains the cross-product authority for owner health offline behavior.

Living Shell rules:
- Camp ambience/scene state can be reconstructed locally and must pause in background.
- Safe cached shell presentation may degrade gracefully.
- Owner health schedules/reminders/outbox use shared `lifemate_core` mechanisms, not Living Camp-specific queues.
- Remote/shared/Circle/Commerce authorization remains server-authoritative.
- Cached shared data must never be treated as proof that revoked access still exists.

## 10. Chat vs Work operating rule

**Chat is the default coordinator and executor.** Use Chat whenever the task can be completed reliably here, including:
- architecture and contracts;
- GitHub/Notion/Supabase audits;
- issue reconciliation;
- scoped Flutter/package/backend implementation;
- API/read-model contracts;
- tests, CI debugging, review and merge;
- documentation and execution-map maintenance.

Use **Work only when it has a material advantage**, especially:
- original visual asset production;
- Rive animation/artboard authoring;
- large visual exploration across many references;
- broad repo-wide refactors touching many files;
- extensive autonomous multi-step research + implementation where one continuous workspace materially reduces handoff cost.

When Work is preferable, Chat must stop before duplicating that implementation and provide:
1. a short reason;
2. recommended model;
3. recommended reasoning level;
4. one complete copy-ready Work prompt;
5. after Work finishes, Chat resumes ownership and LIVE verifies its PR/code/CI/result.

### Current known Work candidates
- #1073 layered master Camp asset package — visual/art-heavy.
- #1074 first reusable Rive avatar — Rive/animation-heavy.
- #1096 Journey visual design may become Work-preferred when that phase starts.
- Future Stage 2/3/N asset packs and large character/action expansions are likely Work-preferred.

#1066 is **not** a Work task; it is a bounded architecture/information-architecture contract and should be executed in Chat.

## 11. Standard execution loop

For implementation sessions:

`LIVE VERIFY → current-main reconciliation → earliest unblocked task → implement → test → fix → retest → exact diff review → PR → CI → fix if needed → merge → verify main → update issue → next`

Additional rules:
- do not generate speculative tasks when existing backlog already covers the work;
- do not wait idly for CI if an independent task can safely proceed;
- keep PRs focused and reviewable;
- after an execution-order, dependency or locked-decision change, update this file in the same or immediately following focused PR.

## 12. Immediate next action

**Start #1066 — `[Shell] Define parent navigation map and information architecture`.**

Why first:
- it is P0;
- it is open and has no recorded blocker;
- it is the first declared child of #1061;
- #1067 depends on it;
- #1067 is a direct dependency of the Living Camp renderer #1075;
- it is architecture/IA work with approved product decisions already available, so Chat can complete it without Work.

After #1066 is merged, proceed to #1067 while also advancing #1070–#1072 as the independent Living Camp contract lane.

## 13. Durable references

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

Whenever this file is read in a future session, verify current `main`, relevant issue/PR state and Supabase runtime facts before executing the next task.
