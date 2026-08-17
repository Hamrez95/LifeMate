from pathlib import Path


def replace_once(path: str, old: str, new: str, marker: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old in text:
        file.write_text(text.replace(old, new, 1))
        return
    if marker not in text:
        raise SystemExit(f"target not found: {path}")


replace_once(
    "packages/lifemate_client/lib/src/experience_auth.dart",
    '''                    validator: (value) => (value?.length ?? 0) >= 8
                        ? null
                        : LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'رمز عبور باید حداقل ۸ کاراکتر باشد.',
                              en: "Password must be at least 8 characters long.",
                            ),
                            en: "Password must be at least 8 characters long.",
                          ),''',
    '''                    validator: (value) => isSignUp
                        ? LifeMatePasswordPolicy.validationMessage(
                            value,
                            isPersian: LifeMateRuntimeLocale.isPersian,
                          )
                        : (value?.length ?? 0) >= 8
                        ? null
                        : LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'رمز عبور باید حداقل ۸ کاراکتر باشد.',
                              en: "Password must be at least 8 characters long.",
                            ),
                            en: "Password must be at least 8 characters long.",
                          ),''',
    "LifeMatePasswordPolicy.validationMessage",
)

replace_once(
    "packages/lifemate_client/lib/src/experience_recovery.dart",
    '''                              validator: (value) => (value?.length ?? 0) >= 8
                                  ? null
                                  : LifeMateRuntimeLocale.select(
                                      fa: LifeMateRuntimeLocale.select(
                                        fa: 'رمز باید حداقل ۸ کاراکتر باشد.',
                                        en: "Password must be at least 8 characters long.",
                                      ),
                                      en: "Password must be at least 8 characters long.",
                                    ),''',
    '''                              validator: (value) =>
                                  LifeMatePasswordPolicy.validationMessage(
                                    value,
                                    isPersian: LifeMateRuntimeLocale.isPersian,
                                  ),''',
    "LifeMatePasswordPolicy.validationMessage",
)

replace_once(
    "packages/lifemate_client/lib/src/experience_recovery.dart",
    '''    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);''',
    '''    } on AuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = safeRecoveryAuthMessage(
            error.message,
            isPersian: LifeMateRuntimeLocale.isPersian,
          ),
        );
      }''',
    "safeRecoveryAuthMessage(",
)
