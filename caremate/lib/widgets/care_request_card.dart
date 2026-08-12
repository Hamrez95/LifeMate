import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import 'package:lifemate_client/lifemate_client.dart';

class CareRequestCard extends StatelessWidget {
  const CareRequestCard({
    required this.loading,
    required this.pendingRequests,
    required this.onRequest,
    required this.onCancel,
    super.key,
  });

  final bool loading;
  final List<Map<String, dynamic>> pendingRequests;
  final VoidCallback? onRequest;
  final ValueChanged<Map<String, dynamic>> onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFEAF5FF), Color(0xFFF6F1FF)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: Color(0x115A78A8),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.volunteer_activism_rounded,
                  color: AppColors.primaryBlue,
                  size: 28,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'می‌خواهی مراقب کسی باشی؟',
                          en: "Do you want to take care of someone?",
                        ),
                        en: "Do you want to take care of someone?",
                      ),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryText,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'با ایمیل WellMate او درخواست بفرست. دسترسی فقط بعد از تأیید خودش فعال می‌شود.',
                          en: "Apply with his WellMate email. Access is enabled only after self-verification.",
                        ),
                        en: "Apply with his WellMate email. Access is enabled only after self-verification.",
                      ),
                      style: TextStyle(
                        height: 1.55,
                        fontSize: 12.5,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : onRequest,
              icon: loading
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.send_rounded),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'ارسال درخواست مراقبت',
                    en: "Submit a care request",
                  ),
                  en: "Submit a care request",
                ),
              ),
            ),
          ),
          if (pendingRequests.isNotEmpty) ...[
            SizedBox(height: 16),
            Divider(height: 1),
            SizedBox(height: 12),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'درخواست‌های در انتظار',
                  en: "Pending requests",
                ),
                en: "Pending requests",
              ),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.primaryText,
              ),
            ),
            SizedBox(height: 8),
            ...pendingRequests.map(
              (request) => Padding(
                padding: EdgeInsets.only(top: 7),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(0xFFEAF4FF),
                        child: Icon(
                          Icons.alternate_email_rounded,
                          size: 18,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request['targetDisplayName']?.toString() ??
                                  LifeMateRuntimeLocale.select(
                                    fa: LifeMateRuntimeLocale.select(
                                      fa: 'در انتظار تأیید',
                                      en: "Awaiting confirmation",
                                    ),
                                    en: "Awaiting confirmation",
                                  ),
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            SizedBox(height: 2),
                            Text(
                              request['contactHint']?.toString() ?? '',
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'لغو درخواست',
                            en: "Cancel the request",
                          ),
                          en: "Cancel the request",
                        ),
                        onPressed: () => onCancel(request),
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
