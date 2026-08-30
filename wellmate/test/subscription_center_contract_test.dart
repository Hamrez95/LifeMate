import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subscription centre is server driven and contains no local commercial price', () {
    final source = File(
      'lib/screens/profile/subscription_center_screen.dart',
    ).readAsStringSync();

    expect(source, contains('getSubscriptionSnapshot()'));
    expect(source, contains('startPeriodTrial('));
    expect(source, contains('claimSubscriptionGift('));
    expect(source, contains('convertPeriodToCocoon('));
    expect(source, contains('LifeMateOfferCard('));
    expect(source, contains('قیمت، تخفیف، سقف‌ها و مدت آزمایشی از حساب شما در سرور دریافت می‌شوند.'));
    expect(source, isNot(contains('50000')));
    expect(source, isNot(contains('commercial entitlement')));
  });

  test('gift and Period conversion preserve their privacy boundaries', () {
    final source = File(
      'lib/screens/profile/subscription_center_screen.dart',
    ).readAsStringSync();

    expect(source, contains('هدیه فقط اشتراک را فعال می‌کند'));
    expect(source, contains('هیچ دسترسی یا اطلاعات سلامتی را تغییر نمی‌دهد'));
    expect(source, contains('تاریخچهٔ تقویم شما حفظ می‌شود.'));
    expect(source, contains('بازگشت به Period نیازمند اشتراک جدید است.'));
  });

  test('existing profile and calendar point to the new shared centre', () {
    final profile = File('lib/screens/profile/profile_screen.dart').readAsStringSync();
    final calendar =
        File('lib/screens/women_calendar/women_calendar_screen.dart').readAsStringSync();

    expect(profile, contains('LifeMateSubscriptionCenterScreen()'));
    expect(calendar, contains('LifeMateSubscriptionCenterScreen(focusPeriod: true)'));
    expect(calendar, contains('women_calendar_month_card.dart'));
  });
}
