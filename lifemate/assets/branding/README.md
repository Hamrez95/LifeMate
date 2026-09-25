# LifeMate shell branding

- `lifemate_logo.png` is the transparent LifeMate mark supplied in this task and
  prepared for the shell UI, launch reveal, and Android launcher icon.
- `lifemate_launch_city.jpg` is the supplied dusk village image without the
  baked-in logo. The shell animates the mark upward over this image in Flutter.
- Android launcher resources are generated from the same logo with
  `dart run flutter_launcher_icons` after `tools/release/prepare-lifemate-android.sh`.
- The launch reveal honors Reduce Motion and uses a short animation instead of
  a video asset.

The Living Camp uses the existing day and dusk terrain images and blends them
from an astronomical sunrise/sunset window. Without a saved coarse location it
uses the local 06:00–20:00 fallback. Twilight takes 60 minutes at each edge.
Zone art remains independently rendered and interactive; its extra window glow
fades out during the day and returns at night. The source zone paintings define
the underlying window pixels.

Authentication for the parent shell uses `LifeMateAuth` and the shared
authenticated API client. SMS OTP remains fail-closed unless the release
explicitly enables the existing `ENABLE_PHONE_OTP` flag and has a working
server-side delivery provider. Product modules mounted in the registry receive
the same authenticated API client and must not create another auth gate. The
current WellMate/CareMate registry entries are still unavailable until their
screens are adapted for embedding; their standalone apps have not been
converted by this shell change.
