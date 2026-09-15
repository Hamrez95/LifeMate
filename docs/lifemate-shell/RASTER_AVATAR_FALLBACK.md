# Living Camp raster avatar fallback

This small two-family raster package is a visual bridge, not completion of
#1074. It makes the Camp feel inhabited while the real reusable Rive asset is
authored.

## Included assets

- `adult_female_idle.png`
- `adult_male_idle.png`

Both are 256 × 384 PNGs with transparent backgrounds. Their combined runtime
size is approximately 162 KiB. They are original generated illustration
exports for LifeMate's internal prototype use; no third-party character source
material was used.

## Intentional limitations

- only the neutral `idle` pose is rendered;
- the tiny vertical drift is decorative and stops for Reduced Motion, accessible
  navigation, inactive lifecycle, or Flutter `TickerMode`;
- no actor tap, navigation, domain mutation, health claim, or audio depends on
  this animation;
- flattened artwork is **not** skin-tintable safely, so the runtime does not
  pretend it is. The Rive source must expose `skin_tone` separately from hair
  and clothing under `RIVE_AVATAR_CONTRACT.md`.

## Replacement seam

`CampSceneActor` is world-anchor based and ignores pointer events. Replace the
`CampAvatarFallback` builder in `CampHome` with the versioned Rive actor adapter
when #1074 delivers a real `.riv`; keep `actorId`, anchor and zone semantics
stable. Route choreography remains owned by #1076.