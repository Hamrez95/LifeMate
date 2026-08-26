import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../models/care_home_snapshot.dart';
import '../services/companion_care_engine.dart';
import '../widgets/companion_care_guidance_card.dart';
import 'women_calendar/care_women_calendar_screen.dart';

class CompanionCareGuidanceScreen extends StatefulWidget {
  const CompanionCareGuidanceScreen({
    super.key,
    required this.summary,
    required this.isPersian,
  });

  final CareCompanionHomeSummary summary;
  final bool isPersian;

  @override
  State<CompanionCareGuidanceScreen> createState() =>
      _CompanionCareGuidanceScreenState();
}

class _CompanionCareGuidanceScreenState
    extends State<CompanionCareGuidanceScreen> {
  late CareCompanionHomeSummary _summary;
  bool _revoked = false;

  @override
  void initState() {
    super.initState();
    _summary = widget.summary;
  }

  Future<void> _recordImpression(CompanionCareGuidance guidance) async {
    final relationship = _summary.relationship;
    if (relationship == null) return;
    await WomenCompanionApi.fromEnvironment().recordGuidanceImpression(
      patientUserId: relationship.patientUserId,
      guidanceId: guidance.id,
      contentVersion: guidance.contentVersion,
      category: guidance.category,
    );
  }

  void _openSupportActions() {
    final relationship = _summary.relationship;
    if (relationship == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CareWomenCalendarScreen(
          patientUserId: relationship.patientUserId,
          patientName: relationship.patientDisplayName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final relationship = _summary.relationship;
    final font = TextStyle(
      fontFamily: widget.isPersian ? 'Vazir' : 'Nunito',
      color: const Color(0xFF2D3440),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isPersian ? 'راهنمای همراهی' : 'Support guidance'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_revoked || relationship == null)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  widget.isPersian
                      ? 'اشتراک‌گذاری این راهنما متوقف شده است. برای حفظ حریم خصوصی، پیشنهاد شخصی‌سازی‌شده دیگری نمایش داده نمی‌شود.'
                      : 'Sharing for this guidance has stopped. No further personalized suggestion is shown.',
                  style: font.copyWith(height: 1.55),
                ),
              )
            else
              CompanionCareGuidanceCard(
                summary: _summary,
                isPersian: widget.isPersian,
                font: font,
                onRevoked: () => setState(() => _revoked = true),
                onSupportRequested: _openSupportActions,
                recordImpression: _recordImpression,
              ),
            const SizedBox(height: 16),
            Text(
              widget.isPersian
                  ? 'این بخش فقط از scopeهایی استفاده می‌کند که صاحب WellMate برای همین رابطه روشن کرده است. یادداشت خصوصی، درد و علائم خصوصی وارد انتخاب پیشنهاد نمی‌شوند.'
                  : 'This view only uses scopes the WellMate owner enabled for this exact relationship. Private notes, pain, and private symptoms are never inputs to guidance selection.',
              style: font.copyWith(
                fontSize: 12,
                height: 1.55,
                color: const Color(0xFF728094),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
