import 'runtime_locale.dart';

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
/// users are never blocked from sign-in by a stronger client-side requirement.
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

  static String? validationMessage(
    String? password, {
    required bool isPersian,
  }) {
    assert(isPersian == LifeMateRuntimeLocale.isPersian);
    final violation = firstViolation(password);
    if (violation == null) return null;
    return switch (violation) {
      LifeMatePasswordViolation.tooShort => LifeMateRuntimeLocale.select(
          fa: 'رمز عبور باید حداقل ۱۲ کاراکتر باشد.',
          en: 'Password must be at least 12 characters long.',
        ),
      LifeMatePasswordViolation.missingLowercase => LifeMateRuntimeLocale.select(
          fa: 'رمز عبور باید حداقل یک حرف کوچک انگلیسی داشته باشد.',
          en: 'Password must contain at least one lowercase letter.',
        ),
      LifeMatePasswordViolation.missingUppercase => LifeMateRuntimeLocale.select(
          fa: 'رمز عبور باید حداقل یک حرف بزرگ انگلیسی داشته باشد.',
          en: 'Password must contain at least one uppercase letter.',
        ),
      LifeMatePasswordViolation.missingDigit => LifeMateRuntimeLocale.select(
          fa: 'رمز عبور باید حداقل یک عدد داشته باشد.',
          en: 'Password must contain at least one number.',
        ),
      LifeMatePasswordViolation.missingSymbol => LifeMateRuntimeLocale.select(
          fa: 'رمز عبور باید حداقل یک نماد مانند ! یا @ داشته باشد.',
          en: 'Password must contain at least one symbol such as ! or @.',
        ),
    };
  }
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

String safeRecoveryAuthMessage(
  String providerMessage, {
  required bool isPersian,
}) {
  assert(isPersian == LifeMateRuntimeLocale.isPersian);
  return switch (classifyRecoveryAuthFailure(providerMessage)) {
    LifeMateRecoveryAuthFailure.rateLimited => LifeMateRuntimeLocale.select(
        fa: 'تعداد درخواست‌ها زیاد بوده است؛ کمی بعد دوباره تلاش کنید.',
        en: 'Too many requests were made. Try again later.',
      ),
    LifeMateRecoveryAuthFailure.unavailable => LifeMateRuntimeLocale.select(
        fa: 'تغییر رمز عبور انجام نشد. کمی بعد دوباره تلاش کنید.',
        en: 'Password change could not be completed. Try again later.',
      ),
  };
}
