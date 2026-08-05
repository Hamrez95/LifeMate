import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/screens/profile/editable_profile_screen.dart';

void main() {
  testWidgets('profile editor loads and saves the versioned backend profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _ProfileApiClient();
    await tester.pumpWidget(
      Provider<LifeMateApiClient>.value(
        value: api,
        child: const MaterialApp(home: EditableProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ریحانه'), findsOneWidget);
    expect(find.text('owner@example.test'), findsOneWidget);
    expect(find.text('+989121234567'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'ریحانه شکیبا');
    await tester.enterText(fields.at(2), '+49 151 1234567');
    await tester.enterText(fields.at(3), 'Europe/Berlin');

    final purpleAvatar = find.byKey(
      const ValueKey<String>('profile-avatar-person_purple'),
    );
    await tester.ensureVisible(purpleAvatar);
    await tester.tap(purpleAvatar);
    await tester.pumpAndSettle();

    final save = find.byKey(const ValueKey<String>('profile-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(api.savedVersion, 7);
    expect(api.savedDisplayName, 'ریحانه شکیبا');
    expect(api.savedPhoneNumber, '+49 151 1234567');
    expect(api.savedLocale, 'fa');
    expect(api.savedTimeZone, 'Europe/Berlin');
    expect(api.savedAvatarKey, 'person_purple');
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
  String? savedAvatarKey;

  @override
  Future<Map<String, dynamic>> getCurrentProfile() async => {
    'id': 'profile-1',
    'userId': 'user-1',
    'displayName': 'ریحانه',
    'email': 'owner@example.test',
    'phoneNumber': '+989121234567',
    'locale': 'fa',
    'timeZone': 'Asia/Tehran',
    'avatarKey': 'person_blue',
    'version': 7,
  };

  @override
  Future<Map<String, dynamic>> updateCurrentProfile({
    required int version,
    required String displayName,
    String? phoneNumber,
    required String locale,
    required String timeZone,
    required String avatarKey,
  }) async {
    savedVersion = version;
    savedDisplayName = displayName;
    savedPhoneNumber = phoneNumber;
    savedLocale = locale;
    savedTimeZone = timeZone;
    savedAvatarKey = avatarKey;
    return {
      'id': 'profile-1',
      'userId': 'user-1',
      'displayName': displayName.trim(),
      'email': 'owner@example.test',
      'phoneNumber': phoneNumber?.replaceAll(' ', ''),
      'locale': locale,
      'timeZone': timeZone.trim(),
      'avatarKey': avatarKey,
      'version': version + 1,
    };
  }
}
