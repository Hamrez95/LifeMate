import 'package:caremate/screens/editable_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('CareMate profile editor saves the stable backend profile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ProfileApiClient();
    await tester.pumpWidget(
      Provider<LifeMateApiClient>.value(
        value: api,
        child: const MaterialApp(home: CareMateEditableProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('حمیدرضا'), findsOneWidget);
    expect(find.text('caregiver@example.test'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'حمیدرضا پاکپور');
    await tester.enterText(fields.at(2), '+49 151 7654321');
    await tester.enterText(fields.at(3), 'Europe/Berlin');

    final save = find.byKey(const ValueKey<String>('care-profile-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(api.savedVersion, 4);
    expect(api.savedDisplayName, 'حمیدرضا پاکپور');
    expect(api.savedPhoneNumber, '+49 151 7654321');
    expect(api.savedLocale, 'fa');
    expect(api.savedTimeZone, 'Europe/Berlin');
    expect(find.text('اطلاعات پروفایل با موفقیت ذخیره شد.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ProfileApiClient extends LifeMateApiClient {
  _ProfileApiClient()
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () => 'test-token',
        );

  int? savedVersion;
  String? savedDisplayName;
  String? savedPhoneNumber;
  String? savedLocale;
  String? savedTimeZone;

  @override
  Future<Map<String, dynamic>> getCurrentProfile() async => {
        'id': 'profile-2',
        'userId': 'user-2',
        'displayName': 'حمیدرضا',
        'email': 'caregiver@example.test',
        'phoneNumber': null,
        'locale': 'fa',
        'timeZone': 'Asia/Tehran',
        'version': 4,
      };

  @override
  Future<Map<String, dynamic>> updateCurrentProfile({
    required int version,
    required String displayName,
    String? phoneNumber,
    required String locale,
    required String timeZone,
  }) async {
    savedVersion = version;
    savedDisplayName = displayName;
    savedPhoneNumber = phoneNumber;
    savedLocale = locale;
    savedTimeZone = timeZone;
    return {
      'id': 'profile-2',
      'userId': 'user-2',
      'displayName': displayName.trim(),
      'email': 'caregiver@example.test',
      'phoneNumber': phoneNumber?.replaceAll(' ', ''),
      'locale': locale,
      'timeZone': timeZone.trim(),
      'version': version + 1,
    };
  }
}
