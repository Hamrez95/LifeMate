import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_ui/src/subscription_center_locales.dart';

void main() {
  test('server entitlement names are localized for the selected language', () {
    expect(
      lifeMateSubscriptionServerLabel(
        'Period Calendar',
        locale: const Locale('fa'),
        policy: false,
        fallback: 'اشتراک',
      ),
      'تقویم چرخه',
    );
    expect(
      lifeMateSubscriptionServerLabel(
        'WellMate + CareMate',
        locale: const Locale('en'),
        policy: false,
        fallback: 'Subscription',
      ),
      'WellMate and CareMate',
    );
  });

  test('known and unknown policy keys never leak into the UI', () {
    expect(
      lifeMateSubscriptionServerLabel(
        'trial.days',
        locale: const Locale('fa'),
        policy: true,
        fallback: 'سقف استفاده',
      ),
      'مدت دورهٔ آزمایشی',
    );
    expect(
      lifeMateSubscriptionServerLabel(
        'future.policy_key',
        locale: const Locale('fa'),
        policy: true,
        fallback: 'سقف استفاده',
      ),
      'سقف استفاده',
    );
  });
}
