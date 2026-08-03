/// Compile-time feature flags shared by WellMate and CareMate.
///
/// Paid or externally provisioned providers must stay fail-closed unless a
/// release build explicitly enables them with a reviewed `--dart-define`.
abstract final class LifeMateFeatureFlags {
  static const bool googleAuthEnabled = bool.fromEnvironment(
    'ENABLE_GOOGLE_AUTH',
    defaultValue: false,
  );
}
