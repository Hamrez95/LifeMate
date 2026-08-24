import 'package:caremate/widgets/custom_app_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'header exposes 48dp actions and announces a new care alert in Persian',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var notificationTaps = 0;
      var profileTaps = 0;
      await tester.pumpWidget(
        Provider<LifeMateApiClient>.value(
          value: _HeaderApi(),
          child: MaterialApp(
            locale: const Locale('fa'),
            home: Scaffold(
              body: CustomAppHeader(
                showNotificationDot: true,
                onNotificationTap: () => notificationTaps += 1,
                onProfileTap: () => profileTaps += 1,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final alerts = find.byKey(const Key('caremate-header-alerts'));
      final profile = find.byKey(const Key('caremate-header-profile'));
      expect(alerts, findsOneWidget);
      expect(profile, findsOneWidget);
      expect(
        find.bySemanticsLabel('هشدارهای مراقبتی، مورد جدید دارید'),
        findsOneWidget,
      );
      expect(tester.getSize(alerts).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(alerts).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(profile).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(profile).height, greaterThanOrEqualTo(48));

      await tester.tap(alerts);
      await tester.tap(profile);
      await tester.pump();
      expect(notificationTaps, 1);
      expect(profileTaps, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

class _HeaderApi extends LifeMateApiClient {
  _HeaderApi()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'token',
      );

  @override
  Future<Map<String, dynamic>> getCurrentProfile() async => const {
    'displayName': 'مراقب',
    'avatarKey': 'caregiver_teal',
    'profilePhotoUrl': null,
  };
}
