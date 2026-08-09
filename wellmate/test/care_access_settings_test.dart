import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/screens/profile/care_access_settings_screen.dart';

void main() {
  tearDown(LifeMateNotice.clearForTesting);

  testWidgets(
    'permission cards keep off switch visible and require explicit consent',
    (tester) async {
      final management = _FakeManagementApi();
      await tester.pumpWidget(
        Provider<LifeMateApiClient>.value(
          value: _FakeWellMateApi(),
          child: MaterialApp(
            locale: const Locale('fa'),
            home: CareAccessSettingsScreen(
              relationship: const {
                'id': 'relationship-1',
                'caregiverDisplayName': 'حمیدرضا',
                'canViewWomenCalendar': false,
              },
              managementApi: management,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('care-permission-medication')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('care-permission-women-calendar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('care-permission-health-record')),
        findsOneWidget,
      );
      expect(find.text('مشاهده و ویرایش پرونده سلامت'), findsOneWidget);

      final womenSwitch = tester.widget<Switch>(
        find.descendant(
          of: find.byKey(const ValueKey('care-permission-women-calendar')),
          matching: find.byType(Switch),
        ),
      );
      expect(womenSwitch.value, isFalse);
      expect(womenSwitch.inactiveTrackColor, const Color(0xFFD6DDE5));
      expect(womenSwitch.inactiveThumbColor, Colors.white);

      final healthSwitch = find.descendant(
        of: find.byKey(const ValueKey('care-permission-health-record')),
        matching: find.byType(Switch),
      );
      await tester.tap(healthSwitch);
      await tester.pumpAndSettle();

      expect(find.text('تأیید دسترسی حساس'), findsOneWidget);
      final confirmFinder = find.byKey(
        const ValueKey('confirm-health-record-access'),
      );
      expect(confirmFinder, findsOneWidget);
      expect(tester.widget<FilledButton>(confirmFinder).onPressed, isNull);

      await tester.tap(
        find.byKey(const ValueKey('health-record-consent-checkbox')),
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(confirmFinder).onPressed, isNotNull);
      await tester.tap(confirmFinder);
      await tester.pumpAndSettle();

      expect(management.lastEnabled, isTrue);
      expect(management.lastConfirmConsent, isTrue);
      expect(find.text('مدیریت پرونده فعال شد'), findsOneWidget);
    },
  );
}

class _FakeWellMateApi extends LifeMateApiClient {
  _FakeWellMateApi()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> getWomenCalendarProfile() async => const {
    'enabled': true,
  };

  @override
  Future<Map<String, dynamic>> updateCareRelationshipPermissions({
    required String relationshipId,
    required bool canViewWomenCalendar,
  }) async => {
    'id': relationshipId,
    'canViewWomenCalendar': canViewWomenCalendar,
  };
}

class _FakeManagementApi extends LifeMateCareManagementApi {
  _FakeManagementApi()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  bool? lastEnabled;
  bool? lastConfirmConsent;

  @override
  Future<Map<String, dynamic>> getRelationshipPermission({
    required String relationshipId,
  }) async => const {'canManageHealthRecord': false};

  @override
  Future<Map<String, dynamic>> updateHealthRecordPermission({
    required String relationshipId,
    required bool enabled,
    bool confirmConsent = false,
  }) async {
    lastEnabled = enabled;
    lastConfirmConsent = confirmConsent;
    return {'canManageHealthRecord': enabled};
  }
}
