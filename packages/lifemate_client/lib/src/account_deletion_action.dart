import 'package:flutter/material.dart';

import 'lifemate_api_client.dart';
import 'lifemate_auth.dart';

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
        'درخواست حذف حساب LifeMate',
        style: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w900),
      ),
      content: Text(
        'با ادامه، دسترسی حساب بلافاصله غیرفعال می‌شود، ارتباط‌های اشتراک‌گذاری و دسترسی‌های فعال لغو می‌شوند و پردازش حذف/ناشناس‌سازی طبق سیاست نگهداری داده آغاز می‌شود. اطلاعاتی که نگهداری آن‌ها الزام قانونی یا ایمنی دارد فوراً پاک نمی‌شوند.',
        style: TextStyle(fontFamily: fontFamily, height: 1.7),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('انصراف'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('ادامه حذف حساب'),
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
  if (typed != 'حذف حساب' || !context.mounted) return false;

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
      'درخواست حذف ثبت نشد. اتصال را بررسی و دوباره تلاش کنید.',
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
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'تأیید نهایی',
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
              'برای جلوگیری از حذف تصادفی، عبارت «حذف حساب» را وارد کنید.',
              style: TextStyle(fontFamily: widget.fontFamily, height: 1.6),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('account-deletion-confirmation'),
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'حذف حساب',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() {
                _matches = value.trim() == 'حذف حساب';
              }),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: _matches
                ? () => Navigator.pop(context, _controller.text.trim())
                : null,
            child: const Text('ثبت درخواست حذف'),
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
      'حذف حساب انجام نشد',
      style: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w900),
    ),
    content: Text(message, style: TextStyle(fontFamily: fontFamily, height: 1.6)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('متوجه شدم'),
      ),
    ],
  ),
);
