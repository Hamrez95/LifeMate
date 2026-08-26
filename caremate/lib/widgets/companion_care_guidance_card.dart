import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../models/care_home_snapshot.dart';
import '../services/companion_care_engine.dart';

class CompanionCareGuidanceCard extends StatefulWidget {
  const CompanionCareGuidanceCard({
    super.key,
    required this.summary,
    required this.isPersian,
    required this.font,
    required this.onRevoked,
    required this.onSupportRecorded,
  });

  final CareCompanionHomeSummary summary;
  final bool isPersian;
  final TextStyle font;
  final VoidCallback onRevoked;
  final Future<void> Function() onSupportRecorded;

  @override
  State<CompanionCareGuidanceCard> createState() =>
      _CompanionCareGuidanceCardState();
}

class _CompanionCareGuidanceCardState
    extends State<CompanionCareGuidanceCard> {
  static const _engine = CompanionCareEngine();

  CompanionCareGuidance? _guidance;
  String? _recordedKey;
  bool _recordingSupport = false;

  @override
  void initState() {
    super.initState();
    _reselect();
  }

  @override
  void didUpdateWidget(covariant CompanionCareGuidanceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reselect();
  }

  void _reselect() {
    final summary = widget.summary;
    if (!summary.hasPermission ||
        !summary.available ||
        summary.relationship == null) {
      _guidance = null;
      return;
    }
    final selected = _engine.select(
      phaseAllowed: summary.phaseAllowed,
      wellbeingAllowed: summary.wellbeingAllowed,
      cycleDay: summary.cycleDay,
      mood: summary.mood,
      energyLevel: summary.energyLevel,
      guidanceHistory: summary.guidanceHistory
          .map(
            (item) => CompanionGuidanceHistoryItem(
              guidanceId: item.guidanceId,
              shownAtUtc: item.shownAtUtc,
            ),
          )
          .toList(growable: false),
      supportActions: summary.supportActions
          .map(
            (item) => CompanionSupportActionHistoryItem(
              actionType: item.actionType,
              performedAtUtc: item.performedAtUtc,
            ),
          )
          .toList(growable: false),
      locale: widget.isPersian ? 'fa' : 'en',
      nowUtc: DateTime.now().toUtc(),
    );
    _guidance = selected;
    if (selected != null) {
      final key =
          '${summary.relationship!.patientUserId}:${selected.contentVersion}:${selected.id}';
      if (_recordedKey != key) {
        _recordedKey = key;
        unawaited(
          _recordImpression(selected, summary.relationship!.patientUserId),
        );
      }
    }
  }

  Future<void> _recordImpression(
    CompanionCareGuidance guidance,
    String patientUserId,
  ) async {
    final api = WomenCompanionApi.fromEnvironment();
    try {
      await api.recordGuidanceImpression(
        patientUserId: patientUserId,
        guidanceId: guidance.id,
        contentVersion: guidance.contentVersion,
        category: guidance.category,
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'women_calendar_access_denied' ||
          error.code == 'person_access_denied') {
        setState(() => _guidance = null);
        widget.onRevoked();
      }
    }
  }

  Future<void> _recordSupport() async {
    final guidance = _guidance;
    final relationship = widget.summary.relationship;
    final action = guidance?.supportActionType;
    if (guidance == null ||
        relationship == null ||
        action == null ||
        _recordingSupport) {
      return;
    }
    setState(() => _recordingSupport = true);
    try {
      final api = LifeMateApiClient(
        baseUri: AppConfig.fromEnvironment().apiBaseUri,
        accessToken: () => null,
      );
      api.close();
      // Existing support-action UI remains authoritative for marking support;
      // the dashboard guidance CTA only navigates to that flow to avoid a
      // second network client and duplicated mutation semantics.
      if (!mounted) return;
      setState(() => _guidance = null);
      await widget.onSupportRecorded();
    } finally {
      if (mounted) setState(() => _recordingSupport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final guidance = _guidance;
    if (guidance == null) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('companion-care-guidance-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE5EBF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.favorite_outline_rounded,
                color: Color(0xFF6F7DD8),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  guidance.title,
                  style: widget.font.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            guidance.message,
            style: widget.font.copyWith(
              fontSize: 12.5,
              height: 1.6,
              color: const Color(0xFF5E6B7D),
            ),
          ),
          if (guidance.supportActionType != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonal(
                onPressed: _recordingSupport ? null : _recordSupport,
                child: Text(
                  guidance.supportActionLabel ??
                      (widget.isPersian ? 'ثبت حمایت' : 'Record support'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            widget.isPersian
                ? 'این پیشنهاد تشخیص یا توصیه پزشکی نیست و فقط از اطلاعاتی استفاده می‌کند که برای شما به‌اشتراک گذاشته شده است.'
                : 'This is not a diagnosis or medical advice and only uses information shared with you.',
            style: widget.font.copyWith(
              fontSize: 10,
              height: 1.45,
              color: const Color(0xFF8A96A8),
            ),
          ),
        ],
      ),
    );
  }
}
