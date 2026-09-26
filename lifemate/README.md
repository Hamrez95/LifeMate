# LifeMate shell

Flutter parent application for the LifeMate shell and Living Camp. The shell
owns sign-in, the shared profile, and navigation into embedded product modules.

## Local development

From this directory, run `flutter pub get`, `flutter analyze`, and
`flutter test`. Android host files are generated and normalized by
`../tools/release/prepare-lifemate-android.sh` before Android builds.

The product modules remain in the repository's `wellmate/`, `caremate/`, and
`cocoonmate/` directories and are mounted through `lib/modules/`.
