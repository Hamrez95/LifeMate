import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('care access screen keeps the redesigned management contract', () {
    final source = File(
      'lib/screens/profile/care_access_screen.dart',
    ).readAsStringSync();

    expect(source, contains('افزودن مراقب جدید'));
    expect(source, contains('درخواست‌های جدید'));
    expect(source, contains('مراقبان فعال'));
    expect(source, contains('دعوت‌های ارسال‌شده'));
    expect(source, contains('Icons.settings_rounded'));
    expect(source, contains('showModalBottomSheet<void>'));
    expect(
      source,
      contains('CareAccessSettingsScreen(relationship: relationship)'),
    );
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
  });
}
