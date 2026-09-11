# Living Camp Layered Scene & Responsive Composition Contract

Status: **P0 implementation contract for #1070**  
Parent Epic: #1058  
Parent shell/navigation: #1061 / #1066  
Future progression: #1111 / #1114

This contract turns the approved Living Camp North Star into a versioned asset/runtime boundary. It deliberately defines **scene topology and export rules**, not final artwork. #1073 produces the master art package and #1075 implements the renderer against this contract.

## 1. Product invariants

- Fixed elevated/isometric camera; no pan, zoom, joystick or free exploration.
- Flutter owns layout, routing, semantics, state and scene orchestration.
- Static raster layers provide most environment depth.
- Small independent Rive artboards provide actors and selected ambient effects.
- Flame/Unity/3D are out of MVP unless #1079 measurements prove the agreed Flutter + Rive approach insufficient.
- The North Star image is a design reference, **not** a monolithic runtime image.
- Module navigation must remain immediate and independent from avatar movement.
- Reduced Motion and screen-reader use must preserve every route/action without requiring scene animation.

## 2. Canonical logical world

The Camp uses a locale-neutral logical coordinate space:

```text
width  = 1000 world units
height = 2000 world units
origin = top-left
x grows toward physical right
y grows downward
```

All scene anchors, zone positions, actor waypoints, occlusion boundaries and hotspots are stored in this logical space. They are never stored as raw device pixels.

### Why 1:2

A 1:2 reference world sits near common modern Android phone aspect ratios while allowing controlled crop for 16:9 through very-tall phones. It gives one deterministic topology without stretching art per device.

### Locale rule

The world itself does **not** mirror in RTL. A WellMate zone at logical `x=220` remains at that physical world position in Persian and English. Only labels, conventional UI, directional icons and shell chrome follow Directionality.

## 3. Supported viewport range

MVP phone composition is certified for portrait content viewports whose width/height ratio is:

```text
0.41 <= viewportWidth / viewportHeight <= 0.60
```

This covers approximately 22:9 through 5:3/16:9 phone-class viewports after shell/system insets.

For wider tablet/foldable panes, the renderer must **cap the Camp viewport** at the supported composition range and fill remaining space with shell/background treatment. It must never horizontally stretch the Camp to fill a tablet.

## 4. Composition-safe region and bleed

### Core safe composition rectangle

All identity-critical objects, module-zone anchors, companion anchors and required hotspots must fit inside:

```text
x: 110 .. 890
y: 140 .. 1860
```

This is the intersection-safe region designed to survive the supported cover crop range.

### Decorative bleed region

The areas outside the core safe rectangle are decorative bleed. They may contain sky, vegetation, terrain, water continuation, shadows or nonessential ambience, but never the only representation of:

- a module entry;
- the central LifeMate home;
- an alert affordance;
- a required companion interaction;
- required localized text.

### Crop algorithm

1. Determine the actual **scene viewport** after shell/system layout.
2. Scale the 1000×2000 logical world uniformly using `BoxFit.cover` semantics.
3. Center the world in the viewport.
4. Crop only overflow; never non-uniformly scale x/y.
5. Map every Flutter hotspot/semantic node using the exact same transform.
6. Assert the core safe rectangle remains visible for certified phone ratios.

A future theme or stage pack must use the same logical world dimensions unless a new scene-contract major version is introduced.

## 5. Scene viewport versus shell chrome

`sceneViewport` means the rectangle owned by the Home/Living Camp content after the parent shell decides system insets and persistent navigation chrome.

- Scene assets never contain a fake status bar, bottom navigation, notch padding or device frame.
- Decorative background may extend behind safe insets if #1075 chooses immersive rendering, but interactive hotspots are clamped to tappable safe areas.
- Persistent bottom navigation remains a Flutter shell responsibility.
- A Today Peek Sheet overlays the scene; it does not resize/re-author the world coordinates.

## 6. Stable layer stack

The manifest uses integer `z` values so new layers can be inserted without rewriting existing ordering.

| z range | Layer family | Typical content |
| ---: | --- | --- |
| 0–9 | `background` | sky, distant gradient, far depth |
| 10–19 | `environment_back` | distant trees/rocks/mountains |
| 20–29 | `ground` | base terrain, paths, shoreline |
| 30–39 | `water` | static water base + optional small effect anchor |
| 40–59 | `zone` | replaceable module/home Stage-N visuals |
| 60–69 | `actor_back` | actors currently behind foreground occluders |
| 70–79 | `foreground` | near vegetation, bridge edges, framing occlusion |
| 80–89 | `lighting` | night tint, lamps, local glows, shadows |
| 90–99 | `ambient_effect` | bounded Rive/raster ambient effect anchors |
| 100+ | Flutter-only semantic/hotspot overlay | invisible hit targets and semantics |

Hotspots are **not rasterized** into art. Their geometry and semantic action live in the manifest/Flutter layer.

## 7. Required MVP zone identities

Stable `zoneId` values:

- `lifemate_home`
- `wellmate`
- `caremate`
- `reproductive_context`
- `fitmate`

`reproductive_context` is the stable scene location whose resolved visual may represent CocoonMate or Women Health. The topology must not create two competing active locations for this context.

### `zoneId` is not `moduleId`

A zone is scene topology. A module is a routable product identity. A resolver may map one zone to different module presentation/entry behavior, but those concepts remain separate.

## 8. Future progression compatibility

Every zone supports an independent visual stage/variant input without changing:

- `zoneId`;
- anchor coordinates;
- hotspot geometry;
- route semantics;
- actor waypoints;
- alert target identity.

Initial visual direction is deliberately **modest Stage 1**.

Manifest stage values are open-ended strings such as:

```text
stage_1
stage_2
stage_3
...
```

No renderer code may assume a fixed maximum stage count.

### Stage resolution

Conceptually:

```text
(zoneId, requestedStage, themeVariant, timeOfDay)
  -> compatible asset entry
  -> fallback chain
```

Required fallback:

1. exact compatible requested stage/variant;
2. same stage default theme/time-compatible variant;
3. highest compatible lower stage when explicitly declared compatible;
4. `stage_1` default;
5. zone-safe placeholder that preserves hotspot/route semantics.

Entitlement presentation (`active/locked/expired`) is an orthogonal dimension and must never rewrite trusted progression stage.

## 9. Day/night asset model

Day/night must avoid duplicating the entire scene when a small overlay can express the change.

Preferred order:

- base/environment/ground: shared day asset where visually acceptable;
- optional explicit night alternative only for layers that truly change;
- one bounded global night tint/lighting layer;
- individual lamp/torch/glow overlays;
- actor state changes handled by Scene Coordinator/Rive, not pre-baked into background.

Only the currently needed large day/night variant should remain decoded when memory pressure requires eviction. Do not keep duplicate full-resolution scene copies resident by default.

## 10. Runtime export dimensions

### Full-world raster

Default runtime full-world export canvas:

```text
1536 × 3072 px
```

This is a 1:2 raster mapped to the 1000×2000 logical world.

A full-world layer may use a lower resolution when visually equivalent. It must not exceed 1536×3072 in MVP without an evidence-based exception documented in the asset manifest.

### Zone/foreground overlays

- Export to the tightest transparent bounding box that preserves required shadow/bleed.
- Longest edge target: <= 1024 px for ordinary zone overlays.
- Exceptional foreground/light overlays may exceed 1024 px only when they cover a large world area; document why.
- The manifest records logical bounds separately from raster pixel dimensions.

### Rive

Rive artboards are vector/runtime assets and are budgeted separately under #1071/#1074. Do not rasterize the avatar into every scene frame.

## 11. Runtime formats

### Opaque raster layers

Preferred: **WebP** (high-quality lossy where visually safe).

Use for:
- sky/background;
- opaque ground/environment layers;
- non-textural large surfaces where compression artifacts remain invisible at target scale.

### Transparent raster overlays

Preferred: **lossless WebP with alpha**. PNG is an allowed fallback when export/tooling compatibility or visual validation proves it safer.

Use for:
- zone overlays;
- foreground occlusion;
- lights/glows when not Rive;
- transparent environmental details.

### Prohibited in runtime art

- text baked into environment images;
- personally identifying/user-generated health content;
- unlicensed competitor artwork;
- one giant animated GIF/video loop for the Camp;
- SVG containing unreviewed executable/external references.

Localized labels remain Flutter text.

## 12. Source/master package

Editable source art is not bundled through Flutter pubspec.

Recommended repository shape for #1073:

```text
assets/lifemate/living_camp/source/v1/
  README.md
  provenance.json
  master/                 # editable layered source(s)
  references/             # approved internal references only

lifemate/assets/living_camp/v1/
  manifest.json
  raster/
    base/
    zones/
    foreground/
    lighting/
  rive/
```

Source formats may be PSD/KRA/other editable layered formats chosen by the art workflow, but runtime code consumes only reviewed exports plus `manifest.json`.

Do not add the `source/` tree to Flutter assets.

## 13. File naming

Runtime file names are lowercase snake_case and do not contain localized product names.

Examples:

```text
raster/base/camp_background_day.webp
raster/base/camp_ground.webp
raster/zones/wellmate/stage_1/default_day.webp
raster/zones/wellmate/stage_1/default_night.webp
raster/zones/fitmate/stage_1/under_construction_day.webp
raster/foreground/near_vegetation.webp
raster/lighting/night_tint.webp
rive/avatar_adult_a_v1.riv
```

File names are implementation details. Stable identity is carried by manifest IDs, not inferred from file paths.

## 14. Manifest contract

Runtime assets are declared in a versioned manifest; Flutter must not discover them by directory scanning or construct file paths from hard-coded stage numbers.

Required top-level fields:

- `contractVersion`
- `sceneId`
- `sceneVersion`
- `logicalSize`
- `certifiedAspectRatio`
- `safeRect`
- `layers`
- `zones`
- `actors`

Every asset entry includes a stable `assetId`, runtime path, logical bounds/anchor, `z`, day/night applicability and compatibility metadata where relevant.

A concrete example is committed beside this document as `scene_manifest.v1.example.json`.

## 15. Zone manifest requirements

Each zone definition includes:

- stable `zoneId`;
- logical anchor;
- logical hotspot rectangle or polygon reference;
- semantic localization key;
- optional route/module resolver key;
- visual catalog entries keyed by open-ended stage/variant;
- declared fallback stage;
- actor interaction anchor(s);
- alert presentation anchor;
- optional occlusion group.

The visual catalog must be replaceable without editing the scene topology fields.

## 16. Hotspot and semantic rules

- Flutter creates a semantic/tappable overlay from manifest geometry.
- Effective touch target must be at least **48×48 logical dp on device**, even if visible art is smaller.
- Expanding hit slop must not create ambiguous overlap; if overlap is unavoidable, explicit priority is declared in manifest/config.
- Every hotspot has a localized accessible name and action hint.
- Selected/attention state is never color-only.
- Reduced Motion never removes a hotspot.
- A user never has to wait for an avatar to reach a hotspot before navigation.

## 17. Actor and waypoint geometry

Scene topology may declare named actor anchors/waypoints such as:

```text
home_rest
wellmate_approach
wellmate_action
caremate_approach
fitmate_action
reproductive_approach
```

Coordinates belong to the scene manifest; action meaning belongs to the Scene Coordinator/Rive contract (#1071/#1072).

Do not encode a fixed loop order into the asset file names or raster art.

## 18. Occlusion model

2.5D depth is deterministic, not inferred from image pixels.

Use explicit layer ordering plus optional logical occlusion boundaries. Actor z-placement may change at named route segments where the avatar passes behind/in front of foreground elements.

MVP must avoid a complex general-purpose depth engine. If an actor needs to cross a foreground object, model the minimum explicit route/occlusion transition required and keep it data-driven.

## 19. Asset/package budgets

These are **PoC target budgets**, verified and revised from measurements under #1079 rather than silently exceeded.

### Packaged size

- all Living Camp raster exports for PoC: **<= 10 MiB compressed**;
- first PoC Rive actor/effects combined: **<= 2 MiB compressed**;
- total incremental Living Camp asset contribution for PoC: **<= 15 MiB**.

### Runtime decoded memory

On the Galaxy A55 Profile Mode reference:

- target incremental decoded scene/actor memory after stable first frame: **<= 48 MiB**;
- soft ceiling during day/night swap/preload: **<= 64 MiB**;
- if measurements exceed the soft ceiling, reduce raster dimensions/simultaneous residency before adding more ambience.

These budgets exclude the rest of the LifeMate app/runtime and must be reported as deltas against the parent shell baseline.

### Animation residency

Only the currently active actor/zone should require full animation. Inactive actors/effects use static/lightweight state where possible.

## 20. Performance acceptance targets handed to #1079

#1070 defines the measurement targets; #1079 records device evidence.

On Galaxy A55 and the agreed lower-mid reference tier:

- target steady-state **60 FPS** on 60 Hz presentation;
- p95 build and raster frame time each should stay under **16.7 ms** during ordinary Camp idle/walk interaction;
- p99 frames over **33.3 ms** must be investigated and attributed;
- cold scene asset decode/first meaningful Camp frame target: **<= 1200 ms** after shell is ready;
- warm return to already-cached Camp target: **<= 500 ms**;
- five-minute foreground loop must show no unbounded memory growth;
- backgrounding pauses scene animation; resume reconstructs deterministic current state rather than simulating elapsed animation frames.

These are engineering targets, not permission to hide degraded accessibility or functionality to hit FPS.

## 21. Responsive validation matrix

#1073/#1075 must capture evidence at minimum for these logical viewport cases:

| Case | Width:height | Expected behavior |
| --- | --- | --- |
| short phone | 9:16 | centered cover crop; all core zones visible |
| common modern | 9:19.5 | centered; extra vertical world naturally visible/cropped as defined |
| tall phone | 9:20 | centered; all core zones/hotspots visible |
| very tall | 9:22 | horizontal edge bleed may crop; core safe rect remains visible |
| narrow + large text | same scene ratio | world unaffected; Flutter labels/actions reflow |
| Persian RTL | same geometry | scene does not mirror; semantic order/chrome follows RTL |
| English LTR | same geometry | identical world topology |

Add at least one test with a display cutout/system inset and one with bottom navigation + Today Peek Sheet overlay.

## 22. Automated renderer tests required by #1075

The renderer implementation must make these contracts testable:

1. world-to-screen transform uses uniform scale;
2. safeRect remains within certified phone viewports;
3. hotspot screen transform matches the rendered asset transform;
4. no hotspot is clipped below minimum accessible target size;
5. stage swap does not move zone anchor/hotspot;
6. day/night swap does not change navigation geometry;
7. missing stage falls back deterministically;
8. RTL/LTR do not mirror world coordinates;
9. Reduced Motion keeps identical semantic actions;
10. malformed/incompatible manifest fails to a safe Home state, not a crash loop.

## 23. Provenance and licensing

Every source/master package includes provenance metadata for each nontrivial visual source:

- `assetId` / source file;
- creator/owner;
- original, commissioned, generated or licensed classification;
- tool/model used when AI-generated, where required by internal policy;
- source/reference URL when applicable;
- license/usage rights;
- date;
- reviewer/status.

Competitor screenshots may inform research but must not be copied into runtime art.

## 24. Privacy and health-data boundary

The scene asset/manifest layer contains no live Account/Person/health state.

It may expose stable presentation slots such as `zoneId`, `actorAnchor` or future `stage` inputs. A separate reviewed adapter resolves authorized/canonical state into presentation-safe values.

Never put in manifest/runtime art:

- Person names;
- pregnancy/diagnosis truth;
- medication names/schedules;
- health measurements;
- entitlement tokens;
- relationship/consent identifiers;
- trusted reward balances.

## 25. Versioning

`contractVersion` follows an integer major contract version. `sceneVersion` is a content version string.

### Compatible content update

May add:

- a new stage/variant asset;
- a new optional decorative layer;
- a new actor/effect asset that old runtimes can safely ignore;
- replacement art under an existing compatible asset entry.

### Contract-major change

Required when changing semantics such as:

- logical world dimensions;
- coordinate origin meaning;
- mandatory manifest field meaning;
- hotspot geometry interpretation;
- incompatible layer/actor protocol.

Older clients must fail safely when a manifest requires a newer unsupported contract.

## 26. #1073 handoff checklist

The art-production task must deliver:

- editable layered source package;
- provenance/license metadata;
- runtime day/night/base exports;
- independent Stage-1 zone exports;
- FitMate under-construction presentation;
- foreground/lighting exports;
- manifest populated from the reviewed topology;
- screenshots proving supported crop range;
- compressed and decoded-size report;
- no flattened North Star runtime shortcut.

## 27. #1075 handoff checklist

The renderer must:

- parse/validate versioned manifest;
- map logical world to screen deterministically;
- render independent ordered layers;
- resolve zone visual by stable `zoneId` + stage/variant with fallback;
- expose semantic/hotspot overlay independently from art;
- allow placeholder assets while art is unavailable;
- not depend on Progression, entitlement or raw health tables for topology;
- expose instrumentation needed by #1079.

## 28. Definition of Done for #1070

This contract is complete when:

- logical coordinate system and certified aspect range are fixed;
- safe composition region and crop algorithm are explicit;
- layer stack and stable zone identities are explicit;
- Stage-1/future-stage separation is explicit;
- day/night, formats, dimensions and package/memory budgets are explicit;
- source/runtime folder and naming rules are explicit;
- versioned manifest requirements are explicit;
- responsive/accessibility test matrix is explicit;
- privacy/backend boundaries are explicit;
- #1073/#1075 can implement without inventing another scene topology contract.
