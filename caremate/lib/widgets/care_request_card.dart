import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';

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
        boxShadow: const [
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
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.volunteer_activism_rounded,
                  color: AppColors.primaryBlue,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'می‌خواهی مراقب کسی باشی؟',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryText,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'با ایمیل WellMate او درخواست بفرست. دسترسی فقط بعد از تأیید خودش فعال می‌شود.',
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
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : onRequest,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: const Text('ارسال درخواست مراقبت'),
            ),
          ),
          if (pendingRequests.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Text(
              'درخواست‌های در انتظار',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 8),
            ...pendingRequests.map(
              (request) => Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(0xFFEAF4FF),
                        child: Icon(
                          Icons.alternate_email_rounded,
                          size: 18,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request['targetDisplayName']?.toString() ??
                                  'در انتظار تأیید',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              request['contactHint']?.toString() ?? '',
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'لغو درخواست',
                        onPressed: () => onCancel(request),
                        icon: const Icon(
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
