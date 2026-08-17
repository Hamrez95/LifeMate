import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/utils/iranian_mobile_input.dart';

Future<String?> showCarePhoneInviteDialog(BuildContext context) async {
  final phoneController = TextEditingController();
  var confirmed = false;
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final normalized = normalizeIranianMobileInput(phoneController.text);
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              LifeMateRuntimeLocale.select(
                fa: 'دعوت مراقب با شماره موبایل',
                en: 'Invite caregiver by mobile number',
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: LifeMateRuntimeLocale.select(
                      fa: 'شماره موبایل مراقب',
                      en: 'Caregiver mobile number',
                    ),
                    hintText: '0912 123 4567',
                    helperText: LifeMateRuntimeLocale.select(
                      fa: 'شماره موبایل ایران را وارد کنید.',
                      en: 'Enter an Iranian mobile number.',
                    ),
                    errorText: phoneController.text.trim().isNotEmpty &&
                            normalized == null
                        ? LifeMateRuntimeLocale.select(
                            fa: 'شماره موبایل معتبر نیست.',
                            en: 'Enter a valid Iranian mobile number.',
                          )
                        : null,
                    prefixIcon: const Icon(Icons.phone_iphone_rounded),
                    filled: true,
                    fillColor: const Color(0xFFF6FAF8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: confirmed,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (value) =>
                      setDialogState(() => confirmed = value ?? false),
                  title: Text(
                    LifeMateRuntimeLocale.select(
                      fa: 'اجازه می‌دهم این فرد وضعیت برنامه و مصرف داروهای من را ببیند. هر زمان بخواهم می‌توانم دسترسی را قطع کنم.',
                      en: 'I allow this person to see my schedule and medication status. I can terminate access at any time.',
                    ),
                    style: const TextStyle(height: 1.55, fontSize: 12.5),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  LifeMateRuntimeLocale.select(
                    fa: 'کد یک‌بارمصرف مستقیماً با پیامک برای همین شماره ارسال می‌شود و در این برنامه نمایش داده نمی‌شود.',
                    en: 'The one-time code is sent directly to this number by SMS and is not displayed in this app.',
                  ),
                  style: const TextStyle(
                    height: 1.5,
                    fontSize: 11.5,
                    color: Color(0xFF667085),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  LifeMateRuntimeLocale.select(fa: 'انصراف', en: 'Cancel'),
                ),
              ),
              FilledButton(
                onPressed: confirmed && normalized != null
                    ? () => Navigator.pop(dialogContext, normalized)
                    : null,
                child: Text(
                  LifeMateRuntimeLocale.select(
                    fa: 'ارسال دعوت',
                    en: 'Send invitation',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    phoneController.dispose();
  }
}
