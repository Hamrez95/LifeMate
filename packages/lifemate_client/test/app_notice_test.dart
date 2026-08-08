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

  testWidgets(
    'LifeMate notice text never inherits debug underline decoration',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => LifeMateNotice.show(
                  context,
                  type: LifeMateNoticeType.error,
                  title: 'ثبت انجام نشد',
                  message: 'دوباره تلاش کن',
                ),
                child: const Text('show-error'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('show-error'));
      await tester.pump();

      final title = tester.widget<Text>(find.text('ثبت انجام نشد'));
      final message = tester.widget<Text>(find.text('دوباره تلاش کن'));
      expect(title.style?.decoration, TextDecoration.none);
      expect(message.style?.decoration, TextDecoration.none);
    },
  );
}
