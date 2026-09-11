# Living Camp Deterministic Scene Coordinator Contract

Status: **P0 implementation contract for #1072**  
Parent Epic: #1058  
Scene topology: #1070  
Rive actor protocol: #1071  
Technical PoC: #1076

The Scene Coordinator is a deterministic Dart orchestration layer between privacy-safe presentation inputs and the Living Camp renderer/actors. It does **not** own health truth, entitlement truth, progression economy, consent, timers that must survive process death, or Rive-native state-machine details.

## 1. Responsibilities

The coordinator owns only presentation orchestration:

- resolve `day` / `night` presentation from a supplied local-time context;
- determine which resolved zones are eligible for ambient visits;
- choose a deterministic route and controlled action variant;
- advance the main avatar through route phases while the app is foregrounded;
- coordinate dwell/rest timing in memory;
- pause immediately on background/inactive lifecycle;
- reconstruct current scene state on resume instead of simulating hidden elapsed frames;
- enforce Reduced Motion and Low Power presentation policies;
- produce renderer/actor commands from stable semantic IDs;
- expose deterministic diagnostics suitable for tests/profile instrumentation.

## 2. Explicit non-responsibilities

The coordinator must never:

- query Supabase or sensitive API tables directly;
- decide whether an Account is entitled;
- decide whether a relationship implies consent;
- calculate clinical urgency from health observations;
- mint/spend trusted rewards;
- calculate Progression stage from local behavior;
- persist canonical health or financial state;
- run a permanent background ticker;
- use animation completion as proof that a real-world health action happened;
- infer pregnancy/diagnosis state from raw records.

Those states arrive only as reviewed presentation-safe inputs.

## 3. Deterministic input snapshot

The coordinator consumes an immutable `CampPresentationSnapshot` conceptually containing:

```text
snapshotVersion
accountContextKey          # opaque/non-PHI runtime isolation key
personContextKey           # opaque/non-PHI runtime isolation key
localTimeContext
motionPolicy
powerPolicy
zones[]
mainActor
companions[]
futurePresentationInputs   # optional reviewed extensions
```

### Zone presentation input

Each resolved zone entry may contain:

```text
zoneId
availability              # active | locked | expired | unavailable
ambientVisitEligible      # already resolved by reviewed adapter
interactionEnabled        # whether hotspot may navigate
routeResolverKey          # presentation-safe route handoff key
visualStage               # future optional resolved stage, default stage_1
visualVariant             # optional safe presentation variant
actionCandidates[]        # semantic Rive action IDs allowed at this zone
attentionPresentation     # none | needs_attention | explicit_ui_required
```

The coordinator accepts these values; it does not derive them from sensitive source records.

## 4. Separation of state dimensions

Never collapse these dimensions:

- **Scene phase** — where the avatar is in its ambient route.
- **Zone availability** — active/locked/expired/unavailable presentation.
- **Progression stage** — optional future resolved visual stage.
- **Attention presentation** — normalized alert presentation only.
- **Actor identity/life stage** — resolved Profile presentation.
- **Consent-safe companion presence** — resolved outside coordinator.

A Stage-3 expired zone remains Stage-3 but closed/dimmed. A locked zone is not automatically Stage-1 ownership. A route phase does not imply entitlement.

## 5. Time context

The coordinator receives a `LocalTimeContext` containing:

```text
instantUtc
localDateTime
ianaTimeZone
sunriseLocal?             # optional resolved astronomical time
sunsetLocal?              # optional resolved astronomical time
source                    # coarse_location | selected_city | fallback
```

### Day/night rule

If valid sunrise/sunset are available for the local date:

```text
day   = sunrise <= localDateTime < sunset
night = otherwise
```

Fallback when astronomical context is unavailable:

```text
day   = 06:00 <= local time < 20:00
night = otherwise
```

The coordinator does not request GPS. Location acquisition/storage is outside this layer.

### Boundary behavior

At an exact boundary:

- exact sunrise starts `day`;
- exact sunset starts `night`.

Timezone/date changes trigger reconstruction with a new input snapshot. Do not incrementally adjust a hidden long-running timer from the old timezone.

## 6. Scene mode

Canonical scene modes:

```text
loading
ready_day
ready_night
paused
reduced_motion
safe_degraded
```

These are presentation modes, not domain status.

### `safe_degraded`

Used when optional presentation inputs/assets are unavailable but Home/module navigation can remain truthful. It must not fabricate missing companion/entitlement/health state.

## 7. Main-avatar route phases

Canonical orchestration phases:

```text
home_rest
select_next_zone
walk_to_zone
zone_action
zone_dwell
walk_home
cycle_rest
paused
```

`paused` is lifecycle/policy state; it is not persisted as historical user activity.

### Route behavior

For the full future route:

1. start/rest at `lifemate_home.home_rest`;
2. build ordered eligible-zone candidates from the snapshot;
3. visit eligible zones through configured route topology;
4. perform one deterministic semantic action/variant at each zone;
5. spend approximately the approved dwell budget at that zone;
6. return to central home after the eligible sequence;
7. rest approximately one minute;
8. start a new deterministic cycle if still foreground/allowed.

PoC #1076 intentionally uses only `home → wellmate → home`.

## 8. Route topology versus eligibility

Route topology comes from versioned scene/config data. Eligibility comes from the resolved presentation snapshot.

The coordinator must not contain logic like:

```text
if product == WellMate then x=255,y=720
```

Instead:

```text
scene manifest -> stable waypoint/zone topology
snapshot -> eligible zone IDs
coordinator -> ordered route plan
```

A new zone can be added through registry/config + route topology without rewriting unrelated coordinator branches.

## 9. Stable candidate ordering

To keep reconstruction/test behavior deterministic, candidate order is derived from configured route order, not map iteration order and not random shuffle.

Example configured route order for the future Camp:

```text
wellmate
caremate
fitmate
reproductive_context
```

Only eligible IDs are retained.

The exact production order may evolve through versioned route config. The coordinator API must not hard-code this example.

## 10. Deterministic action selection

Each eligible zone supplies a bounded ordered set of approved semantic `actionCandidates`.

The coordinator selects a controlled variant from deterministic inputs such as:

```text
sceneConfigVersion
routeCycleOrdinal
zoneId
actorDefinitionId
```

A stable hash/selection function may resolve an index. The same inputs produce the same choice.

### No nondeterministic RNG dependency

Do not call ambient global `Random()` without a controlled seed. Tests/resume reconstruction must be able to reproduce the same variant.

### No clinical inference

Action selection never branches on raw glucose, BP, weight, medication records or similar measurements. A future #1115 reviewed wellbeing presentation adapter may expose a bounded safe presentation signal; the coordinator treats it as another versioned presentation input with neutral fallback.

## 11. Timing model

Foreground orchestration may use an injectable monotonic clock/ticker.

Time budgets are configuration values, not scattered magic constants.

PoC-compatible defaults:

```text
zoneDwellTarget ≈ 10 seconds
cycleRestTarget ≈ 60 seconds
```

Walk duration is derived from actor movement presentation/config and route geometry, not a domain event deadline.

### No permanent background timer

When lifecycle leaves active foreground:

- cancel/suspend animation ticker;
- record only the minimal ephemeral reconstruction baseline if needed;
- do not wake periodically to advance the Camp;
- do not simulate hidden avatar visits while app is backgrounded.

On resume, rebuild from current time + latest snapshot and enter a deterministic present state.

## 12. Reconstruction policy

The Living Camp is ambient presentation, not a game simulation requiring exact offline replay.

On app resume/process recreation:

1. resolve current authorized presentation snapshot;
2. resolve current day/night mode from current local time;
3. apply current motion/power policy;
4. rebuild eligible route candidates;
5. place the main avatar into a deterministic neutral/restart state, normally `home_rest`, unless a separately reviewed restoration token is valid;
6. restart foreground orchestration.

Do **not** replay every missed route/action from elapsed background time.

## 13. Optional restoration token

A lightweight non-sensitive token may preserve presentation continuity across short recreation:

```text
sceneConfigVersion
snapshotPresentationVersion
routeCycleOrdinal
phase
zoneId?
phaseStartedMonotonicBaseline?
```

It must not contain PHI or trusted entitlement/reward values.

Invalidate it when:

- Account/Person context changes;
- scene contract/config major version changes;
- relevant authorization/presentation snapshot version is incompatible;
- lifecycle gap exceeds configured restoration tolerance;
- asset/actor contract compatibility changes.

Invalid restoration always falls back safely to `home_rest`.

## 14. Reduced Motion policy

When Reduced Motion is active:

- disable autonomous walk animation;
- disable camera reactions/nonessential ambient movement;
- keep every hotspot and route available;
- actor may use a neutral static/low-motion pose;
- module tap navigates immediately exactly as normal;
- no coordinator phase may wait for a Rive completion event that will never run.

Recommended coordinator representation:

```text
mode = reduced_motion
avatarPresentation = static_home_or_contextual_pose
```

The UI must not communicate important status only through missing motion.

## 15. Low Power policy

Low Power is distinct from Reduced Motion.

It may:

- lower ambient effect frequency;
- keep non-active actors static;
- reduce idle animation duty cycle;
- skip decorative action variants;
- prefer simpler lighting/effect variants.

It must not:

- disable module access;
- hide explicit alerts;
- change entitlement/authorization meaning;
- stop required conventional UI.

## 16. Night policy

At night:

- route loop is normally suspended;
- main avatar resolves to home/rest presentation;
- companions resolve to their approved resting/static presentation;
- environment lighting/night layers activate;
- module hotspots stay fully available;
- explicit urgent/safety UI still works through normal shell channels.

Night is not an offline mode and not a lockout state.

## 17. Lifecycle state machine

Conceptual transitions:

```text
boot -> resolve snapshot -> ready
ready -> app inactive/background -> paused
paused -> resume -> reconstruct -> ready
ready_day -> sunset/timezone snapshot change -> ready_night
ready_night -> sunrise/timezone snapshot change -> ready_day
ready_* -> Reduced Motion enabled -> reduced_motion
reduced_motion -> setting disabled -> reconstruct -> ready_*
any ready mode -> incompatible/missing optional presentation -> safe_degraded
safe_degraded -> valid snapshot/assets restored -> reconstruct -> ready_*
```

Lifecycle transitions are idempotent. Repeated pause/resume callbacks must not duplicate tickers or actor commands.

## 18. Command model

Coordinator outputs semantic commands, never Rive-native codes.

Conceptually:

```text
SceneCommand
  SetSceneMode(day/night/...)
  PlaceActor(actorId, waypointId)
  MoveActor(actorId, routeSegmentId, commandId)
  PlayActorAction(actorId, actionId, variant, facing, commandId)
  SetActorActive(actorId, bool)
  SetZonePresentation(zoneId, stage, variant, availability)
  SetAmbientEffect(effectId, enabled)
```

Renderer/Rive adapters translate these into pixels/animation inputs.

## 19. Actor result handling

Rive adapter results are presentation-only and correlated to `commandId`.

On `action_complete`:

- if commandId == current expected command, coordinator advances presentation phase;
- stale/superseded completion is ignored;
- completion does not write domain state.

On timeout/error:

- cancel the visual command;
- fall back to neutral actor state;
- continue or safely reset route presentation;
- never deadlock navigation.

## 20. Module tap behavior

A user interaction preempts ambient orchestration.

On active module hotspot tap:

1. UI produces the approved 300–500 ms response where motion policy permits;
2. shell navigation starts immediately after that response budget;
3. coordinator cancels/suspends conflicting ambient actor commands;
4. user never waits for avatar travel/dwell.

Locked/unavailable/expired behavior comes from resolved zone presentation and shell/module route contract, not from route animation state.

## 21. Attention/alert presentation

Coordinator may consume normalized presentation-safe attention state:

```text
none
needs_attention
explicit_ui_required
```

It may orchestrate a bounded zone pulse for `needs_attention` when motion settings allow.

It must not:

- calculate severity;
- turn raw clinical values into attention state;
- suppress explicit standard UI for urgent/safety-sensitive items;
- make color/animation the only alert channel.

## 22. Companion orchestration

Companions are resolved outside the coordinator from valid relationship + consent-safe presentation state.

Coordinator receives only approved companion presentation entries such as:

```text
actorDefinitionId
assignedZoneId
allowedActions
visible
```

MVP companions remain at fixed contextual zones with lightweight idle/static behavior. The main avatar may approach/interact through a configured semantic `care` action.

If a companion disappears from a new authorized snapshot (for example after consent revocation), coordinator removes that presentation immediately on reconciliation without exposing the reason.

## 23. Account / Person switching

Account/Person context switch is a hard scene isolation boundary.

Required behavior:

1. pause/cancel current ticker and actor commands;
2. clear ephemeral route/restoration state from old context;
3. hide old companion/zone presentation while new context resolves;
4. resolve a fresh snapshot for the new context;
5. reconstruct from safe Home state.

Never keep the previous Person's companion scene visible because a widget/animation stack survived navigation.

## 24. Future Progression input

A future canonical Progression system may provide resolved presentation-safe values such as:

```text
zoneStage
zoneVariant
unlockedCosmeticIds
```

Coordinator only forwards/composes them with scene presentation. It never:

- calculates point balances;
- decides whether an upgrade was earned;
- decrements currency;
- resets progress on entitlement expiry.

When Progression is disabled/unavailable, deterministic fallback is Stage 1/default presentation.

## 25. Future wellbeing presentation input

#1115 may later provide a reviewed/versioned bounded signal such as a neutral presentation category/action preference.

Required coordinator behavior:

- accept only the reviewed derived signal contract;
- never receive raw health observations as scene decision inputs;
- missing/unknown signal -> neutral default;
- unsupported signal version -> neutral default + diagnostics;
- no reward or clinical inference inside coordinator.

## 26. Configuration model

Coordinator behavior is driven by versioned configuration for:

- route order/topology IDs;
- eligible ambient action candidate IDs;
- timing budgets;
- deterministic selection algorithm version;
- Reduced Motion/Low Power policy toggles;
- restoration tolerance;
- day/night presentation flags.

Config must be bounded and validated. Remote config may select reviewed behavior within the renderer/coordinator contract; it must not download arbitrary executable logic.

## 27. Diagnostics

Privacy-safe coordinator diagnostics may record:

```text
scene_mode
scene_config_version
route_phase
zone_id
actor_definition_id
command_type
command_duration_ms
actor_timeout_count
reconstruction_reason
reduced_motion_enabled
low_power_enabled
```

Do not log:

- Person names;
- medication names;
- raw observations;
- pregnancy/diagnosis details;
- companion health state;
- consent text;
- trusted balances.

## 28. Testability seams

Coordinator implementation must inject/abstract:

- wall/local time provider;
- monotonic foreground clock;
- scene config/manifest reader;
- actor command sink;
- presentation snapshot source;
- lifecycle/motion/power policy inputs.

Unit tests must not sleep for real 10/60-second intervals.

## 29. Required deterministic test matrix

Implementation under #1076/#1077 must cover at least:

### Day/night
1. 05:59 fallback -> night;
2. 06:00 fallback -> day;
3. 19:59 fallback -> day;
4. 20:00 fallback -> night;
5. exact astronomical sunrise -> day;
6. exact sunset -> night;
7. timezone change reconstructs without replaying hidden route.

### Eligibility / route
8. only WellMate active -> `home → wellmate → home`;
9. locked zone is skipped for ambient visit but hotspot remains presentation-configurable;
10. zero eligible zones -> remain/rest at home without busy loop;
11. configured new unknown-to-old optional zone does not corrupt known route; validated compatibility rules apply.

### Determinism
12. same snapshot/config/cycle ordinal -> same action variant;
13. next cycle ordinal may choose another approved variant deterministically;
14. map/dictionary iteration order cannot alter route choice.

### Lifecycle
15. background cancels ticker/actor commands;
16. resume reconstructs from current snapshot/time;
17. repeated resume does not create duplicate tickers;
18. long background gap does not replay missed visits.

### Reduced Motion / Low Power
19. Reduced Motion emits no autonomous walk requirement and preserves hotspots;
20. no animation completion wait in Reduced Motion;
21. Low Power reduces decorative activity without changing navigation/authorization state.

### Actor fault
22. stale `action_complete` ignored;
23. action timeout returns to neutral presentation;
24. missing actor uses safe fallback and does not block module entry.

### Privacy/isolation
25. Account/Person switch clears old scene ephemeral state;
26. removed companion disappears after reconciliation;
27. missing Progression/wellbeing input yields neutral default;
28. coordinator API has no raw health-observation input type.

## 30. Example trace fixtures

A machine-readable fixture file is committed beside this contract:

`scene_coordinator_traces.v1.json`

It captures representative deterministic input/output expectations without implementing the runtime prematurely.

## 31. PoC #1076 handoff

#1076 implements the smallest slice:

```text
snapshot: WellMate eligible only
start: lifemate_home.home_rest
phase: home_rest
→ walk_to_zone(wellmate)
→ zone_action(wellness or approved deterministic variant)
→ zone_dwell
→ walk_home
→ cycle_rest
```

State remains synthetic/privacy-safe. No PHI, live companion data or trusted entitlement mutation is needed to prove the coordinator/renderer/actor integration.

## 32. #1077 handoff

#1077 owns the concrete implementation/testing of:

- local sunrise/sunset resolver + 06:00/20:00 fallback;
- timezone/date-change reconciliation;
- lifecycle pause/resume wiring;
- Reduced Motion preference wiring;
- Low Power behavior where platform signal/policy is available;
- debug time override used only by development/test builds.

The coordinator contract must make those inputs injectable rather than hard-coding platform APIs.

## 33. Definition of Done for #1072

This design is complete when:

- scene state/route phases are explicit;
- day/night inputs and boundary semantics are explicit;
- foreground timing versus background reconstruction is explicit;
- deterministic route/action selection is defined;
- Reduced Motion/Low Power behavior is explicit;
- lifecycle/account-person isolation is explicit;
- actor completion/error handling cannot mutate trusted domain state;
- future Progression/wellbeing inputs have neutral optional seams;
- testability seams and deterministic fixtures are defined;
- #1076/#1077 can implement without inventing another scene-state architecture.
