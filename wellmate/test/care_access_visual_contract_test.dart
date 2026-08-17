import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('care access screen keeps the redesigned management contract', () {
    final source = File(
      'lib/screens/profile/care_access_screen.dart',
    ).readAsStringSync();
    final phoneShell = File(
      'lib/screens/profile/care_access_phone_screen.dart',
    ).readAsStringSync();
    final phoneDialog = File(
      'lib/screens/profile/care_phone_invite_dialog.dart',
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

    expect(phoneShell, contains("createPhoneCareInvitation(phone: phone)"));
    expect(phoneShell, contains("ValueKey('care-phone-invite-action')"));
    expect(phoneShell, contains('دعوت مراقب با شماره موبایل'));
    expect(
      phoneShell,
      contains('کد محرمانه در این برنامه نمایش داده نمی‌شود'),
    );
    expect(phoneShell, isNot(contains("invitation['token']")));
    expect(phoneShell, isNot(contains('Clipboard.setData')));

    expect(phoneDialog, contains('TextInputType.phone'));
    expect(phoneDialog, contains('normalizeIranianMobileInput'));
    expect(phoneDialog, contains('confirmed'));
    expect(phoneDialog, contains('در این برنامه نمایش داده نمی‌شود'));
  });
}
