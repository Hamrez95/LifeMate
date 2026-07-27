# Android signing and build configuration

## Stable application identities

- WellMate: `com.lifemate.wellmate`
- CareMate: `com.lifemate.caremate`
- Beta version: `0.7.0-beta.1` (`versionCode` 7)

Application IDs must not change after an app is distributed.

## Founder-owned release signing

Create one release keystore outside Git and keep an encrypted offline backup. Put
an app-local `android/key.properties` file in each Flutter project:

```properties
storePassword=REPLACE_LOCALLY
keyPassword=REPLACE_LOCALLY
keyAlias=lifemate
storeFile=/absolute/path/outside-the-repository/lifemate-upload.jks
```

`key.properties`, `.jks`, and `.keystore` files are ignored by Git. When the
properties file is absent, Gradle signs the beta artifact with Android's debug
key so it can be installed on test devices. That fallback is never suitable for
Play Store distribution; a store build must provide the founder-owned keystore.

## Build-time public configuration

Android beta builds require these GitHub Actions repository variables:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `LIFEMATE_API_BASE_URL`

The API base URL must be HTTPS. Service-role keys, database credentials, private
signing files, passwords, and refresh/access tokens must never be passed as Dart
defines or committed.
