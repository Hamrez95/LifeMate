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

The scene keeps the 1000×2000 logical coordinate contract. Distant terrain
drifts by at most three logical pixels behind independent foreground zones;
local zone light glows breathe gently. The editable Flutter vector actor walks
the central path and performs `drink` and `wellness` at its endpoints. Its
`idle` pose is used with Reduced Motion. `TickerMode` pauses scene animation
when the shell is not visible or a modal sheet is open. Navigation does not
depend on animation completion.

This is a free native Flutter 2.5D implementation. It is **not** a `.riv`
export. Issue #1074's Rive deliverable remains unmet because the authenticated
Free workspace did not offer `.riv` export. Device frame timing, GPU cost and
memory use have not been measured; the automated checks cover rendering,
navigation, actor actions and Reduced Motion.
