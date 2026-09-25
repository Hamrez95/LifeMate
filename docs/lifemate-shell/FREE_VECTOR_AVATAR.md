# Free Living Camp vector avatar

This is a source-editable Flutter `CustomPainter` alternative for the adult avatar motions requested in #1074. The Rive workspace available for this task is on the Free plan, which does not permit `.riv` export. This implementation is **not** a Rive asset and does not complete the `.riv` deliverable in #1074.

Source: `lifemate/lib/living_camp/camp_vector_avatar.dart`. Preview: from `lifemate/`, run `flutter run -t tool/avatar_motion_preview.dart`. No animation package or binary asset is needed.

| Semantic action | Behavior |
| --- | --- |
| `idle` | Subtle breathing cycle, then stable pose |
| `walk` | Gentle in-place looping step; scene position stays with Flutter |
| `drink` | Raise a small cup, then return to idle and call `onActionComplete` |
| `wellness` | Calm hand-on-heart/stretch, then return to idle and call `onActionComplete` |

The widget supports the two existing adult character families. `skinTone` recolors skin paths independently of clothing, hair and cup. `commandId` can distinguish repeated actions of the same type. `motionEnabled: false` and the platform's `disableAnimations` setting render a stable pose and complete one-shot commands without playing them.

The painter uses a 420 × 620 local coordinate space, with the feet near normalized `(0.51, 0.93)`. Flutter's `CampSceneActor` owns the world position. The avatar is decorative and adds no hit target. The existing raster asset catalog remains available as a fallback.

Limitations: idle currently settles after one breathing cycle so `pumpAndSettle` in the shell can complete. This implementation has no Rive artboard, state machine or versioned Rive inputs, and no on-device frame-time measurement has been made. Future Rive export can replace this presenter while keeping the semantic action IDs.
