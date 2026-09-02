/// UI privacy lock policy kept deliberately separate from Supabase Auth.
///
/// Implementations may use biometrics or the device credential to unlock the
/// LifeMate UI, but must never gate Supabase refresh-token access or background
/// reminder/sync work behind an interactive biometric prompt.
class LifeMateAppLockPolicy {
  LifeMateAppLockPolicy({
    required this.enabled,
    this.relockAfter = const Duration(minutes: 5),
  }) : assert(!relockAfter.isNegative);

  const LifeMateAppLockPolicy.disabled()
    : enabled = false,
      relockAfter = Duration.zero;

  final bool enabled;
  final Duration relockAfter;

  bool requiresUnlock({
    required DateTime now,
    DateTime? lastUnlockedAt,
    bool coldStart = false,
  }) {
    if (!enabled) return false;
    if (coldStart || lastUnlockedAt == null) return true;
    return now.difference(lastUnlockedAt) >= relockAfter;
  }
}

/// Platform authentication boundary for a future Face ID / fingerprint /
/// device-credential implementation.
///
/// Keeping this interface independent from Supabase makes it impossible for a
/// biometric prompt to become a prerequisite for token refresh or background
/// API work by accident.
abstract interface class LifeMateAppLockAuthenticator {
  Future<bool> isAvailable();

  Future<bool> authenticate({required String localizedReason});
}
