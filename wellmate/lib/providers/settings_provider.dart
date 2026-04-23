import 'package:flutter/material.dart';

class SettingsProvider with ChangeNotifier {
  // سایز پیش‌فرض 1.0 (حالت عادی) است. برای افراد سالخورده می‌توانیم آن را 1.2 یا 1.3 کنیم.
  double _textScaleFactor = 1.0;

  double get textScaleFactor => _textScaleFactor;

  void updateTextScale(double newScale) {
    _textScaleFactor = newScale;
    notifyListeners();
  }
}
