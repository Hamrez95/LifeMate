import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/screens/health/health_screen.dart';

class _FakeHealthApi extends LifeMateHealthApi {
  _FakeHealthApi()
      : super(
          baseUri: Uri.parse('https://api.example.test'),
          accessToken: () => 'test-token',
        );

  @override
  Future<List<LifeMateHealthObservation>> listObservations({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const [];

  @override
  void close() {}
}

void main() {
  testWidgets('health hub renders real-data empty states and coming soon gadget gate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HealthScreen(healthApi: _FakeHealthApi())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('health-title')), findsOneWidget);
    expect(find.text('سلامت من'), findsOneWidget);
    expect(find.byKey(const ValueKey('health-quick-log')), findsOneWidget);
    expect(find.text('ثبت سریع'), findsOneWidget);
    expect(find.byKey(const ValueKey('health-calendar-history')), findsOneWidget);
    expect(find.text('تاریخچه سلامت'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, -1600));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('health-gadgets-coming-soon')), findsOneWidget);
    expect(find.text('به‌زودی'), findsOneWidget);
  });

  testWidgets('quick note opens the polished dated entry sheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HealthScreen(healthApi: _FakeHealthApi())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('یادداشت').last);
    await tester.pumpAndSettle();

    expect(find.text('یادداشت سلامت'), findsWidgets);
    expect(find.text('تاریخ'), findsOneWidget);
    expect(find.text('زمان'), findsOneWidget);
    expect(find.byKey(const ValueKey('health-entry-save')), findsOneWidget);
  });
}
