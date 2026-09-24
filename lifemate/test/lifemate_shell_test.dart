import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/app/lifemate_app.dart';
import 'package:lifemate/modules/module_registry.dart';
import 'package:lifemate/shell/lifemate_shell.dart';

void main() {
  testWidgets('compact header keeps profile and notifications reachable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const LifeMateApp(home: LifeMateShell(), localeOverride: Locale('fa')),
    );
    expect(find.byTooltip('اعلان‌ها'), findsOneWidget);
    expect(find.byTooltip('باز کردن پروفایل'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('باز کردن پروفایل'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    expect(find.text('شما'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders four primary destinations and opens Today from card', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LifeMateApp(home: LifeMateShell(), localeOverride: Locale('en')),
    );

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Journey'), findsOneWidget);
    expect(find.text('Circle'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
      hasLength(4),
    );
    expect(find.byKey(const ValueKey('camp-today-card')), findsOneWidget);

    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View full day'));
    await tester.pumpAndSettle();

    expect(find.text('Today is not connected yet'), findsOneWidget);
  });

  testWidgets('back from a peer destination returns to Home', (tester) async {
    await tester.pumpWidget(
      const LifeMateApp(home: LifeMateShell(), localeOverride: Locale('en')),
    );

    await tester.tap(find.text('Circle'));
    await tester.pumpAndSettle();
    expect(find.text('Camp companions'), findsOneWidget);
    expect(
      find.text('Camp companion selection is not connected yet.'),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    // Home intentionally keeps ambient animation running.
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Living Camp'), findsOneWidget);
  });

  testWidgets('Persian locale is RTL and keeps semantic destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LifeMateApp(home: LifeMateShell(), localeOverride: Locale('fa')),
    );

    final directionality = tester.widget<Directionality>(
      find.byType(Directionality).first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
    expect(find.text('خانه'), findsWidgets);
    expect(find.text('امروز'), findsWidgets);
    expect(find.text('دایره'), findsOneWidget);
    expect(find.text('شما'), findsOneWidget);
  });

  testWidgets(
    'WellMate hotspot routes through the module host after response',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final registry = LifeMateModuleRegistry.foundation().replacing(
        LifeMateModuleDefinition(
          id: LifeMateModuleId.wellMate,
          routeName: '/modules/wellmate',
          labelEn: 'WellMate',
          labelFa: 'ول‌میت',
          icon: Icons.health_and_safety_outlined,
          availability: ModuleAvailability.available,
          pageBuilder: (_) => const Scaffold(body: Text('WellMate mounted')),
        ),
      );

      await tester.pumpWidget(
        LifeMateApp(
          home: LifeMateShell(moduleRegistry: registry),
          localeOverride: const Locale('en'),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'WellMate',
          description: 'WellMate semantic hotspot',
        ),
        findsOneWidget,
      );
      final hotspot = find.byKey(
        const ValueKey<String>('camp-zone-hit-wellmate'),
      );
      expect(hotspot, findsOneWidget);

      await tester.tap(hotspot);
      await tester.pump(const Duration(milliseconds: 349));
      expect(find.text('WellMate mounted'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('WellMate mounted'), findsOneWidget);
    },
  );

  testWidgets('WellMate unavailable fallback is truthful', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const LifeMateApp(home: LifeMateShell(), localeOverride: Locale('en')),
    );

    final hotspot = find.byKey(
      const ValueKey<String>('camp-zone-hit-wellmate'),
    );
    expect(hotspot, findsOneWidget);
    await tester.tap(hotspot);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('WellMate'), findsWidgets);
    expect(
      find.text('This module is not mounted in the parent app yet.'),
      findsOneWidget,
    );
  });
}
