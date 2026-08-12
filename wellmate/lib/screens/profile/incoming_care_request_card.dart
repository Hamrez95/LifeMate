import 'package:flutter/material.dart';

import '../../core/theme/app_style.dart';
import 'package:lifemate_client/lifemate_client.dart';

class IncomingCareRequestCard extends StatelessWidget {
  const IncomingCareRequestCard({
    required this.request,
    required this.loading,
    required this.onAccept,
    required this.onReject,
    super.key,
  });

  final Map<String, dynamic> request;
  final bool loading;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final name = request['requesterDisplayName']?.toString().trim();
    final displayName = name == null || name.isEmpty
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: 'مراقب', en: "Caregiver"),
            en: "Careful",
          )
        : name;
    final photo = request['requesterProfilePhotoUrl']?.toString().trim();
    final photoUrl = photo == null || photo.isEmpty ? null : photo;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Color(0x0D27493D),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: Color(0xFFEAF8F3),
            backgroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
            child: photoUrl == null
                ? Icon(Icons.person_rounded, color: AppColors.primary, size: 28)
                : null,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.darkBlue,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'درخواست کرده مراقب شما باشد',
                      en: "He asked to take care of you",
                    ),
                    en: "He asked to take care of you",
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            Semantics(
              button: true,
              label: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'رد درخواست مراقبت $displayName',
                  en: "$displayName maintenance request rejected",
                ),
                en: "$displayName maintenance request rejected",
              ),
              child: IconButton(
                tooltip: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'رد درخواست',
                    en: "Request rejection",
                  ),
                  en: "Request rejection",
                ),
                onPressed: onReject,
                style: IconButton.styleFrom(
                  backgroundColor: Color(0xFFFFEEEE),
                  foregroundColor: Color(0xFFE6535B),
                ),
                icon: Icon(Icons.close_rounded),
              ),
            ),
            SizedBox(width: 6),
            Semantics(
              button: true,
              label: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تأیید درخواست مراقبت $displayName',
                  en: "Confirm care request $displayName",
                ),
                en: "Confirm care request $displayName",
              ),
              child: IconButton(
                tooltip: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'تأیید درخواست',
                    en: "Request confirmation",
                  ),
                  en: "Request confirmation",
                ),
                onPressed: onAccept,
                style: IconButton.styleFrom(
                  backgroundColor: Color(0xFFE7F8F0),
                  foregroundColor: AppColors.primary,
                ),
                icon: Icon(Icons.check_rounded),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
