from pathlib import Path

path = Path('packages/lifemate_client/lib/src/experience_auth.dart')
text = path.read_text(encoding='utf-8')
old = '''            if (LifeMateFeatureFlags.googleAuthEnabled) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 15),
                child: Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'یا با روشی دیگر',
                        style: TextStyle(
                          color: Color(0xFF8C9AB1),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('auth-google'),
                onPressed: _busy ? null : _signInWithGoogle,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: brand.ink,
                  side: BorderSide(
                    color: brand.primary.withValues(alpha: 0.16),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Text(
                  'G',
                  style: TextStyle(
                    color: Color(0xFF4285F4),
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                label: const Text(
                  'ادامه با حساب گوگل',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
'''
new = '''            if (
              LifeMateFeatureFlags.googleAuthEnabled ||
              LifeMateFeatureFlags.phoneOtpEnabled
            ) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 15),
                child: Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'یا با روشی دیگر',
                        style: TextStyle(
                          color: Color(0xFF8C9AB1),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
              ),
              if (LifeMateFeatureFlags.phoneOtpEnabled)
                _PhoneOtpButton(brand: brand, enabled: !_busy),
              if (
                LifeMateFeatureFlags.phoneOtpEnabled &&
                LifeMateFeatureFlags.googleAuthEnabled
              )
                const SizedBox(height: 10),
              if (LifeMateFeatureFlags.googleAuthEnabled)
                OutlinedButton.icon(
                  key: const ValueKey('auth-google'),
                  onPressed: _busy ? null : _signInWithGoogle,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: brand.ink,
                    side: BorderSide(
                      color: brand.primary.withValues(alpha: 0.16),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Text(
                    'G',
                    style: TextStyle(
                      color: Color(0xFF4285F4),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  label: const Text(
                    'ادامه با حساب گوگل',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
'''
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected one auth-provider block, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('phone OTP experience added')
