import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:qr_flutter/qr_flutter.dart';

Future<void> showCarePairingQrDialog({
  required BuildContext context,
  required String token,
  required String? expiresAtUtc,
}) async {
  final payload = CarePairingQr.encodeToken(token);
  final expiresAt = expiresAtUtc == null
      ? null
      : DateTime.tryParse(expiresAtUtc)?.toLocal();

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: const Row(
        children: [
          Icon(Icons.qr_code_2_rounded),
          SizedBox(width: 10),
          Expanded(child: Text('اتصال امن CareMate')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'در CareMate گزینه «اسکن QR» را بزنید و این تصویر را فقط به مراقب مورد اعتماد نشان دهید.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.55),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE5ECE8)),
              ),
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 230,
                semanticsLabel: 'کد اتصال مراقب LifeMate',
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                expiresAt == null
                    ? 'این دعوت کوتاه‌مدت و یک‌بارمصرف است.'
                    : 'مهلت استفاده: ${_formatDateTime(expiresAt)}؛ پس از پذیرش یا پایان مهلت، QR دیگر معتبر نیست.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8B5E12),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: token));
            if (dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('کد پشتیبان کپی شد.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('کپی کد پشتیبان'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('تمام'),
        ),
      ],
    ),
  );
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}/${two(value.month)}/${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
