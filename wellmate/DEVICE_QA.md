# LifeMate Android Device QA

The old version-specific WellMate candidate checklist has been retired.

The canonical physical-device gate for **both WellMate and CareMate** is now:

`docs/release/FOUNDATION_DEVICE_QA.md`

Use that checklist only against the exact release-signed artifacts produced from the exact `main` commit under review. Record APK SHA-256, signing certificate SHA-256, APK-derived Android SDK metadata, deployed API SHA and representative physical-device evidence.

No checkbox in the canonical checklist is considered passed merely because CI, emulator tests, local PostgreSQL smoke or a previous internal candidate succeeded.

GitHub issue #170 remains the canonical Foundation Closure/release gate.
