import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import 'care_access_screen.dart';
import 'care_phone_invite_dialog.dart';

/// Adds the provider-specific SMS invitation action around the existing
/// caregiver-management surface without coupling Kavenegar behavior to the
/// large email/QR/relationship screen.
class CareAccessPhoneScreen extends StatefulWidget {
  const CareAccessPhoneScreen({super.key});

  @override
  State<CareAccessPhoneScreen> createState() => _CareAccessPhoneScreenState();
}

class _CareAccessPhoneScreenState extends State<CareAccessPhoneScreen> {
  bool _sendingPhoneInvitation = false;
  int _contentRevision = 0;

  Future<void> _sendPhoneInvitation() async {
    if (_sendingPhoneInvitation) return;
    final phone = await showCarePhoneInviteDialog(context);
    if (phone == null || !mounted) return;

    setState(() => _sendingPhoneInvitation = true);
    try {
      final invitation = await context
          .read<LifeMateApiClient>()
          .createPhoneCareInvitation(phone: phone);
      if (!mounted) return;
      final contactHint = invitation['contactHint']?.toString().trim();
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: LifeMateRuntimeLocale.select(
          fa: 'دعوت ارسال شد',
          en: 'Invitation sent',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: contactHint == null || contactHint.isEmpty
              ? 'پیامک دعوت برای مراقب ارسال شد. کد محرمانه در این برنامه نمایش داده نمی‌شود.'
              : 'پیامک دعوت برای $contactHint ارسال شد. کد محرمانه در این برنامه نمایش داده نمی‌شود.',
          en: contactHint == null || contactHint.isEmpty
              ? 'The caregiver invitation was sent by SMS. The secret code is not displayed in this app.'
              : 'The caregiver invitation was sent by SMS to $contactHint. The secret code is not displayed in this app.',
        ),
      );
      setState(() => _contentRevision += 1);
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'invalid_contact' => LifeMateRuntimeLocale.select(
            fa: 'یک شماره موبایل معتبر ایران وارد کنید.',
            en: 'Enter a valid Iranian mobile number.',
          ),
        'invitation_already_pending' => LifeMateRuntimeLocale.select(
            fa: 'برای این شماره یک دعوت فعال وجود دارد.',
            en: 'An active invitation already exists for this number.',
          ),
        'self_invitation_not_allowed' => LifeMateRuntimeLocale.select(
            fa: 'نمی‌توانید شماره خودتان را به‌عنوان مراقب دعوت کنید.',
            en: 'You cannot invite your own number as a caregiver.',
          ),
        'phone_invitation_delivery_unavailable' =>
          LifeMateRuntimeLocale.select(
            fa: 'ارسال پیامک فعلاً در دسترس نیست. کمی بعد دوباره تلاش کنید.',
            en: 'SMS delivery is temporarily unavailable. Please try again later.',
          ),
        _ => LifeMateRuntimeLocale.select(
            fa: 'دعوت ارسال نشد. دوباره تلاش کنید.',
            en: 'The invitation was not sent. Please try again.',
          ),
      };
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: LifeMateRuntimeLocale.select(
          fa: 'ارسال دعوت انجام نشد',
          en: 'Invitation not sent',
        ),
        message: message,
      );
    } catch (error) {
      debugPrint('WellMate phone caregiver invitation failed: $error');
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: LifeMateRuntimeLocale.select(
          fa: 'ارسال دعوت انجام نشد',
          en: 'Invitation not sent',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: 'اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.',
          en: 'Check your connection and try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingPhoneInvitation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CareAccessScreen(
        key: ValueKey('care-access-content-$_contentRevision'),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: FilledButton.icon(
          key: const ValueKey('care-phone-invite-action'),
          onPressed: _sendingPhoneInvitation ? null : _sendPhoneInvitation,
          icon: _sendingPhoneInvitation
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sms_rounded),
          label: Text(
            LifeMateRuntimeLocale.select(
              fa: 'دعوت مراقب با شماره موبایل',
              en: 'Invite caregiver by mobile number',
            ),
          ),
        ),
      ),
    );
  }
}
