import 'package:flutter/widgets.dart';

import 'localization.dart';

const Map<String, String> lifeMateDemographicsEnglishMessages =
    <String, String>{
  'demographics.loadFailed':
      'Initial profile information is unavailable. Try again.',
  'demographics.selfDescriptionRequired':
      'Please enter a short gender description.',
  'demographics.saveFailed':
      'Could not save. Check your connection and try again.',
  'demographics.preparingTitle': 'Preparing your personal profile',
  'demographics.preparingDescription': 'This only takes a moment.',
  'demographics.unavailableTitle': 'Profile information is unavailable',
  'demographics.basicProfile': 'Basic profile',
  'demographics.saveContinue': 'Save and continue',
  'demographics.question': 'How do you describe your gender?',
  'demographics.questionDescription':
      'Used for appropriate personalization. You can always choose “Prefer not to say”.',
  'demographics.shortDescription': 'Short description',
  'demographics.sexAtBirthDescription':
      'Used only for health experiences that genuinely need it. It is not used as a substitute for gender in messaging.',
  'demographics.editorLoadFailed': 'Could not load profile information.',
  'demographics.editorTitle': 'Gender & demographics',
  'demographics.gender': 'Gender',
  'demographics.sexAtBirth': 'Sex assigned at birth',
  'demographics.edit': 'Edit',
  'demographics.editTitle': 'Edit demographics',
  'demographics.save': 'Save',
  'demographics.saveShortFailed': 'Could not save',
  'demographics.woman': 'Woman',
  'demographics.man': 'Man',
  'demographics.nonBinary': 'Non-binary',
  'demographics.selfDescribe': 'Self-describe',
  'demographics.selfDescribed': 'Self-described',
  'demographics.preferNotToSay': 'Prefer not to say',
  'demographics.notCollected': 'Not collected',
  'demographics.female': 'Female',
  'demographics.male': 'Male',
  'demographics.intersex': 'Intersex',
};

const Map<String, String> lifeMateDemographicsPersianMessages =
    <String, String>{
  'demographics.loadFailed':
      'اطلاعات اولیه در دسترس نیست. دوباره تلاش کن.',
  'demographics.selfDescriptionRequired':
      'لطفاً توضیح کوتاهی برای جنسیت وارد کن.',
  'demographics.saveFailed':
      'ذخیره انجام نشد. اتصال را بررسی و دوباره تلاش کن.',
  'demographics.preparingTitle': 'پروفایل شخصی تو را آماده می‌کنیم',
  'demographics.preparingDescription': 'چند لحظه صبر کن.',
  'demographics.unavailableTitle': 'اطلاعات پروفایل در دسترس نیست',
  'demographics.basicProfile': 'اطلاعات پایه',
  'demographics.saveContinue': 'ذخیره و ادامه',
  'demographics.question': 'چطور خودت را معرفی می‌کنی؟',
  'demographics.questionDescription':
      'برای شخصی‌سازی پیام‌ها استفاده می‌شود. همیشه می‌توانی «ترجیح می‌دهم نگویم» را انتخاب کنی.',
  'demographics.shortDescription': 'توضیح کوتاه',
  'demographics.sexAtBirthDescription':
      'این مورد فقط برای تجربه‌های سلامت که واقعاً به آن نیاز دارند استفاده می‌شود و برای جنسیت پیام‌رسانی جایگزین نمی‌شود.',
  'demographics.editorLoadFailed': 'بارگذاری اطلاعات انجام نشد.',
  'demographics.editorTitle': 'جنسیت و اطلاعات پایه',
  'demographics.gender': 'جنسیت',
  'demographics.sexAtBirth': 'جنس ثبت‌شده هنگام تولد',
  'demographics.edit': 'ویرایش',
  'demographics.editTitle': 'ویرایش اطلاعات پایه',
  'demographics.save': 'ذخیره',
  'demographics.saveShortFailed': 'ذخیره انجام نشد',
  'demographics.woman': 'زن',
  'demographics.man': 'مرد',
  'demographics.nonBinary': 'نان‌باینری',
  'demographics.selfDescribe': 'خودم توضیح می‌دهم',
  'demographics.selfDescribed': 'خودتوصیف',
  'demographics.preferNotToSay': 'ترجیح می‌دهم نگویم',
  'demographics.notCollected': 'ثبت نشده',
  'demographics.female': 'مونث',
  'demographics.male': 'مذکر',
  'demographics.intersex': 'اینترسکس',
};

const Set<String> lifeMateDemographicsRequiredKeys = <String>{
  'demographics.loadFailed',
  'demographics.selfDescriptionRequired',
  'demographics.saveFailed',
  'demographics.preparingTitle',
  'demographics.preparingDescription',
  'demographics.unavailableTitle',
  'demographics.basicProfile',
  'demographics.saveContinue',
  'demographics.question',
  'demographics.questionDescription',
  'demographics.shortDescription',
  'demographics.sexAtBirthDescription',
  'demographics.editorLoadFailed',
  'demographics.editorTitle',
  'demographics.gender',
  'demographics.sexAtBirth',
  'demographics.edit',
  'demographics.editTitle',
  'demographics.save',
  'demographics.saveShortFailed',
  'demographics.woman',
  'demographics.man',
  'demographics.nonBinary',
  'demographics.selfDescribe',
  'demographics.selfDescribed',
  'demographics.preferNotToSay',
  'demographics.notCollected',
  'demographics.female',
  'demographics.male',
  'demographics.intersex',
};

const LifeMateMessageCatalog lifeMateDemographicsMessages =
    LifeMateMessageCatalog(<String, Map<String, String>>{
  'en': lifeMateDemographicsEnglishMessages,
  'fa': lifeMateDemographicsPersianMessages,
});

extension LifeMateDemographicsLocalizationContext on BuildContext {
  String demographicsTr(
    String key, {
    Map<String, Object?> params = const <String, Object?>{},
  }) =>
      lifeMateDemographicsMessages.text(
        key,
        locale: lifeMateLocale.locale,
        params: params,
      );
}
