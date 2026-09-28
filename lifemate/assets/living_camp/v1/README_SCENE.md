# Living Camp layered dusk scene

Exported 2026-09-25 for the Flutter parent shell, using the user-supplied
North Star screenshot as the composition reference. The generated raster art
was made with the built-in image generation tool, then encoded as WebP. The
prompt requested a clean blue-hour terrain plate with empty building lots,
plus a separate transparent moon-garden prop. No UI text or navigation is
embedded in the images.

The runtime composes `raster/base/camp_terrain_dusk.webp` (291,298 bytes),
the five existing transparent Stage-1 zone assets, and
`raster/zones/reproductive_context/stage_1/moon_garden.webp` (297,302 bytes).
The moon garden is decoration, not a second `reproductive_context` hotspot.
Zone hit targets, signs, state badges, the Today card, and the four primary
navigation destinations are Flutter widgets. The legacy day background remains
in the catalog for compatibility.

On the first authenticated launch, a three-step Camp guide appears after the
launch reveal and can be replayed from the shared profile. Its completion flag
is a device-level preference; it stores no account or health data. The guide
uses original vector icons and is independent of the future character art.

In production, WellMate and CareMate house availability is refreshed from the
authenticated `/api/v1/capabilities` snapshot (`applications`). If that read is
temporarily unavailable, the shell stays navigable and the product APIs remain
the authorization boundary. CocoonMate remains launchable because its reviewed
authenticated bootstrap resolves its initial enrollment. Entitlement decisions
remain inside each product's server-backed feature flows.

The scene keeps the 1000×2000 logical coordinate contract. Distant terrain
drifts by at most three logical pixels behind independent foreground zones;
local zone light glows breathe gently. A separate Flutter window-light pass
fades the house and product-site lights down during daylight and adds warm
window glows at night, following the existing local sunrise/sunset easing.
The day illustrations still contain baked-in warm pixels beneath the masks, so
the light pass remains a visual approximation that needs device review.

An editable Flutter vector route prototype can follow a deterministic home →
WellMate → home path on the 1000×2000 world canvas. At WellMate it plays
one-shot `wellness` and `drink` actions, then returns home. It is hidden by
default in first-release Camp because the current character art is a prototype;
only the opt-in PoC widget test enables it. A future animator can replace the
renderer without changing the shell. `TickerMode` pauses the optional prototype
when the shell is not visible or a modal sheet is open.

This is a free native Flutter 2.5D implementation. It is **not** a `.riv`
export. Issue #1074 is being fulfilled with the approved editable Flutter
vector substitute because the authenticated Free Rive workspace did not offer
`.riv` export. Device frame timing, GPU cost and memory use have not been
measured; automated checks cover route sampling, rendering, navigation, actor
actions, lifecycle pause/resume and Reduced Motion.
