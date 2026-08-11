# Android signing and build configuration

## Stable application identities

- WellMate: `com.lifemate.wellmate`
- CareMate: `com.lifemate.caremate`

Application IDs must not change after an app is distributed.

## Founder-owned release signing

WellMate and CareMate each use a separate founder-owned release keystore. The
keystores are created outside Git and must have encrypted offline backups.

Current aliases:

- WellMate: `wellmate`
- CareMate: `caremate`

The raw `.jks` files and passwords must never be committed to the repository.
Repository `.gitignore` excludes `android/key.properties`, `.jks`, `.keystore`
and `.p12` signing material.

For local release builds, an app-local `android/key.properties` file may still
be used:

```properties
storePassword=REPLACE_LOCALLY
keyPassword=REPLACE_LOCALLY
keyAlias=wellmate-or-caremate
storeFile=/absolute/path/outside-the-repository/app-release.jks
```

When `key.properties` is absent, the Gradle project retains the historical debug
fallback for local/installable development builds. CI release workflows that
produce distributable Android artifacts do **not** rely on that fallback: they
must reconstruct the founder-owned keystores from GitHub Actions Secrets and
verify the APK signing certificate before uploading artifacts.

## GitHub Actions signing secrets

The repository must contain all eight Actions secrets:

- `WELLMATE_KEYSTORE_BASE64`
- `WELLMATE_STORE_PASSWORD`
- `WELLMATE_KEY_PASSWORD`
- `WELLMATE_KEY_ALIAS`
- `CAREMATE_KEYSTORE_BASE64`
- `CAREMATE_STORE_PASSWORD`
- `CAREMATE_KEY_PASSWORD`
- `CAREMATE_KEY_ALIAS`

`tools/release/prepare-android-signing.sh` decodes the keystores only into the
ephemeral GitHub runner temp directory, validates each alias/store password and
writes temporary app-local `key.properties` files with mode `0600`.

`tools/release/verify-android-signing.sh` compares the certificate embedded in
each built APK with the certificate fingerprint of the keystore prepared for
that same build. Workflows fail closed when secrets are missing or signatures do
not match.

The main release artifact manifest records the public SHA-256 signing
certificate fingerprint for each app. This fingerprint is not a secret and can
be used to confirm that future APKs remain update-compatible.

## Update behavior on Android

Android accepts an APK as an update only when all of these remain true:

1. the package/application ID is unchanged;
2. the new APK is signed by the same signing certificate as the installed APK;
3. the new `versionCode` is greater than the installed version.

GitHub `GITHUB_RUN_NUMBER` is scoped to an individual workflow, so it is not a
safe global Android versionCode when several workflows can build APKs. To keep
WellMate and CareMate updateable regardless of whether an APK came from the
main-final, internal-beta, or manual checkpoint workflow, Android Gradle uses a
single CI-wide monotonic scale: UTC seconds elapsed since
`2025-01-01T00:00:00Z`. This value is applied only on GitHub Actions; local
builds continue to use Flutter's configured versionCode.

Older LifeMate test APKs were sometimes produced with ephemeral/debug signing.
After stable founder-owned signing is enabled, those legacy APKs may require one
final uninstall/reinstall. Once a founder-signed WellMate/CareMate APK is
installed, subsequent founder-signed CI builds can be installed as updates
without removing the previous app or its local state.

The release keystores are long-lived project assets. Losing them can prevent
future direct APK updates. Keep at least one encrypted offline backup and store
the passwords in a trusted password manager.

## Build-time public configuration

Android beta builds require these GitHub Actions repository variables:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `LIFEMATE_API_BASE_URL`

The beta workflow can fall back to the project's public Supabase URL,
publishable key, and authenticated `lifemate-api` Edge Function. The resulting
beta APKs use the real database-backed MVP flow. A repository variable may
override the API URL for another environment.

The API base URL must be HTTPS. Service-role keys, database credentials, private
signing files, passwords, and refresh/access tokens must never be passed as Dart
defines or committed.
