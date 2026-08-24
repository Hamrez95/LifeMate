import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

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
    final displayName = name == null || name.isEmpty
        ? LifeMateRuntimeLocale.select(fa: 'مراقب', en: 'Caregiver')
        : name;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      LifeMateRuntimeLocale.select(
                        fa: 'درخواست کرده مراقب شما باشد',
                        en: 'Wants to be your caregiver',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading) ...[
                const SizedBox(width: 10),
                Semantics(
                  label: LifeMateRuntimeLocale.select(
                    fa: 'در حال ثبت پاسخ درخواست مراقبت',
                    en: 'Saving care request response',
                  ),
                  child: const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final stackActions = constraints.maxWidth < 320 || textScale > 1.3;
              final reject = _rejectButton();
              final accept = _acceptButton();
              if (stackActions) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    accept,
                    const SizedBox(height: 8),
                    reject,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: reject),
                  const SizedBox(width: 8),
                  Expanded(child: accept),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _rejectButton() => OutlinedButton.icon(
    key: const Key('incoming-care-request-reject'),
    onPressed: loading ? null : onReject,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      foregroundColor: const Color(0xFFE6535B),
      side: const BorderSide(color: Color(0xFFFFD7D9)),
      backgroundColor: const Color(0xFFFFF7F7),
    ),
    icon: const Icon(Icons.close_rounded),
    label: Text(
      LifeMateRuntimeLocale.select(fa: 'رد درخواست', en: 'Reject'),
    ),
  );

  Widget _acceptButton() => FilledButton.icon(
    key: const Key('incoming-care-request-accept'),
    onPressed: loading ? null : onAccept,
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      backgroundColor: AppColors.primary,
    ),
    icon: const Icon(Icons.check_rounded),
    label: Text(
      LifeMateRuntimeLocale.select(fa: 'تأیید درخواست', en: 'Accept'),
    ),
  );
}
