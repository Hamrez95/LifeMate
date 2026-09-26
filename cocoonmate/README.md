# CocoonMate standalone host

This Flutter application is a thin standalone host for the reusable CocoonMate module in `packages/cocoonmate_module`.

## Local development

From this directory, run `flutter pub get`, then `flutter test`. Android platform files are committed for local development; machine-specific SDK settings such as `android/local.properties` remain local.

The host uses the shared LifeMate API client and does not own a separate authentication or profile store.