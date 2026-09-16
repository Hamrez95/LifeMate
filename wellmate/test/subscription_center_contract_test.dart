import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

void main() {
  test(
    'subscription centre is server driven and contains no local commercial price',
    () {
      final source = File(
        'lib/screens/profile/subscription_center_screen.dart',
      ).readAsStringSync();

      expect(source, contains('getSubscriptionSnapshot()'));
      expect(source, contains('startPeriodTrial('));
      expect(source, contains('claimSubscriptionGift('));
      expect(source, contains('convertPeriodToCocoon('));
      expect(source, contains('LifeMateOfferCard('));
      expect(
        lifeMateSubscriptionCenterPersianMessages[
          'subscription.serverPricing.note'
        ],
        'قیمت، تخفیف، سقف‌ها و مدت آزمایشی از حساب شما در سرور دریافت می‌شوند.',
      );
      expect(
        source,
        contains("subscriptionTr('subscription.serverPricing.note')"),
      );
      expect(source, isNot(contains('50000')));
      expect(source, isNot(contains('commercial entitlement')));
    },
  );

  test('gift and Period conversion preserve their privacy boundaries', () {
    final source = File(
      'lib/screens/profile/subscription_center_screen.dart',
    ).readAsStringSync();
    final gift = lifeMateSubscriptionCenterPersianMessages[
      'subscription.gift.card.message'
    ];
    final conversion = lifeMateSubscriptionCenterPersianMessages[
      'subscription.convert.dialog.message'
    ];

    expect(gift, contains('هدیه فقط اشتراک را فعال می‌کند'));
    expect(gift, contains('هیچ دسترسی یا اطلاعات سلامتی را تغییر نمی‌دهد'));
    expect(conversion, contains('تاریخچهٔ تقویم شما حفظ می‌شود.'));
    expect(conversion, contains('بازگشت به Period نیازمند اشتراک جدید است.'));
    expect(source, contains("subscriptionTr('subscription.gift.card.message')"));
    expect(source, contains("'subscription.convert.dialog.message'"));
  });

  test('subscription catalogue is complete in Persian and English', () {
    expect(
      lifeMateSubscriptionCenterPersianMessages.keys,
      unorderedEquals(lifeMateSubscriptionCenterEnglishMessages.keys),
    );
    for (final key in lifeMateSubscriptionCenterPersianMessages.keys) {
      expect(lifeMateSubscriptionCenterPersianMessages[key]?.trim(), isNotEmpty);
      expect(lifeMateSubscriptionCenterEnglishMessages[key]?.trim(), isNotEmpty);
    }
  });

  test('existing profile and calendar point to the new shared centre', () {
    final profile = File(
      'lib/screens/profile/profile_screen.dart',
    ).readAsStringSync();
    final calendar = File(
      'lib/screens/women_calendar/women_calendar_screen.dart',
    ).readAsStringSync();

    expect(profile, contains('LifeMateSubscriptionCenterScreen()'));
    expect(
      calendar,
      contains('LifeMateSubscriptionCenterScreen(focusPeriod: true)'),
    );
    expect(calendar, contains('women_calendar_month_card.dart'));
  });
}
