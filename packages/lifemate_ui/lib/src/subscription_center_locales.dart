import 'package:flutter/widgets.dart';

import 'localization.dart';

const Map<String, String> lifeMateSubscriptionCenterEnglishMessages =
    <String, String>{
      'subscription.gift.dialog.title': 'Receive gift',
      'subscription.gift.dialog.codeLabel': 'Gift code',
      'subscription.gift.dialog.codeHint': 'Enter the code you received',
      'subscription.action.cancel': 'Cancel',
      'subscription.gift.dialog.claim': 'Claim',
      'subscription.convert.dialog.title': 'Convert to CocoonMate',
      'subscription.convert.dialog.message':
          'Your remaining subscription value will be transferred automatically. After conversion, returning to Period requires a new subscription. Your calendar history will be preserved.',
      'subscription.convert.dialog.confirm': 'Convert',
      'subscription.updated': 'Subscription status updated.',
      'subscription.title': 'Subscriptions',
      'subscription.refresh': 'Refresh',
      'subscription.trial.title': 'Calendar trial',
      'subscription.trial.message':
          'The trial duration is set by the server and does not reset after reinstalling the app.',
      'subscription.trial.start': 'Start trial',
      'subscription.convert.card.title': 'Convert to CocoonMate',
      'subscription.convert.card.message':
          'The actual remaining value is transferred while health data and history stay preserved.',
      'subscription.convert.card.cta': 'Review and convert',
      'subscription.offers.title': 'Active offers',
      'subscription.offer.fallbackTitle': 'Premium subscription',
      'subscription.price.loading': 'Loading price',
      'subscription.access.title': 'Access status',
      'subscription.access.empty': 'You have no active premium access.',
      'subscription.freeLimits.title': 'Free plan limits',
      'subscription.freeLimits.empty':
          'Account limits could not be loaded from the server.',
      'subscription.gift.card.title': 'Receive a gift subscription',
      'subscription.gift.card.message':
          'A gift only activates a subscription and does not change health information or access permissions.',
      'subscription.gift.card.cta': 'Enter gift code',
      'subscription.serverPricing.note':
          'Prices, discounts, limits, and trial duration are loaded from your server account.',
      'subscription.payment.notice':
          'Available payment methods will be shown when you complete the purchase.',
      'subscription.hero.title': 'A subscription that fits your needs',
      'subscription.hero.subtitle':
          'Manage access and offers securely and transparently.',
      'subscription.entitlement.fallback': 'Subscription',
      'subscription.status.active': 'Active',
      'subscription.status.inactive': 'Inactive',
      'subscription.policy.fallback': 'Usage limit',
      'subscription.load.failed': 'Subscription status could not be loaded.',
      'subscription.retry': 'Try again',
    };

const Map<String, String> lifeMateSubscriptionCenterPersianMessages =
    <String, String>{
      'subscription.gift.dialog.title': 'دریافت هدیه',
      'subscription.gift.dialog.codeLabel': 'کد هدیه',
      'subscription.gift.dialog.codeHint': 'کد دریافت‌شده را وارد کنید',
      'subscription.action.cancel': 'انصراف',
      'subscription.gift.dialog.claim': 'دریافت',
      'subscription.convert.dialog.title': 'تبدیل به CocoonMate',
      'subscription.convert.dialog.message':
          'ارزش باقی‌ماندهٔ اشتراک شما به‌صورت خودکار منتقل می‌شود. پس از تبدیل، بازگشت به Period نیازمند اشتراک جدید است. تاریخچهٔ تقویم شما حفظ می‌شود.',
      'subscription.convert.dialog.confirm': 'تبدیل',
      'subscription.updated': 'وضعیت اشتراک به‌روزرسانی شد.',
      'subscription.title': 'اشتراک‌ها',
      'subscription.refresh': 'تازه‌سازی',
      'subscription.trial.title': 'دورهٔ آزمایشی تقویم',
      'subscription.trial.message':
          'مدت دوره از سرور تعیین می‌شود و با نصب دوباره بازنشانی نمی‌شود.',
      'subscription.trial.start': 'شروع دورهٔ آزمایشی',
      'subscription.convert.card.title': 'تبدیل به CocoonMate',
      'subscription.convert.card.message':
          'ارزش واقعیِ باقی‌مانده منتقل می‌شود؛ اطلاعات سلامت و تاریخچه محفوظ می‌ماند.',
      'subscription.convert.card.cta': 'بررسی و تبدیل',
      'subscription.offers.title': 'پیشنهادهای فعال',
      'subscription.offer.fallbackTitle': 'اشتراک ویژه',
      'subscription.price.loading': 'قیمت در حال دریافت',
      'subscription.access.title': 'وضعیت دسترسی',
      'subscription.access.empty': 'دسترسی ویژهٔ فعالی ندارید.',
      'subscription.freeLimits.title': 'سقف نسخهٔ رایگان',
      'subscription.freeLimits.empty': 'سقف‌های حساب از سرور دریافت نشد.',
      'subscription.gift.card.title': 'دریافت اشتراک هدیه',
      'subscription.gift.card.message':
          'هدیه فقط اشتراک را فعال می‌کند و هیچ دسترسی یا اطلاعات سلامتی را تغییر نمی‌دهد.',
      'subscription.gift.card.cta': 'وارد کردن کد هدیه',
      'subscription.serverPricing.note':
          'قیمت، تخفیف، سقف‌ها و مدت آزمایشی از حساب شما در سرور دریافت می‌شوند.',
      'subscription.payment.notice':
          'روش‌های پرداخت فعال هنگام تکمیل خرید نمایش داده می‌شوند.',
      'subscription.hero.title': 'اشتراک متناسب با نیاز شما',
      'subscription.hero.subtitle':
          'دسترسی‌ها و پیشنهادها را امن و شفاف مدیریت کنید.',
      'subscription.entitlement.fallback': 'اشتراک',
      'subscription.status.active': 'فعال',
      'subscription.status.inactive': 'غیرفعال',
      'subscription.policy.fallback': 'سقف استفاده',
      'subscription.load.failed': 'وضعیت اشتراک دریافت نشد.',
      'subscription.retry': 'تلاش دوباره',
    };

const LifeMateMessageCatalog lifeMateSubscriptionCenterMessages =
    LifeMateMessageCatalog(<String, Map<String, String>>{
      'en': lifeMateSubscriptionCenterEnglishMessages,
      'fa': lifeMateSubscriptionCenterPersianMessages,
    });

extension LifeMateSubscriptionCenterLocalization on BuildContext {
  String subscriptionTr(
    String key, {
    Map<String, Object?> params = const <String, Object?>{},
  }) => lifeMateSubscriptionCenterMessages.text(
    key,
    locale: lifeMateLocale.locale,
    params: params,
  );
}
