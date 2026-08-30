# Releasing WellMate and CareMate

Use **Actions → Release WellMate** or **Release CareMate** → **Run workflow** on `main`. Select beta for device testing and stable only after sign-off. Each workflow builds a signed APK/AAB, checksum, immutable product-prefixed tag and GitHub Release.

Required WellMate secrets: `WELLMATE_KEYSTORE_BASE64`, `WELLMATE_STORE_PASSWORD`, `WELLMATE_KEY_ALIAS`, `WELLMATE_KEY_PASSWORD`.

Required CareMate secrets: `CAREMATE_KEYSTORE_BASE64`, `CAREMATE_STORE_PASSWORD`, `CAREMATE_KEY_ALIAS`, `CAREMATE_KEY_PASSWORD`.

Never generate replacement production keys: Android updates require the existing signing lineage.
