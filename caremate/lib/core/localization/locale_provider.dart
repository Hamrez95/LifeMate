import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

class LocaleProvider extends ChangeNotifier {
  LocaleProvider({Locale initialLocale = const Locale('fa')})
      : _locale = initialLocale.languageCode == 'en'
            ? const Locale('en')
            : const Locale('fa') {
    LifeMateRuntimeLocale.setLanguageCode(_locale.languageCode);
  }

  Locale _locale;

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    if (!['en', 'fa'].contains(locale.languageCode)) return;
    if (_locale.languageCode == locale.languageCode) return;
    _locale = Locale(locale.languageCode);
    LifeMateRuntimeLocale.setLanguageCode(_locale.languageCode);
    notifyListeners();
  }
}
