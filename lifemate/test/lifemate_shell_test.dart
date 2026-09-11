import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/app/lifemate_app.dart';
import 'package:lifemate/modules/module_registry.dart';
import 'package:lifemate/shell/lifemate_shell.dart';

void main() {
  testWidgets('renders five primary destinations and switches to Today', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LifeMateApp(home: LifeMateShell(), localeOverride: Locale('en')),
    );

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Journey'), findsOneWidget);
    expect(find.text('Circle'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);

    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Cross-module priorities'), findsOneWidget);
  });

  testWidgets('back from a peer destination returns to Home', (tester) async {
    await tester.pumpWidget(
      const LifeMateApp(home: LifeMateShell(), localeOverride: Locale('en')),
    );

    await tester.tap(find.text('Circle'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Relationships, companion selection'),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

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

      final hotspot = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'WellMate',
        description: 'WellMate semantic hotspot',
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
    await tester.pumpWidget(
      const LifeMateApp(home: LifeMateShell(), localeOverride: Locale('en')),
    );

    final hotspot = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == 'WellMate',
      description: 'WellMate semantic hotspot',
    );
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
