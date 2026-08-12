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
      title: Row(
        children: [
          Icon(Icons.qr_code_2_rounded),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'اتصال امن CareMate',
                  en: "CareMate secure connection",
                ),
                en: "CareMate secure connection",
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'در CareMate گزینه «اسکن QR» را بزنید و این تصویر را فقط به مراقب مورد اعتماد نشان دهید.',
                  en: "Tap \"Scan QR\" in CareMate and show this image only to a trusted caregiver.",
                ),
                en: "Tap \"Scan QR\" in CareMate and show this image only to a trusted caregiver.",
              ),
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.55),
            ),
            SizedBox(height: 18),
            Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Color(0xFFE5ECE8)),
              ),
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 230,
                semanticsLabel: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'کد اتصال مراقب LifeMate',
                    en: "LifeMate Caregiver Connection Code",
                  ),
                  en: "LifeMate Caregiver Connection Code",
                ),
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
            SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color(0xFFFFF7E8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                expiresAt == null
                    ? LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'این دعوت کوتاه‌مدت و یک‌بارمصرف است.',
                          en: "This invitation is short-term and disposable.",
                        ),
                        en: "This invitation is short-term and disposable.",
                      )
                    : LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'مهلت استفاده: ${_formatDateTime(expiresAt)}؛ پس از پذیرش یا پایان مهلت، QR دیگر معتبر نیست.',
                          en: "Expiry date: ${_formatDateTime(expiresAt)}; Once accepted or expired, the QR is no longer valid.",
                        ),
                        en: "Expiry date: ${_formatDateTime(expiresAt)}; Once accepted or expired, the QR is no longer valid.",
                      ),
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
                SnackBar(
                  content: Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'کد پشتیبان کپی شد.',
                        en: "Backup code copied.",
                      ),
                      en: "Backup code copied.",
                    ),
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          icon: Icon(Icons.copy_rounded),
          label: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'کپی کد پشتیبان',
                en: "Copy the backup code",
              ),
              en: "Copy the backup code",
            ),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(fa: 'تمام', en: "all"),
              en: "all",
            ),
          ),
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
