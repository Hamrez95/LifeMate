# Living Camp Rive Avatar & Animation Contract

Status: **P0 implementation contract for #1071**  
Parent Epic: #1058  
Scene contract: #1070  
First PoC actor: #1074

This contract separates **semantic LifeMate actions** from one particular Rive file/state-machine implementation. Flutter/Scene Coordinator talks in stable actor/action IDs; a versioned actor manifest maps those semantics to each `.riv` asset.

## 1. Goals

The contract must support:

- the MVP actions `idle`, `walk`, `sit`, `drink`, `wellness`, `care`, `exercise`, `wave`, `sleep`;
- controlled visual variants without changing domain meaning;
- two character families × six life-stage variants over time;
- skin-tone tinting without recoloring hair/clothing;
- deterministic action completion and route orchestration;
- future actions/characters without rewriting existing Scene Coordinator call sites;
- Reduced Motion and Low Power fallbacks;
- safe failure when an actor file/version is missing or incompatible.

## 2. Semantic action IDs

Canonical app-level action IDs are strings, not numeric Rive constants:

```text
idle
walk
sit
drink
wellness
care
exercise
wave
sleep
```

These IDs are presentation semantics only. They are not clinical/business events.

Examples:

- `drink` may be ordinary decorative hydration only when product rules allow it;
- medicine-taking must never be represented by generic `drink` or another ambient action unless an authoritative medication event explicitly requests a reviewed medication-specific action in a future contract;
- `care` means a neutral companion interaction, not a statement about another Person's health condition.

New semantic action IDs may be registered later. Old actors are allowed to declare unsupported actions and use a deterministic fallback rather than breaking.

## 3. Actor identity versus presentation state

Keep these dimensions separate:

- `actorId` — scene instance (`main_avatar`, `companion_primary`, ...);
- `characterFamilyId` — approved visual family;
- `lifeStageId` — visual stage such as `age_20` or `age_30`;
- `appearance` — skin tone and future approved cosmetic bindings;
- `actionId` — semantic action;
- `actionVariant` — controlled visual variation of the same semantic action;
- `facingVector` / resolved direction — scene orientation;
- scene position — owned by Flutter/Scene Coordinator, not trusted Rive state.

Changing an animation asset must not silently change canonical profile age, Person identity, entitlement or progression.

## 4. Artboard contract

Each actor `.riv` file exposes one primary runtime artboard declared by its manifest.

Recommended v1 names:

```text
artboard: LifeMateAvatar
state machine: LifeMateAvatarV1
```

The host must **read these names from actor manifest metadata**. Runtime code must not assume all future actors use the same hard-coded artboard/state-machine name.

### Artboard geometry

- transparent background;
- no environment, module building, localized text or shell UI inside the avatar artboard;
- one stable local ground/foot anchor at the character's standing contact point;
- visual content must stay within declared bounds for every required action;
- shadows that must interact with world geometry should be a separate actor shadow layer/asset when practical rather than baked into an oversized artboard.

## 5. Ground anchor

Every actor declares a local `groundAnchor` in normalized artboard coordinates.

Flutter places that ground anchor on the scene waypoint from #1070. Actor scale/animation must not move the logical world position itself.

If an animation visually lifts a foot/body, its local animation may move around the anchor, but Scene Coordinator remains authoritative for route position.

## 6. Direction contract

Scene Coordinator provides a normalized 2D world-facing vector or a resolved semantic direction. Actor adapters map it to directions supported by that asset.

Canonical v1 semantic directions:

```text
front_left
front_right
back_left
back_right
```

An actor manifest declares which directions it supports and how unsupported directions fall back.

### Mirroring

Horizontal mirroring is allowed **only** when a manifest explicitly marks a direction pair `mirrorSafe`.

Do not blindly mirror:

- asymmetric clothing/accessories;
- text/symbols;
- medically meaningful left/right visuals;
- hand-specific props that become incorrect when mirrored.

The PoC actor may use mirror-safe directional pairs to reduce art scope, but future actors can provide dedicated direction states without changing host semantics.

RTL/LTR does not alter world direction. Persian UI does not mirror the avatar's route.

## 7. State-machine input adapter

Rive-native input names/types are versioned actor implementation details. The recommended v1 machine exposes:

| Input | Type | Purpose |
| --- | --- | --- |
| `action_code` | Number | actor-manifest code for current semantic action |
| `direction_code` | Number | actor-manifest code for resolved visual direction |
| `variant_code` | Number | controlled variant within same action |
| `speed_scale` | Number | visual playback speed multiplier within declared range |
| `action_trigger` | Trigger | start/restart the requested action command |
| `active` | Boolean | actor is active/visible enough to animate |

Flutter must not scatter these raw names/codes through feature code. One Rive actor adapter owns them.

The app-level command remains conceptually:

```text
ActorCommand(
  actorId,
  actionId,
  facing,
  variant,
  commandId,
)
```

The adapter resolves that command through the actor manifest.

## 8. Action-code mapping

Numeric codes are local to an actor contract version and stored in the manifest.

Example only:

```text
idle      -> 0
walk      -> 1
sit       -> 2
drink     -> 3
wellness  -> 4
care      -> 5
exercise  -> 6
wave      -> 7
sleep     -> 8
```

Runtime business/scene code must never depend on these numeric values directly.

A future actor may use different internal codes while exposing the same semantic actions.

## 9. Looping versus bounded actions

Each action manifest entry declares one playback behavior:

- `loop` — continues until another command (e.g. idle/walk/sleep ambience);
- `oneShot` — emits completion and returns through host-defined next state;
- `hold` — reaches a terminal pose and waits for another command.

The manifest also declares a safe fallback action, normally `idle`.

Scene Coordinator, not Rive, decides what command follows completion.

## 10. Completion/event semantics

Required output semantic event:

```text
action_complete
```

It means only: **the visual one-shot command reached its reviewed completion point**.

It must never mean:

- medication was taken;
- exercise was completed in real life;
- a health intervention succeeded;
- a reward should be minted;
- a care relationship/consent changed.

The Flutter adapter correlates the event with the current `commandId`; stale completion from a superseded command is ignored.

Optional visual-only events may include:

- `loop_boundary`;
- `footstep_cue`;
- `effect_cue`.

They may drive sound/effects only where settings and Reduced Motion/audio policies allow. They cannot mutate canonical domain state.

## 11. Interruption policy

Actions declare whether they are interruptible.

Minimum behavior:

- `idle`, `walk`: freely interruptible;
- decorative one-shots: interruptible by navigation, lifecycle pause, Reduced Motion change or urgent shell state;
- no visual animation can block a module route;
- tapping a module immediately begins shell navigation even if an avatar one-shot is mid-animation.

When interrupted, the adapter produces a local cancellation result; it does not emit a fake `action_complete`.

## 12. Controlled variants

An `actionVariant` changes visual flavor without changing semantic meaning.

Examples:

- two neutral idle poses;
- alternate wellness stretch;
- alternate wave.

Variants are selected deterministically by Scene Coordinator (for example from a bounded sequence/seed) so tests and resume reconstruction remain stable.

Never use random animation variants to imply different clinical severity, adherence or companion health state.

## 13. Skin-tone binding

MVP appearance customization supports skin tone only.

Every actor source must keep skin regions separately addressable from:

- hair;
- eyes;
- clothing;
- accessories;
- props;
- environment/effects.

The actor manifest declares an appearance binding named:

```text
skin_tone
```

and the reviewed region/binding targets it controls.

Flutter supplies a palette token/approved color value through the Rive adapter. The exact Rive data-binding/property mechanism may evolve; feature code depends only on the semantic `skin_tone` binding.

### Color safety

- palette values are design tokens, not arbitrary persisted paint values in the first MVP;
- skin tint must not unintentionally recolor lips, eyes, hair, clothing or props;
- contrast/readability must remain acceptable in day/night lighting;
- no skin-tone option changes gameplay/progression/health meaning.

## 14. Character families and life stages

Target visual matrix:

- two approved character families;
- six life stages each: approximately `age_2`, `age_10`, `age_20`, `age_30`, `age_50`, `age_70`.

All production variants eventually expose the same **semantic** base-action contract, even when their animation implementation differs.

A missing action on an incomplete/older actor falls back through manifest-declared compatibility; it must not crash or silently select a different Person identity.

Life-stage selection comes from the approved Profile mapping. A transition between age bands is user-confirmed by Journey/Chapter logic; Rive does not calculate age.

## 15. Companion actors

Companions reuse the actor contract where practical but may support a smaller action subset, such as:

```text
idle
sit
wave
sleep
```

The manifest explicitly declares capabilities. Main-avatar route code must not assume a companion supports `walk` or `exercise`.

Companion presence/identity comes from consent-safe canonical presentation state. An actor asset does not encode a real Person's health status.

## 16. Capability discovery

Each actor manifest declares:

- `contractVersion`;
- actor asset/version;
- artboard/state-machine names;
- supported semantic actions;
- action fallback rules;
- direction capabilities/mirror-safe pairs;
- appearance bindings;
- required semantic events;
- optional visual events;
- approximate intrinsic size/scale guidance;
- compatibility range with shell actor adapter.

Renderer/Scene Coordinator asks the registry for capabilities rather than checking a character filename.

## 17. Missing/incompatible asset behavior

Required fallback chain:

1. exact requested character family + life stage + compatible contract;
2. approved compatible fallback for same family/life stage if declared;
3. neutral placeholder actor with `idle` capability;
4. accessible module/world actions remain available with actor hidden/static.

A broken/missing Rive actor may reduce visual delight but must never block Home/module navigation.

## 18. Reduced Motion

When Reduced Motion is enabled:

- autonomous walking is disabled;
- nonessential ambient loops are disabled or replaced with static/low-motion poses;
- module actions/hotspots remain unchanged;
- actor may switch directly between static semantic poses when useful;
- shell/scene must not require `action_complete` from an animation that is intentionally not running.

The host owns Reduced Motion behavior. Do not make accessibility dependent on a hidden Rive switch alone.

## 19. Low Power / lifecycle

When app is backgrounded:

- pause/stop Rive ticking;
- do not continue a hidden route timer just to keep animation continuity;
- on resume, Scene Coordinator reconstructs current deterministic scene state and commands the actor accordingly.

Low Power may reduce idle/ambient animation frequency while preserving interaction and semantics.

## 20. Day/night relationship

Day/night lighting is primarily a scene/environment concern.

Actors may expose approved appearance variants if needed for night readability, but:

- action IDs stay identical;
- route coordinates stay identical;
- night does not create a second actor identity;
- sleeping/rest behavior comes from Scene Coordinator state, not device-time logic embedded in Rive.

## 21. Animation timing

Timing is declared per action/asset in the actor manifest for orchestration/testing guidance.

- Scene Coordinator may use declared expected duration as watchdog/fallback;
- authoritative completion for one-shot animation normally comes from the actor adapter event;
- a missing completion event must time out safely and return to a neutral state rather than deadlock the scene;
- changing animation timing within compatible bounds must not require feature-code changes.

The approved product target of roughly 10 seconds at eligible zones is **scene behavior**, not a requirement that one Rive clip itself be 10 seconds long. Scene Coordinator may compose idle + action + hold within that dwell.

## 22. File/export naming

Recommended runtime layout from #1070:

```text
lifemate/assets/living_camp/v1/rive/
  avatar_family_a_age_20_v1.riv
  avatar_family_a_age_30_v1.riv
  ...
```

Editable Rive source and export notes belong in the source package owned by #1074/#1073 workflow, not mixed into feature Dart files.

File names are not semantic APIs. Registry/manifest IDs are authoritative.

## 23. Versioning

### `contractVersion`

Integer major version for the Flutter ↔ actor semantic protocol.

### `assetVersion`

Content/export version for one actor asset.

### Compatible update

May:

- refine animation curves/art;
- add an optional action/variant;
- add a direction;
- add an optional event;
- optimize geometry/performance;

provided all required v1 semantics remain valid.

### Major-contract change

Required when changing:

- meaning/type of required state-machine inputs;
- required completion semantics;
- ground-anchor interpretation;
- action capability/fallback protocol incompatibly.

The app must reject unsupported major versions and fall back safely.

## 24. Export validation for #1074

Before a `.riv` file is accepted:

- declared artboard exists;
- declared state machine exists;
- all required inputs exist with expected types;
- every supported semantic action can be invoked through manifest mapping;
- required `action_complete` behavior works for one-shots;
- direction mapping/mirroring matches manifest;
- skin tint affects only reviewed skin regions;
- ground anchor remains visually stable;
- transparent bounds do not contain accidental huge whitespace;
- no external/unreviewed text or sensitive data is embedded;
- file opens and animates in the supported Flutter Rive runtime used by implementation;
- performance/size evidence is recorded.

## 25. PoC budget handed to #1074/#1079

For the first reusable actor:

- target `.riv` compressed file size: **<= 1.5 MiB**;
- all PoC Rive actor/effect assets combined remain within #1070's **<= 2 MiB** target;
- one active PoC avatar should not create sustained raster/build frame misses by itself on Galaxy A55 Profile Mode;
- only the active actor should require full-rate animation.

If visual quality requires exceeding a budget, #1074 must record measured evidence and #1079 decides whether the scene budget changes.

## 26. Flutter adapter boundary

A single package/internal adapter should expose semantics similar to:

```text
loadActor(definition)
setAppearance(binding, value)
command(ActorCommand)
pause()
resume()
dispose()
```

and emit visual-only results/events correlated to `commandId`.

Feature screens and Scene Coordinator must not manipulate arbitrary Rive state-machine inputs directly.

## 27. Test contract for runtime integration

#1074/#1076 implementation tests must cover:

1. manifest semantic action resolves to correct actor-local code;
2. unsupported action uses declared fallback;
3. one-shot completion is correlated to current command and stale events are ignored;
4. interruption never emits false completion;
5. direction fallback/mirroring obeys capability metadata;
6. skin tint cannot mutate unrelated appearance regions through adapter mapping;
7. Reduced Motion preserves scene actions without waiting for animation;
8. pause/resume does not replay elapsed hidden loops;
9. incompatible contract version uses neutral fallback actor;
10. actor failure never blocks module hotspot/navigation.

## 28. Privacy and authority boundary

Rive is presentation only.

The actor asset/state machine must not:

- read Supabase/API data;
- infer health status;
- mint/spend rewards;
- decide entitlement;
- decide consent/authorization;
- persist Person identity;
- convert raw measurements into mood/HP/illness presentation.

A future reviewed wellbeing presentation signal (#1115) may request a neutral presentation semantic through a versioned adapter. Raw glucose/BP/BMI/HR/weight values never enter Rive inputs directly.

## 29. Example actor manifest

A concrete versioned example is committed beside this document as:

`rive_actor_manifest.v1.example.json`

It demonstrates semantic action mappings, direction capabilities, appearance binding and safe fallback without making numeric Rive codes part of the app-level API.

## 30. Definition of Done for #1071

This contract is complete when:

- artboard/state-machine discovery is versioned and manifest-driven;
- all approved base actions have stable semantic IDs;
- Rive-native inputs/codes are isolated behind one adapter;
- direction and mirror-safe behavior are explicit;
- skin-tone binding/region separation is explicit;
- visual event/completion semantics cannot mutate trusted domain state;
- future actions/characters can be added through capability/manifest data;
- Reduced Motion, lifecycle and failure fallback are explicit;
- #1074 can produce one actor without inventing another animation protocol.
