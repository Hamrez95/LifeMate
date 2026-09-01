import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('care access screen keeps the redesigned management contract', () {
    final source = File('lib/screens/profile/care_access_screen.dart').readAsStringSync();
    final compatibilityRoute = File(
      'lib/screens/profile/care_access_phone_screen.dart',
    ).readAsStringSync();

    expect(source, contains('افزودن مراقب جدید'));
    expect(source, contains('درخواست‌های جدید'));
    expect(source, contains('مراقبان فعال'));
    expect(source, contains('دعوت‌های ارسال‌شده'));
    expect(source, contains('Icons.settings_rounded'));
    expect(source, contains('showModalBottomSheet<void>'));
    expect(source, contains('CareAccessSettingsScreen(relationship: relationship)'));
    expect(source, contains('revokeCareInvitation('));
    expect(source, contains("relationship['caregiverProfilePhotoUrl']"));
    expect(source, contains("relationship['caregiverAvatarKey']"));
    expect(source, contains('LifeMateProfileAvatar('));

    final emptyStart = source.indexOf('class _NoIncomingRequestsCard');
    final emptyEnd = source.indexOf('class _CaregiverCard');
    final emptyState = source.substring(emptyStart, emptyEnd);
    expect(emptyState, contains('Icons.inbox_outlined'));
    expect(emptyState, isNot(contains('Icons.check_rounded')));
    expect(emptyState, isNot(contains('Icons.close_rounded')));

    expect(compatibilityRoute, contains('RelationshipInviteFlowScreen'));
    expect(compatibilityRoute, isNot(contains('createPhoneCareInvitation')));
    expect(compatibilityRoute.toLowerCase(), isNot(contains('kavenegar')));
    expect(compatibilityRoute.toLowerCase(), isNot(contains('icons.sms')));
    expect(compatibilityRoute, isNot(contains('phone_invitation_delivery')));
    expect(
      File('lib/screens/profile/care_phone_invite_dialog.dart').existsSync(),
      isFalse,
    );
  });
}
