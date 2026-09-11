import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/app/lifemate_app.dart';
import 'package:lifemate/shell/lifemate_shell.dart';
import 'package:lifemate/today/notification_center_contract.dart';
import 'package:lifemate/today/today_contract.dart';

void main() {
  NotificationCenterItem item({
    required String id,
    required String title,
    required TodaySeverity severity,
    required bool isRead,
    TodayOwnerKind ownerKind = TodayOwnerKind.currentPerson,
    String ownerName = 'You',
  }) {
    return NotificationCenterItem(
      notificationId: id,
      sourceModuleId: 'wellmate',
      owner: TodayOwnerPresentation(
        kind: ownerKind,
        presentationId: 'owner-$id',
        displayName: ownerName,
      ),
      display: TodayDisplayContent(
        title: title,
        subtitle: 'Notification detail',
        sourceLabel: 'WellMate',
      ),
      severity: severity,
      createdAt: DateTime.utc(2026, 9, 11, 8).add(Duration(minutes: id.length)),
      isRead: isRead,
    );
  }

  testWidgets('lists normalized severity, person context and read state', (
    tester,
  ) async {
    final source = SyntheticNotificationCenterSource([
      item(
        id: 'urgent',
        title: 'Urgent notification',
        severity: TodaySeverity.urgent,
        isRead: false,
      ),
      item(
        id: 'attention',
        title: 'Care notification',
        severity: TodaySeverity.needsAttention,
        isRead: true,
        ownerKind: TodayOwnerKind.companion,
        ownerName: 'Rey',
      ),
    ]);

    await tester.pumpWidget(
      LifeMateApp(
        home: LifeMateShell(notificationSource: source),
        localeOverride: const Locale('en'),
      ),
    );

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(
      find.text('Preview data — not live notification state'),
      findsOneWidget,
    );
    expect(find.text('Urgent notification'), findsOneWidget);
    expect(find.text('Urgent'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Care notification'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Rey'), findsOneWidget);
    expect(find.text('Mark read'), findsOneWidget);
    expect(find.text('Mark unread'), findsOneWidget);
  });

  testWidgets('read state mutation is routed through the source', (
    tester,
  ) async {
    final source = SyntheticNotificationCenterSource([
      item(
        id: 'unread',
        title: 'Unread notification',
        severity: TodaySeverity.normal,
        isRead: false,
      ),
    ]);

    await tester.pumpWidget(
      LifeMateApp(
        home: LifeMateShell(notificationSource: source),
        localeOverride: const Locale('en'),
      ),
    );

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Mark read'), findsOneWidget);

    await tester.tap(find.text('Mark read'));
    await tester.pumpAndSettle();

    expect(find.text('Mark unread'), findsOneWidget);
    final items = await source.load();
    expect(items.single.isRead, isTrue);
  });

  testWidgets('default source does not fabricate notification state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LifeMateApp(home: LifeMateShell(), localeOverride: Locale('en')),
    );

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(
      find.text('Notification Center is not connected yet'),
      findsOneWidget,
    );
    expect(
      find.text('No synthetic notification is shown as live state.'),
      findsOneWidget,
    );
  });

  testWidgets('Persian unavailable state remains RTL and localized', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LifeMateApp(home: LifeMateShell(), localeOverride: Locale('fa')),
    );

    await tester.tap(find.byTooltip('اعلان‌ها'));
    await tester.pumpAndSettle();

    final directionality = tester.widget<Directionality>(
      find.byType(Directionality).first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
    expect(find.text('مرکز اعلان‌ها هنوز متصل نیست'), findsOneWidget);
  });
}
