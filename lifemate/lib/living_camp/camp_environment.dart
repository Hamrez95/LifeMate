import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum CampDayPhase { day, night }

enum CampDaylightOverride { automatic, day, night }

@immutable
class CampCoarseLocation {
  const CampCoarseLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

@immutable
class CampEnvironmentPreferences {
  const CampEnvironmentPreferences({
    this.coarseLocation,
    this.timezoneOffset,
    this.debugDaylightOverride = CampDaylightOverride.automatic,
  });

  final CampCoarseLocation? coarseLocation;
  final Duration? timezoneOffset;
  final CampDaylightOverride debugDaylightOverride;
}

@immutable
class CampDaylightWindow {
  const CampDaylightWindow({
    required this.sunriseMinute,
    required this.sunsetMinute,
    required this.usesFallback,
  });

  static const fallback = CampDaylightWindow(
    sunriseMinute: 6 * 60,
    sunsetMinute: 20 * 60,
    usesFallback: true,
  );

  final int sunriseMinute;
  final int sunsetMinute;
  final bool usesFallback;

  bool containsMinute(int minuteOfDay) {
    if (sunriseMinute <= sunsetMinute) {
      return minuteOfDay >= sunriseMinute && minuteOfDay < sunsetMinute;
    }
    return minuteOfDay >= sunriseMinute || minuteOfDay < sunsetMinute;
  }
}

@immutable
class CampEnvironmentState {
  const CampEnvironmentState({
    required this.phase,
    required this.daylightFactor,
    required this.daylightWindow,
    required this.isForeground,
    required this.motionEnabled,
  });

  final CampDayPhase phase;

  /// 0 is fully dark; 1 is full daylight, with a 60-minute soft transition.
  final double daylightFactor;
  final CampDaylightWindow daylightWindow;
  final bool isForeground;
  final bool motionEnabled;
}

class CampDaylightResolver {
  const CampDaylightResolver();

  CampDaylightWindow resolveWindow({
    required DateTime nowUtc,
    required CampEnvironmentPreferences preferences,
  }) {
    final location = preferences.coarseLocation;
    if (location == null || !location.isValid) {
      return CampDaylightWindow.fallback;
    }

    final offset = _timezoneOffset(nowUtc, preferences);
    final local = nowUtc.toUtc().add(offset);
    final dayOfYear = _dayOfYear(local);
    final gamma = 2 * math.pi / 365 * (dayOfYear - 1);
    final equationOfTime =
        229.18 *
        (0.000075 +
            0.001868 * math.cos(gamma) -
            0.032077 * math.sin(gamma) -
            0.014615 * math.cos(2 * gamma) -
            0.040849 * math.sin(2 * gamma));
    final declination =
        0.006918 -
        0.399912 * math.cos(gamma) +
        0.070257 * math.sin(gamma) -
        0.006758 * math.cos(2 * gamma) +
        0.000907 * math.sin(2 * gamma) -
        0.002697 * math.cos(3 * gamma) +
        0.00148 * math.sin(3 * gamma);

    final latitude = _degreesToRadians(location.latitude);
    final zenith = _degreesToRadians(90.833);
    final denominator = math.cos(latitude) * math.cos(declination);
    if (denominator.abs() < 1e-9) return CampDaylightWindow.fallback;

    final cosHourAngle =
        (math.cos(zenith) / denominator) -
        math.tan(latitude) * math.tan(declination);
    if (!cosHourAngle.isFinite || cosHourAngle < -1 || cosHourAngle > 1) {
      return CampDaylightWindow.fallback;
    }

    final hourAngleDegrees = math.acos(cosHourAngle) * 180 / math.pi;
    final solarNoonUtcMinutes = 720 - (4 * location.longitude) - equationOfTime;
    final sunriseUtcMinutes = solarNoonUtcMinutes - (4 * hourAngleDegrees);
    final sunsetUtcMinutes = solarNoonUtcMinutes + (4 * hourAngleDegrees);

    return CampDaylightWindow(
      sunriseMinute: _normalizeMinute(sunriseUtcMinutes + offset.inMinutes),
      sunsetMinute: _normalizeMinute(sunsetUtcMinutes + offset.inMinutes),
      usesFallback: false,
    );
  }

  CampDayPhase resolvePhase({
    required DateTime nowUtc,
    required CampEnvironmentPreferences preferences,
  }) {
    switch (preferences.debugDaylightOverride) {
      case CampDaylightOverride.day:
        return CampDayPhase.day;
      case CampDaylightOverride.night:
        return CampDayPhase.night;
      case CampDaylightOverride.automatic:
        break;
    }

    final offset = _timezoneOffset(nowUtc, preferences);
    final local = nowUtc.toUtc().add(offset);
    final minuteOfDay = local.hour * 60 + local.minute;
    final window = resolveWindow(nowUtc: nowUtc, preferences: preferences);
    return window.containsMinute(minuteOfDay)
        ? CampDayPhase.day
        : CampDayPhase.night;
  }

  double resolveDaylightFactor({
    required DateTime nowUtc,
    required CampEnvironmentPreferences preferences,
    CampDaylightWindow? daylightWindow,
  }) {
    switch (preferences.debugDaylightOverride) {
      case CampDaylightOverride.day:
        return 1;
      case CampDaylightOverride.night:
        return 0;
      case CampDaylightOverride.automatic:
        break;
    }
    final local = nowUtc.toUtc().add(_timezoneOffset(nowUtc, preferences));
    final minute = local.hour * 60 + local.minute + local.second / 60;
    final window =
        daylightWindow ??
        resolveWindow(nowUtc: nowUtc, preferences: preferences);
    double distanceFrom(double target) =>
        ((minute - target + 720 + 1440) % 1440) - 720;
    double smoothStep(double value) {
      final t = value.clamp(0.0, 1.0);
      return t * t * (3 - 2 * t);
    }

    final sunriseDelta = distanceFrom(window.sunriseMinute.toDouble());
    if (sunriseDelta.abs() <= 30) {
      return smoothStep((sunriseDelta + 30) / 60);
    }
    final sunsetDelta = distanceFrom(window.sunsetMinute.toDouble());
    if (sunsetDelta.abs() <= 30) {
      return 1 - smoothStep((sunsetDelta + 30) / 60);
    }
    return window.containsMinute(minute.floor()) ? 1 : 0;
  }

  Duration _timezoneOffset(
    DateTime nowUtc,
    CampEnvironmentPreferences preferences,
  ) {
    return preferences.timezoneOffset ?? nowUtc.toLocal().timeZoneOffset;
  }

  int _dayOfYear(DateTime local) {
    final current = DateTime.utc(local.year, local.month, local.day);
    final first = DateTime.utc(local.year);
    return current.difference(first).inDays + 1;
  }

  int _normalizeMinute(double minute) {
    final rounded = minute.round();
    return ((rounded % 1440) + 1440) % 1440;
  }

  double _degreesToRadians(double degrees) => degrees * math.pi / 180;
}

typedef CampEnvironmentBuilder =
    Widget Function(BuildContext context, CampEnvironmentState state);

class CampEnvironmentHost extends StatefulWidget {
  const CampEnvironmentHost({
    super.key,
    required this.builder,
    this.preferences = const CampEnvironmentPreferences(),
    this.resolver = const CampDaylightResolver(),
    this.nowUtc,
  });

  final CampEnvironmentBuilder builder;
  final CampEnvironmentPreferences preferences;
  final CampDaylightResolver resolver;
  final DateTime Function()? nowUtc;

  @override
  State<CampEnvironmentHost> createState() => _CampEnvironmentHostState();
}

class _CampEnvironmentHostState extends State<CampEnvironmentHost>
    with WidgetsBindingObserver {
  late CampDayPhase _phase;
  late double _daylightFactor;
  late CampDaylightWindow _daylightWindow;
  late bool _isForeground;
  Timer? _clock;

  DateTime get _nowUtc => (widget.nowUtc?.call() ?? DateTime.now()).toUtc();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isForeground = switch (WidgetsBinding.instance.lifecycleState) {
      null || AppLifecycleState.resumed => true,
      _ => false,
    };
    _recomputeEnvironment();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_isForeground) return;
      final previousPhase = _phase;
      final previousFactor = _daylightFactor;
      _recomputeEnvironment();
      if (previousPhase != _phase ||
          (previousFactor - _daylightFactor).abs() >= .002) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(CampEnvironmentHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences ||
        oldWidget.resolver != widget.resolver ||
        oldWidget.nowUtc != widget.nowUtc) {
      _recomputeEnvironment();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      setState(() {
        _isForeground = true;
        _recomputeEnvironment(notify: false);
      });
      return;
    }
    if (_isForeground) {
      setState(() => _isForeground = false);
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _recomputeEnvironment({bool notify = false}) {
    final nowUtc = _nowUtc;
    final window = widget.resolver.resolveWindow(
      nowUtc: nowUtc,
      preferences: widget.preferences,
    );
    final phase = widget.resolver.resolvePhase(
      nowUtc: nowUtc,
      preferences: widget.preferences,
    );
    final factor = widget.resolver.resolveDaylightFactor(
      nowUtc: nowUtc,
      preferences: widget.preferences,
      daylightWindow: window,
    );
    if (notify && mounted) {
      setState(() {
        _daylightWindow = window;
        _phase = phase;
        _daylightFactor = factor;
      });
      return;
    }
    _daylightWindow = window;
    _phase = phase;
    _daylightFactor = factor;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        media?.disableAnimations == true || media?.accessibleNavigation == true;
    final motionEnabled = _isForeground && !reduceMotion;
    final state = CampEnvironmentState(
      phase: _phase,
      daylightFactor: _daylightFactor,
      daylightWindow: _daylightWindow,
      isForeground: _isForeground,
      motionEnabled: motionEnabled,
    );

    return TickerMode(
      key: const ValueKey<String>('camp-environment-motion'),
      enabled: motionEnabled,
      child: widget.builder(context, state),
    );
  }
}
