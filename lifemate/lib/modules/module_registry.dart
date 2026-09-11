import 'package:flutter/material.dart';

enum LifeMateModuleId { wellMate, careMate, cocoonMate, womenHealth, fitMate }

enum ModuleAvailability { available, locked, unavailable }

typedef ModulePageBuilder = Widget Function(BuildContext context);

@immutable
class LifeMateModuleDefinition {
  const LifeMateModuleDefinition({
    required this.id,
    required this.routeName,
    required this.labelEn,
    required this.labelFa,
    required this.icon,
    required this.availability,
    this.pageBuilder,
  });

  final LifeMateModuleId id;
  final String routeName;
  final String labelEn;
  final String labelFa;
  final IconData icon;
  final ModuleAvailability availability;
  final ModulePageBuilder? pageBuilder;

  bool get canOpen =>
      availability == ModuleAvailability.available && pageBuilder != null;

  String label({required bool isPersian}) => isPersian ? labelFa : labelEn;
}

@immutable
class LifeMateModuleRegistry {
  LifeMateModuleRegistry(Iterable<LifeMateModuleDefinition> modules)
    : _modules = Map.unmodifiable({
        for (final module in modules) module.id: module,
      }) {
    if (_modules.length != modules.length) {
      throw ArgumentError('Module IDs must be unique.');
    }
    final routeNames = _modules.values
        .map((module) => module.routeName)
        .toSet();
    if (routeNames.length != _modules.length) {
      throw ArgumentError('Module route names must be unique.');
    }
  }

  final Map<LifeMateModuleId, LifeMateModuleDefinition> _modules;

  List<LifeMateModuleDefinition> get modules =>
      List.unmodifiable(_modules.values);

  LifeMateModuleDefinition? byId(LifeMateModuleId id) => _modules[id];

  LifeMateModuleDefinition? byRoute(String routeName) {
    for (final module in _modules.values) {
      if (module.routeName == routeName) return module;
    }
    return null;
  }

  LifeMateModuleRegistry replacing(LifeMateModuleDefinition module) {
    return LifeMateModuleRegistry([
      for (final current in _modules.values)
        if (current.id == module.id) module else current,
    ]);
  }

  factory LifeMateModuleRegistry.foundation() {
    return LifeMateModuleRegistry(const [
      LifeMateModuleDefinition(
        id: LifeMateModuleId.wellMate,
        routeName: '/modules/wellmate',
        labelEn: 'WellMate',
        labelFa: 'ول‌میت',
        icon: Icons.health_and_safety_outlined,
        availability: ModuleAvailability.unavailable,
      ),
      LifeMateModuleDefinition(
        id: LifeMateModuleId.careMate,
        routeName: '/modules/caremate',
        labelEn: 'CareMate',
        labelFa: 'کرمیت',
        icon: Icons.volunteer_activism_outlined,
        availability: ModuleAvailability.unavailable,
      ),
      LifeMateModuleDefinition(
        id: LifeMateModuleId.cocoonMate,
        routeName: '/modules/cocoonmate',
        labelEn: 'CocoonMate',
        labelFa: 'کوکون‌میت',
        icon: Icons.child_friendly_outlined,
        availability: ModuleAvailability.unavailable,
      ),
      LifeMateModuleDefinition(
        id: LifeMateModuleId.womenHealth,
        routeName: '/modules/women-health',
        labelEn: 'Women Health',
        labelFa: 'سلامت زنان',
        icon: Icons.nightlight_round,
        availability: ModuleAvailability.unavailable,
      ),
      LifeMateModuleDefinition(
        id: LifeMateModuleId.fitMate,
        routeName: '/modules/fitmate',
        labelEn: 'FitMate',
        labelFa: 'فیت‌میت',
        icon: Icons.directions_run_outlined,
        availability: ModuleAvailability.unavailable,
      ),
    ]);
  }
}
