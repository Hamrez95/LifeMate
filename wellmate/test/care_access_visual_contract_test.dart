import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('care access screen keeps the redesigned management contract', () {
    final shell = File(
      'lib/screens/profile/care_access_screen.dart',
    ).readAsStringSync();
    final base = File(
      'lib/screens/profile/care_access_screen_base.dart',
    ).readAsStringSync();
    final phoneDialog = File(
      'lib/screens/profile/care_phone_invite_dialog.dart',
    ).readAsStringSync();

    expect(base, contains('افزودن مراقب جدید'));
    expect(base, contains('درخواست‌های جدید'));
    expect(base, contains('مراقبان فعال'));
    expect(base, contains('دعوت‌های ارسال‌شده'));
    expect(base, contains('Icons.settings_rounded'));
    expect(base, contains('showModalBottomSheet<void>'));
    expect(
      base,
      contains('CareAccessSettingsScreen(relationship: relationship)'),
    );
    expect(base, contains('revokeCareInvitation('));
    expect(base, contains("relationship['caregiverProfilePhotoUrl']"));
    expect(base, contains("relationship['caregiverAvatarKey']"));
    expect(base, contains('LifeMateProfileAvatar('));

    final emptyStart = base.indexOf('class _NoIncomingRequestsCard');
    final emptyEnd = base.indexOf('class _CaregiverCard');
    final emptyState = base.substring(emptyStart, emptyEnd);
    expect(emptyState, contains('Icons.inbox_outlined'));
    expect(emptyState, isNot(contains('Icons.check_rounded')));
    expect(emptyState, isNot(contains('Icons.close_rounded')));

    expect(shell, contains("createPhoneCareInvitation(phone: phone)"));
    expect(shell, contains("ValueKey('care-phone-invite-action')"));
    expect(shell, contains('دعوت مراقب با شماره موبایل'));
    expect(shell, contains('کد محرمانه در این برنامه نمایش داده نمی‌شود'));
    expect(shell, isNot(contains("invitation['token']")));
    expect(shell, isNot(contains('Clipboard.setData')));

    expect(phoneDialog, contains('TextInputType.phone'));
    expect(phoneDialog, contains('normalizeIranianMobileInput'));
    expect(phoneDialog, contains('confirm'));
    expect(phoneDialog, contains('در این برنامه نمایش داده نمی‌شود'));
  });
}
