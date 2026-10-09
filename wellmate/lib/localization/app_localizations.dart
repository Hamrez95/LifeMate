import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

class AppLocalizations {
  final Locale locale;
  final String? packageName;
  late Map<String, String> _localizedStrings;

  AppLocalizations(this.locale, {this.packageName});

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  Future<bool> load() async {
    final assetPath = 'lib/localization/${locale.languageCode}.json';
    late final String jsonString;
    final package = packageName;
    if (package == null) {
      try {
        jsonString = await rootBundle.loadString(assetPath);
      } on FlutterError {
        jsonString = await rootBundle.loadString(
          'packages/wellmate/$assetPath',
        );
      }
    } else {
      try {
        jsonString =
            await rootBundle.loadString('packages/$package/$assetPath');
      } on FlutterError {
        jsonString = await rootBundle.loadString(assetPath);
      }
    }
    Map<String, dynamic> jsonMap = json.decode(jsonString);
    _localizedStrings = jsonMap.map(
      (key, value) => MapEntry(key, value.toString()),
    );
    return true;
  }

  String operator [](String key) => _localizedStrings[key] ?? key;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static LocalizationsDelegate<AppLocalizations> delegateFor(
    String packageName,
  ) =>
      _AppLocalizationsDelegate(packageName: packageName);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate({this.packageName});

  final String? packageName;

  @override
  bool isSupported(Locale locale) => ['en', 'fa'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    AppLocalizations localizations =
        AppLocalizations(locale, packageName: packageName);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
