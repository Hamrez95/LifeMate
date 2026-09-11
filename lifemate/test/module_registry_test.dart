import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/modules/module_registry.dart';
import 'package:lifemate/modules/module_route_host.dart';

void main() {
  test('registry resolves stable module IDs and routes independently', () {
    final registry = LifeMateModuleRegistry.foundation();

    expect(registry.modules, hasLength(5));
    expect(
      registry.byId(LifeMateModuleId.wellMate)?.routeName,
      '/modules/wellmate',
    );
    expect(
      registry.byRoute('/modules/caremate')?.id,
      LifeMateModuleId.careMate,
    );
  });

  test('registry rejects duplicate IDs and duplicate routes', () {
    const first = LifeMateModuleDefinition(
      id: LifeMateModuleId.wellMate,
      routeName: '/modules/wellmate',
      labelEn: 'WellMate',
      labelFa: 'ول‌میت',
      icon: Icons.health_and_safety_outlined,
      availability: ModuleAvailability.unavailable,
    );
    const duplicateId = LifeMateModuleDefinition(
      id: LifeMateModuleId.wellMate,
      routeName: '/modules/wellmate-alt',
      labelEn: 'WellMate alt',
      labelFa: 'ول‌میت جایگزین',
      icon: Icons.health_and_safety_outlined,
      availability: ModuleAvailability.unavailable,
    );
    const duplicateRoute = LifeMateModuleDefinition(
      id: LifeMateModuleId.careMate,
      routeName: '/modules/wellmate',
      labelEn: 'CareMate',
      labelFa: 'کرمیت',
      icon: Icons.volunteer_activism_outlined,
      availability: ModuleAvailability.unavailable,
    );

    expect(
      () => LifeMateModuleRegistry([first, duplicateId]),
      throwsArgumentError,
    );
    expect(
      () => LifeMateModuleRegistry([first, duplicateRoute]),
      throwsArgumentError,
    );
  });

  testWidgets('available module mounts through isolated route host', (
    tester,
  ) async {
    final module = LifeMateModuleDefinition(
      id: LifeMateModuleId.wellMate,
      routeName: '/modules/wellmate',
      labelEn: 'WellMate',
      labelFa: 'ول‌میت',
      icon: Icons.health_and_safety_outlined,
      availability: ModuleAvailability.available,
      pageBuilder: (_) => const Scaffold(body: Text('WellMate mounted')),
    );

    await tester.pumpWidget(
      MaterialApp(home: ModuleRouteHost(module: module, isPersian: false)),
    );

    expect(find.text('WellMate mounted'), findsOneWidget);
  });

  testWidgets('unavailable module fails closed without breaking host', (
    tester,
  ) async {
    const module = LifeMateModuleDefinition(
      id: LifeMateModuleId.fitMate,
      routeName: '/modules/fitmate',
      labelEn: 'FitMate',
      labelFa: 'فیت‌میت',
      icon: Icons.directions_run_outlined,
      availability: ModuleAvailability.unavailable,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: ModuleRouteHost(module: module, isPersian: false),
      ),
    );

    expect(find.text('FitMate'), findsWidgets);
    expect(find.textContaining('not mounted'), findsOneWidget);
  });

  testWidgets('synchronous module construction failure is isolated', (
    tester,
  ) async {
    final module = LifeMateModuleDefinition(
      id: LifeMateModuleId.careMate,
      routeName: '/modules/caremate',
      labelEn: 'CareMate',
      labelFa: 'کرمیت',
      icon: Icons.volunteer_activism_outlined,
      availability: ModuleAvailability.available,
      pageBuilder: (_) => throw StateError('module failed'),
    );

    await tester.pumpWidget(
      MaterialApp(home: ModuleRouteHost(module: module, isPersian: false)),
    );

    expect(find.textContaining('shell is still available'), findsOneWidget);
  });

  testWidgets('Persian unavailable state remains RTL-compatible', (
    tester,
  ) async {
    const module = LifeMateModuleDefinition(
      id: LifeMateModuleId.cocoonMate,
      routeName: '/modules/cocoonmate',
      labelEn: 'CocoonMate',
      labelFa: 'کوکون‌میت',
      icon: Icons.child_friendly_outlined,
      availability: ModuleAvailability.locked,
    );

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('fa'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ModuleRouteHost(module: module, isPersian: true),
        ),
      ),
    );

    expect(find.text('کوکون‌میت'), findsWidgets);
    expect(find.textContaining('در وضعیت فعلی حساب'), findsOneWidget);
  });
}
