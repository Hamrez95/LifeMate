# CocoonMate standalone host

This Flutter application is a thin standalone host for the reusable CocoonMate module in `packages/cocoonmate_module`.

## Local development

From this directory, run `flutter pub get`, then `flutter test`.

### Run as a standalone web app

The CocoonMate host supports both Android and web. From this directory, run:

```sh
flutter run -d chrome --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=your-public-publishable-key --dart-define=LIFEMATE_API_BASE_URL=https://your-api.example.com
```

Use the same public runtime values configured for the LifeMate shell. Never put
service-role credentials or other secrets in browser builds. For a release
bundle, use `flutter build web --release` with those same `--dart-define`
values. Android platform files remain committed; machine-specific SDK settings
such as `android/local.properties` remain local.

The host uses the shared LifeMate API client and does not own a separate authentication or profile store.
