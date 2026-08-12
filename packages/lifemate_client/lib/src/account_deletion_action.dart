import 'package:flutter/material.dart';

import 'lifemate_api_client.dart';
import 'lifemate_auth.dart';
import 'runtime_locale.dart';

Future<bool> showLifeMateAccountDeletionDialog(
  BuildContext context, {
  required LifeMateApiClient apiClient,
  String? fontFamily,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'درخواست حذف حساب LifeMate',
            en: "Request to delete LifeMate account",
          ),
          en: "Request to delete LifeMate account",
        ),
        style: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w900),
      ),
      content: Text(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'با ادامه، دسترسی حساب بلافاصله غیرفعال می‌شود، ارتباط‌های اشتراک‌گذاری و دسترسی‌های فعال لغو می‌شوند و پردازش حذف/ناشناس‌سازی طبق سیاست نگهداری داده آغاز می‌شود. اطلاعاتی که نگهداری آن‌ها الزام قانونی یا ایمنی دارد فوراً پاک نمی‌شوند.',
            en: "Upon proceeding, account access will be immediately disabled, sharing connections and active accesses will be revoked, and deletion/anonymization processing will begin in accordance with the data retention policy. Information whose retention is required by law or safety is not immediately deleted.",
          ),
          en: "Upon proceeding, account access will be immediately disabled, sharing connections and active accesses will be revoked, and deletion/anonymization processing will begin in accordance with the data retention policy. Information whose retention is required by law or safety is not immediately deleted.",
        ),
        style: TextStyle(fontFamily: fontFamily, height: 1.7),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(fa: 'انصراف', en: "opt out"),
              en: "opt out",
            ),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'ادامه حذف حساب',
                en: "Continue to delete the account",
              ),
              en: "Continue to delete the account",
            ),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final typed = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _DeletionPhraseDialog(fontFamily: fontFamily),
  );
  if (typed !=
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'حذف حساب',
              en: "delete account",
            ),
            en: "delete account",
          ) ||
      !context.mounted)
    return false;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    await apiClient.requestAccountDeletion();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await LifeMateAuth.signOut();
    return true;
  } on LifeMateApiException catch (error) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!context.mounted) return false;
    await _showDeletionError(context, error.message, fontFamily);
    return false;
  } catch (_) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!context.mounted) return false;
    await _showDeletionError(
      context,
      LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'درخواست حذف ثبت نشد. اتصال را بررسی و دوباره تلاش کنید.',
          en: "The deletion request was not registered. Check the connection and try again.",
        ),
        en: "The deletion request was not registered. Check the connection and try again.",
      ),
      fontFamily,
    );
    return false;
  }
}

class _DeletionPhraseDialog extends StatefulWidget {
  const _DeletionPhraseDialog({this.fontFamily});

  final String? fontFamily;

  @override
  State<_DeletionPhraseDialog> createState() => _DeletionPhraseDialogState();
}

class _DeletionPhraseDialogState extends State<_DeletionPhraseDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: LifeMateRuntimeLocale.isPersian
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'تأیید نهایی',
              en: "Final approval",
            ),
            en: "Final approval",
          ),
          style: TextStyle(
            fontFamily: widget.fontFamily,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'برای جلوگیری از حذف تصادفی، عبارت «حذف حساب» را وارد کنید.',
                  en: "To prevent accidental deletion, enter the phrase \"delete account\".",
                ),
                en: "To prevent accidental deletion, enter the phrase \"delete account\".",
              ),
              style: TextStyle(fontFamily: widget.fontFamily, height: 1.6),
            ),
            SizedBox(height: 14),
            TextField(
              key: ValueKey('account-deletion-confirmation'),
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'حذف حساب',
                    en: "delete account",
                  ),
                  en: "delete account",
                ),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() {
                _matches =
                    value.trim() ==
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'حذف حساب',
                        en: "delete account",
                      ),
                      en: "delete account",
                    );
              }),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'انصراف', en: "opt out"),
                en: "opt out",
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: _matches
                ? () => Navigator.pop(context, _controller.text.trim())
                : null,
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'ثبت درخواست حذف',
                  en: "Registration of deletion request",
                ),
                en: "Registration of deletion request",
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showDeletionError(
  BuildContext context,
  String message,
  String? fontFamily,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    title: Text(
      LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'حذف حساب انجام نشد',
          en: "Account deletion failed",
        ),
        en: "Account deletion failed",
      ),
      style: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w900),
    ),
    content: Text(
      message,
      style: TextStyle(fontFamily: fontFamily, height: 1.6),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'متوجه شدم',
              en: "I understand",
            ),
            en: "I understand",
          ),
        ),
      ),
    ],
  ),
);
