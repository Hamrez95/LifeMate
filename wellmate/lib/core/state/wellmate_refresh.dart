import 'dart:async';

import 'package:flutter/material.dart';

/// A lightweight invalidation signal for screens kept alive by WellMate's
/// [IndexedStack]. Route pop/remove/replace events are coalesced by the shell,
/// so returning from a write screen refreshes visible data without requiring a
/// manual pull-to-refresh gesture.
abstract final class WellMateRefreshSignal {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void notifyChanged() {
    revision.value = revision.value + 1;
  }
}

class WellMateNavigationRefreshObserver extends NavigatorObserver {
  bool _isDataPage(Route<dynamic>? route) => route is PageRoute<dynamic>;

  void _notifyAfterNavigation() {
    scheduleMicrotask(WellMateRefreshSignal.notifyChanged);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (_isDataPage(route)) _notifyAfterNavigation();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_isDataPage(route)) _notifyAfterNavigation();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (_isDataPage(oldRoute) || _isDataPage(newRoute)) {
      _notifyAfterNavigation();
    }
  }
}
