import 'package:flutter/widgets.dart';

import 'localization.dart';

const Map<String, String> lifeMateLegalPrivacyEnglishMessages =
    <String, String>{
  'legal.registration.loadFailed':
      'Terms and privacy information could not be loaded. Try again.',
  'legal.registration.confirmRequired':
      'Confirm each required Terms and Privacy document to continue.',
  'legal.registration.versionChanged':
      'The legal version changed. Review and accept the current version.',
  'legal.registration.saveConnectionFailed':
      'Acceptance could not be saved. Check your connection and retry.',
  'legal.registration.saveFailed':
      'Acceptance could not be saved. Try again.',
  'legal.registration.checkingTitle': 'Checking the current legal version',
  'legal.registration.checkingDescription': 'This only takes a moment.',
  'legal.registration.unavailableTitle': 'Current terms are unavailable',
  'legal.registration.title': 'Terms & Privacy',
  'legal.registration.finalStep': 'Final step',
  'legal.registration.acceptContinue': 'Accept and continue',
  'legal.registration.reviewTitle':
      'Review and accept the current version yourself',
  'legal.registration.reviewDescription':
      'Nothing is pre-checked. Optional marketing and research preferences are separate.',
  'legal.registration.documentVersion': 'Version {version}',
  'legal.registration.copyLink': 'Copy link',
  'privacy.preferences.loadFailed':
      'Privacy preferences could not be loaded.',
  'privacy.preferences.changeSaveFailed':
      'The change was not saved. Try again.',
  'privacy.preferences.title': 'Privacy & Communications',
  'privacy.preferences.description':
      'These choices are optional and can be turned off anytime. Security, transactional and care-reminder communications are separate from marketing.',
  'privacy.preferences.essentialNotice':
      'Turning off offers and marketing does not disable essential account, security or care-reminder messages.',
  'privacy.preferences.promotionalSms': 'Offers by SMS',
  'privacy.preferences.promotionalPush': 'Offers by push',
  'privacy.preferences.promotionalEmail': 'Offers by email',
  'privacy.preferences.research': 'Research participation',
  'privacy.preferences.personalization': 'Optional personalization',
  'privacy.preferences.versionedDescription': '{description} · {version}',
};

const Map<String, String> lifeMateLegalPrivacyPersianMessages =
    <String, String>{
  'legal.registration.loadFailed':
      'شرایط و حریم خصوصی دریافت نشد. دوباره تلاش کن.',
  'legal.registration.confirmRequired':
      'برای ادامه، شرایط و اطلاعیه حریم خصوصی الزامی را خودت تأیید کن.',
  'legal.registration.versionChanged':
      'نسخه شرایط تغییر کرده است. نسخه جدید را بررسی و تأیید کن.',
  'legal.registration.saveConnectionFailed':
      'تأیید ذخیره نشد. اتصال را بررسی و دوباره تلاش کن.',
  'legal.registration.saveFailed': 'تأیید ذخیره نشد. دوباره تلاش کن.',
  'legal.registration.checkingTitle': 'نسخه فعلی شرایط را بررسی می‌کنیم',
  'legal.registration.checkingDescription': 'چند لحظه صبر کن.',
  'legal.registration.unavailableTitle': 'شرایط فعلی در دسترس نیست',
  'legal.registration.title': 'شرایط و حریم خصوصی',
  'legal.registration.finalStep': 'مرحله نهایی',
  'legal.registration.acceptContinue': 'تأیید و ادامه',
  'legal.registration.reviewTitle':
      'قبل از ورود، نسخه فعلی را خودت تأیید کن',
  'legal.registration.reviewDescription':
      'هیچ گزینه‌ای از قبل فعال نیست. تنظیمات اختیاری تبلیغات و پژوهش جداگانه‌اند.',
  'legal.registration.documentVersion': 'نسخه {version}',
  'legal.registration.copyLink': 'کپی لینک',
  'privacy.preferences.loadFailed': 'تنظیمات حریم خصوصی دریافت نشد.',
  'privacy.preferences.changeSaveFailed':
      'تغییر ذخیره نشد؛ دوباره تلاش کن.',
  'privacy.preferences.title': 'حریم خصوصی و ارتباطات',
  'privacy.preferences.description':
      'این گزینه‌ها اختیاری‌اند و هر زمان می‌توانی خاموششان کنی. اعلان‌های امنیتی، تراکنشی و یادآوری‌های مراقبتی جدا از تبلیغات هستند.',
  'privacy.preferences.essentialNotice':
      'خاموش‌کردن پیشنهادها و تبلیغات روی پیام‌های ضروری حساب، امنیت یا یادآوری‌های مراقبتی اثر نمی‌گذارد.',
  'privacy.preferences.promotionalSms': 'پیشنهادها با پیامک',
  'privacy.preferences.promotionalPush': 'پیشنهادها با اعلان',
  'privacy.preferences.promotionalEmail': 'پیشنهادها با ایمیل',
  'privacy.preferences.research': 'مشارکت در پژوهش',
  'privacy.preferences.personalization': 'شخصی‌سازی اختیاری',
  'privacy.preferences.versionedDescription':
      '{description} · نسخه {version}',
};

const Set<String> lifeMateLegalPrivacyRequiredKeys = <String>{
  'legal.registration.loadFailed',
  'legal.registration.confirmRequired',
  'legal.registration.versionChanged',
  'legal.registration.saveConnectionFailed',
  'legal.registration.saveFailed',
  'legal.registration.checkingTitle',
  'legal.registration.checkingDescription',
  'legal.registration.unavailableTitle',
  'legal.registration.title',
  'legal.registration.finalStep',
  'legal.registration.acceptContinue',
  'legal.registration.reviewTitle',
  'legal.registration.reviewDescription',
  'legal.registration.documentVersion',
  'legal.registration.copyLink',
  'privacy.preferences.loadFailed',
  'privacy.preferences.changeSaveFailed',
  'privacy.preferences.title',
  'privacy.preferences.description',
  'privacy.preferences.essentialNotice',
  'privacy.preferences.promotionalSms',
  'privacy.preferences.promotionalPush',
  'privacy.preferences.promotionalEmail',
  'privacy.preferences.research',
  'privacy.preferences.personalization',
  'privacy.preferences.versionedDescription',
};

const LifeMateMessageCatalog lifeMateLegalPrivacyMessages =
    LifeMateMessageCatalog(<String, Map<String, String>>{
  'en': lifeMateLegalPrivacyEnglishMessages,
  'fa': lifeMateLegalPrivacyPersianMessages,
});

extension LifeMateLegalPrivacyLocalizationContext on BuildContext {
  String legalPrivacyTr(
    String key, {
    Map<String, Object?> params = const <String, Object?>{},
  }) =>
      lifeMateLegalPrivacyMessages.text(
        key,
        locale: lifeMateLocale.locale,
        params: params,
      );
}
