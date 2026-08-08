import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  tearDown(LifeMateNotice.clearForTesting);

  testWidgets('LifeMate notice appears in overlay and can be dismissed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => LifeMateNotice.show(
                context,
                type: LifeMateNoticeType.success,
                message: 'ثبت شد',
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pump();
    expect(find.text('ثبت شد'), findsOneWidget);
    await tester.tap(find.byTooltip('بستن'));
    await tester.pumpAndSettle();
    expect(find.text('ثبت شد'), findsNothing);
  });
}
