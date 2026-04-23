import 'package:flutter/material.dart';

class NotificationProvider extends ChangeNotifier {
  bool _hasUnread = false; // اگر true باشد، نقطه قرمز نمایش داده می‌شود

  bool get hasUnread => _hasUnread;

  void setUnread(bool value) {
    _hasUnread = value;
    notifyListeners();
  }
}
