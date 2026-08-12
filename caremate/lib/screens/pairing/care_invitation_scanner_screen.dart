import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/constants/app_colors.dart';

class CareInvitationScannerScreen extends StatefulWidget {
  const CareInvitationScannerScreen({super.key});

  @override
  State<CareInvitationScannerScreen> createState() =>
      _CareInvitationScannerScreenState();
}

class _CareInvitationScannerScreenState
    extends State<CareInvitationScannerScreen> {
  bool _handled = false;
  String? _message;

  void _handleCapture(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final token = CarePairingQr.tryParseToken(barcode.rawValue);
      if (token == null) continue;
      _handled = true;
      Navigator.of(context).pop(token);
      return;
    }
    if (mounted) {
      setState(
        () => _message = LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'این QR متعلق به دعوت LifeMate نیست.',
            en: "This QR does not belong to LifeMate Invitation.",
          ),
          en: "This QR does not belong to LifeMate Invitation.",
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'اسکن دعوت مراقبت',
              en: "Scan invitation to care",
            ),
            en: "Scan invitation to care",
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: _handleCapture,
            errorBuilder: (context, error) =>
                _CameraError(message: error.errorDetails?.message),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.primaryBlue, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 0,
                      spreadRadius: 1000,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 18, 24, 26),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'QR نمایش‌داده‌شده در WellMate بیمار را داخل کادر قرار دهید.',
                          en: "Enter the QR displayed on the patient's WellMate into the box.",
                        ),
                        en: "Enter the QR displayed on the patient's WellMate into the box.",
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, height: 1.5),
                    ),
                  ),
                  Spacer(),
                  if (_message != null)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.no_photography_rounded, color: Colors.white, size: 58),
              SizedBox(height: 16),
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'دسترسی دوربین برای اسکن QR لازم است.',
                    en: "Camera access is required to scan QR.",
                  ),
                  en: "Camera access is required to scan QR.",
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (message != null && message!.trim().isNotEmpty) ...[
                SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ],
              SizedBox(height: 18),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white54),
                ),
                child: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'بازگشت و ورود دستی کد',
                      en: "Return and manual code entry",
                    ),
                    en: "Return and manual code entry",
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
