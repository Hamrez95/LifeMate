import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/models/schedule_item_model.dart';
import 'package:wellmate/screens/home/soft_schedule_card.dart';

void main() {
  testWidgets('missed visit uses done/not-done wording and both actions work', (
    tester,
  ) async {
    var completed = 0;
    var notCompleted = 0;
    final item = ScheduleItemModel(
      id: 'visit-1',
      title: 'چکاپ زنان',
      time: '18:30',
      dosage: 'سارا راد • مرکز الوند',
      type: 'appointment',
      status: 'missed',
      frequency: 'ویزیت',
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: Scaffold(
          body: SoftScheduleCard(
            item: item,
            index: 0,
            font: const TextStyle(),
            assetPath: 'assets/icons/stethoscope.png',
            isMissed: true,
            onCompleted: () => completed++,
            onNotCompleted: () => notCompleted++,
          ),
        ),
      ),
    );

    expect(find.text('مصرف کردم'), findsNothing);
    expect(find.text('انجام شد'), findsOneWidget);
    expect(find.text('انجام نشد'), findsOneWidget);

    await tester.tap(find.text('انجام شد'));
    await tester.tap(find.text('انجام نشد'));
    expect(completed, 1);
    expect(notCompleted, 1);
  });
}
