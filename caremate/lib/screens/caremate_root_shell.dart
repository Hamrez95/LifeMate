import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import 'calendar/calendar_screen.dart';
import 'care_event_management_screen.dart';
import 'dashboard_screen.dart';
import 'feature_preview_screen.dart';
import 'onboarding/caremate_relationship_v3_gate.dart';

class CareMateRootShell extends StatefulWidget {
  const CareMateRootShell({super.key});

  @override
  State<CareMateRootShell> createState() => _CareMateRootShellState();
}

class _CareMateRootShellState extends State<CareMateRootShell>
    with WidgetsBindingObserver {
  static const _refreshInterval = Duration(seconds: 8);
  static const _refreshTick = Duration(seconds: 2);
  static const _prewarmDelay = Duration(milliseconds: 350);

  int _currentIndex = 4;
  final Set<int> _visitedTabs = <int>{4};
  final List<int> _refreshTokens = List<int>.filled(5, 0);
  final List<DateTime> _lastRefresh = List<DateTime>.filled(5, DateTime.now());
  Timer? _refreshTimer;
  Timer? _prewarmTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(
      _refreshTick,
      (_) => _refreshActiveIfStale(),
    );
    _prewarmTimer = Timer(_prewarmDelay, () {
      if (!mounted) return;
      setState(() => _visitedTabs.addAll(const <int>{0, 1, 2, 3, 4}));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _prewarmTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshTab(_currentIndex, force: true);
    }
  }

  void _selectTab(int index) {
    if (index < 0 || index > 4) return;
    final changed = _currentIndex != index;
    if (changed) {
      setState(() {
        _visitedTabs.add(index);
        _currentIndex = index;
      });
    }
    // A relationship may have been revoked from another CareMate surface.
    // Force a fresh server read whenever the user switches destinations so a
    // previously rendered patient snapshot cannot reappear from an IndexedStack.
    _refreshTab(index, force: changed);
  }

  void _refreshActiveIfStale() => _refreshTab(_currentIndex);

  void _refreshTab(int index, {bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastRefresh[index]) < _refreshInterval) {
      return;
    }
    _lastRefresh[index] = now;
    if (!mounted) return;
    setState(() => _refreshTokens[index]++);
  }

  Widget _tab(int index) {
    if (!_visitedTabs.contains(index)) return const SizedBox.shrink();
    return switch (index) {
      0 => CalendarScreen(
        refreshToken: _refreshTokens[0],
        onNavigationTap: _selectTab,
      ),
      1 => CareMateFeaturePreviewScreen(
        initialIndex: 1,
        refreshToken: _refreshTokens[1],
        onNavigationTap: _selectTab,
      ),
      2 => CareEventManagementScreen(
        refreshToken: _refreshTokens[2],
        onNavigationTap: _selectTab,
      ),
      3 => CareMateFeaturePreviewScreen(
        initialIndex: 3,
        refreshToken: _refreshTokens[3],
        onNavigationTap: _selectTab,
      ),
      _ => DashboardScreen(
        refreshToken: _refreshTokens[4],
        onNavigationTap: _selectTab,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final apiClient = context.read<LifeMateApiClient>();
    return CareMateRelationshipV3Gate(
      apiClient: apiClient,
      child: IndexedStack(
        index: _currentIndex,
        children: List<Widget>.generate(5, _tab),
      ),
    );
  }
}
