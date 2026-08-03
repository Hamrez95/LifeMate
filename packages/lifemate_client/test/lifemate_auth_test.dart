import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('WellMate and CareMate use isolated OAuth callback schemes', () {
    expect(
      LifeMateAuth.callbackUrlForApp('WellMate'),
      'com.lifemate.wellmate://login-callback/',
    );
    expect(
      LifeMateAuth.callbackUrlForApp('CareMate'),
      'com.lifemate.caremate://login-callback/',
    );
  });

  test('Google auth is fail-closed by default', () {
    expect(LifeMateFeatureFlags.googleAuthEnabled, isFalse);
  });

  test('disabled Google auth returns before creating an OAuth request', () async {
    expect(
      await LifeMateAuth.signInWithGoogle(appName: 'WellMate'),
      isFalse,
    );
  });
}
