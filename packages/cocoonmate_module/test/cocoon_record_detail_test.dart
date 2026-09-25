import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'record detail is read-only, semantic, and honest about pending sync', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: CocoonRecordDetailScreen(
            fa: false,
            record: const CocoonRecordViewData(
              id: 'mood-1',
              title: 'Mood',
              dateLabel: '2026-09-24',
              sectionLabel: '2026-09-24',
              summary: 'Good',
              kind: CocoonRecordKind.checkIn,
              syncState: CocoonRecordSyncState.pending,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Record details'), findsOneWidget);
    expect(find.text('Mood'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Pending sync'), 200);
    expect(find.text('Pending sync'), findsOneWidget);
    expect(
      find.text(
          'This entry is not confirmed by the server yet. It will stay marked as pending until a later sync confirms it.'),
      findsOneWidget,
    );
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Open original entry'), findsNothing);
  });

  testWidgets(
      'confirmed record delegates an original-entry route to the host in RTL',
      (tester) async {
    CocoonRecordViewData? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CocoonRecordDetailScreen(
            fa: true,
            record: const CocoonRecordViewData(
              id: 'appointment-1',
              title: 'ویزیت ماما',
              dateLabel: '۲۴ شهریور ۱۴۰۵',
              sectionLabel: 'این هفته',
              kind: CocoonRecordKind.appointment,
              syncState: CocoonRecordSyncState.confirmed,
            ),
            onOpenSource: (record) => opened = record,
          ),
        ),
      ),
    );

    expect(find.text('بازکردن مورد اصلی'), findsOneWidget);
    expect(find.bySemanticsLabel('بازکردن سابقهٔ اصلی'), findsOneWidget);
    await tester.tap(find.text('بازکردن مورد اصلی'));
    expect(opened?.id, 'appointment-1');
    expect(tester.takeException(), isNull);
  });
}
