import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

class LocaleProvider extends ChangeNotifier {
  LocaleProvider() {
    LifeMateRuntimeLocale.setLanguageCode(_locale.languageCode);
  }

  Locale _locale = const Locale('fa');

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    if (!['en', 'fa'].contains(locale.languageCode)) return;
    if (_locale.languageCode == locale.languageCode) return;
    _locale = Locale(locale.languageCode);
    LifeMateRuntimeLocale.setLanguageCode(_locale.languageCode);
    notifyListeners();
  }
}
