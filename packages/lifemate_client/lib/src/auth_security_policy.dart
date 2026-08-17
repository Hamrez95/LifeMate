enum LifeMatePasswordViolation {
  tooShort,
  missingLowercase,
  missingUppercase,
  missingDigit,
  missingSymbol,
}

enum LifeMateRecoveryAuthFailure {
  rateLimited,
  unavailable,
}

/// Client-side closed-beta password requirements.
///
/// The hosted Supabase Auth provider must be configured to enforce the same or
/// stronger policy before the Auth hardening parent can close. This validator
/// intentionally applies only when a password is created or reset; existing
/// users are never blocked from sign-in by a client-side password-strength
/// check.
abstract final class LifeMatePasswordPolicy {
  static const minimumLength = 12;
  static const _symbols = r'!@#$%^&*()_+-=[]{}|;:,.<>?/~`';

  static LifeMatePasswordViolation? firstViolation(String? password) {
    final value = password ?? '';
    if (value.length < minimumLength) {
      return LifeMatePasswordViolation.tooShort;
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return LifeMatePasswordViolation.missingLowercase;
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return LifeMatePasswordViolation.missingUppercase;
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return LifeMatePasswordViolation.missingDigit;
    }
    if (!value.split('').any(_symbols.contains)) {
      return LifeMatePasswordViolation.missingSymbol;
    }
    return null;
  }

  static bool accepts(String? password) => firstViolation(password) == null;
}

/// Collapse provider-specific recovery failures into safe UI categories.
///
/// Provider messages may contain implementation details and must never be
/// rendered directly. Rate limiting is the only distinction useful to the user
/// because the corrective action is to wait before retrying.
LifeMateRecoveryAuthFailure classifyRecoveryAuthFailure(String providerMessage) {
  final message = providerMessage.toLowerCase();
  if (message.contains('rate') ||
      message.contains('limit') ||
      message.contains('too many')) {
    return LifeMateRecoveryAuthFailure.rateLimited;
  }
  return LifeMateRecoveryAuthFailure.unavailable;
}
