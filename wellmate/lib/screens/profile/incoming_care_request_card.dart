import 'package:flutter/material.dart';

import '../../core/theme/app_style.dart';

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
    final displayName = name == null || name.isEmpty ? 'مراقب' : name;
    final photo = request['requesterProfilePhotoUrl']?.toString().trim();
    final photoUrl = photo == null || photo.isEmpty ? null : photo;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
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
            backgroundColor: const Color(0xFFEAF8F3),
            backgroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
            child: photoUrl == null
                ? const Icon(
                    Icons.person_rounded,
                    color: AppColors.primary,
                    size: 28,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'درخواست کرده مراقب شما باشد',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            Semantics(
              button: true,
              label: 'رد درخواست مراقبت $displayName',
              child: IconButton(
                tooltip: 'رد درخواست',
                onPressed: onReject,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFFFEEEE),
                  foregroundColor: const Color(0xFFE6535B),
                ),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            const SizedBox(width: 6),
            Semantics(
              button: true,
              label: 'تأیید درخواست مراقبت $displayName',
              child: IconButton(
                tooltip: 'تأیید درخواست',
                onPressed: onAccept,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFE7F8F0),
                  foregroundColor: AppColors.primary,
                ),
                icon: const Icon(Icons.check_rounded),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
