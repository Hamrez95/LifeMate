import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/core/widgets/medication_home_widget_service.dart';

class LocaleProvider extends ChangeNotifier {
  LocaleProvider() {
    LifeMateRuntimeLocale.setLanguageCode(_locale.languageCode);
    unawaited(MedicationHomeWidgetService.updateLocale(_locale.languageCode));
  }

  Locale _locale = const Locale('fa');

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    if (!['en', 'fa'].contains(locale.languageCode)) return;
    if (_locale.languageCode == locale.languageCode) return;
    _locale = Locale(locale.languageCode);
    LifeMateRuntimeLocale.setLanguageCode(_locale.languageCode);
    unawaited(MedicationHomeWidgetService.updateLocale(_locale.languageCode));
    notifyListeners();
  }
}
